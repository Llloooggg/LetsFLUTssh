# Security Policy

LetsFLUTssh is an open-source SSH / SFTP client. This document describes
the threat model the app is designed to protect against, the boundary
of what app-level code can and cannot achieve, and the vulnerability
reporting process. It is written for users, security researchers, and
contributors; readers who want the code-level reference (module map,
class API, data flow, testing hooks) should head to
[`docs/ARCHITECTURE.md §3.6 Security`](../docs/ARCHITECTURE.md).

## Scope

### What the app protects

- **Cold-disk theft** — someone powers off the machine, removes the
  drive, and reads it elsewhere; or copies the encrypted database off
  a running machine with filesystem access. Covered in varying degree
  by every tier above plaintext.
- **Bystander at an unlocked machine** — a coworker / family member
  taps the app while the legitimate user is away. Covered by any tier
  that holds a typed secret (password modifier or Paranoid).
- **Off-device key extraction** — stolen backup, rooted clone of the
  drive, or leaked OS keychain snapshot. The hardware-bound tier
  (T2) provides specific protection against this class by wrapping
  the database key under a chip-held key; the sealed blob is
  unusable without the original device's TPM / Secure Enclave /
  StrongBox.
- **OS keychain compromise** — CVE in the OS credential store,
  keychain exfiltration tool. The Paranoid alternative is the only
  provider that survives this: it derives the key per unlock from a
  master password through Argon2id and keeps nothing in any OS-
  managed storage.
- **Weak passwords against offline brute force** — when the wrapped
  key is bound to a hardware chip (T2), an attacker cannot attempt
  passwords off-device at all. When the key is derived from the
  password directly (Paranoid), Argon2id slows attempts but does not
  block a determined attacker against a short password.
- **Release binary tampering** — the auto-update channel rejects
  unsigned or mis-signed artefacts via a pinned Ed25519 public key
  baked into the installed binary. See the **Release signing**
  section below.

### What the app does not protect against

The app is a user-space Flutter binary running in the user's OS
session. It does not pretend to defend against attackers operating at
or above its own privilege level:

- **Privileged same-user attacker** — root, admin, `SeDebug`
  privilege, jailbreak, or a debug-signed process with permission to
  attach to our process. Full-RAM dump is available to this attacker
  class and defeats every tier. App-level hardening does not change
  this.
- **Kernel-level exploits** — CVEs in the OS kernel, hardware chip
  firmware backdoors, or supply-chain compromise of the Dart VM /
  Flutter engine / platform libraries. The Paranoid alternative is
  the only tier that keeps the wrapped key out of OS-managed storage,
  but even Paranoid does not protect the running unlocked process
  from a kernel-level reader.
- **Physical cold-RAM forensics** — attacker freezes the RAM of a
  running or locked machine and extracts still-resident key
  material via DMA or chip-off. `mlock` / `VirtualLock` keep keys out
  of swap but do nothing against in-RAM physical attacks.
- **Malicious input-method editors** — third-party keyboards on
  Android that buffer typed text for autocorrect / cloud sync. The
  password leaves our process the moment it is typed, before any
  app-level code sees it. Use the system keyboard for password
  fields; this is a user-side discipline the app does not try to
  enforce with a non-actionable warning.
- **Upstream dependency vulnerabilities** — `russh` and the broader
  RustCrypto stack vendored at `rust/`, `pointycastle`, `xterm`,
  Flutter itself. Report those to the respective maintainers. Scope
  for this repository is strictly the code we wrote.

## Threat boundary

The defensive boundary is **OS process isolation + capabilities**, not
"same user account". Same-user malware is a family of attackers
ranging from unprivileged scripts (`python stealer.py`, unsigned
installer dropped by a browser) to elevated debug-capable processes.

- **Unprivileged same-user code** (no `SeDebug` / `CAP_SYS_PTRACE` /
  debug signing) → blocked by the OS from attaching to our process:
  `PR_SET_DUMPABLE=0` on Linux, `ptrace PT_DENY_ATTACH` on macOS,
  `SetProcessMitigationPolicy` on Windows, sandbox on mobile. The
  attacker sees our files — if the tier protects the file-level state
  (T1 / T2 / Paranoid all do) the attacker gets only ciphertext.
- **Privileged same-user code** (elevated debug privilege / root /
  jailbreak) → can read our process memory directly. Nothing at app
  level closes this. These threats are deliberately omitted from the
  in-app per-tier comparison table (every tier is ✗, so the row adds
  no signal to the user's tier choice) and are called out here
  instead so the gap stays explicit rather than hidden.

## KEK provider hierarchy

The app encrypts the SQLite database under a single 256-bit key. The
hierarchy below describes how that key — the "key-encryption-key" or
KEK, following the industry term — is produced and stored. Choosing
between these providers is a security-model decision; choosing
between the orthogonal modifiers described in the next section is a
UX decision on top of that choice.

### Base — OS-managed key storage (T1)

The default. The database key is held in the OS keychain
(`Keychain` on Apple, `Credential Manager` on Windows, `libsecret` on
Linux, `EncryptedSharedPreferences` on Android). On Apple, Android,
and Windows the OS keychain is itself hardware-backed (Secure Enclave,
StrongBox / TEE, DPAPI with TPM binding) — the effective guarantee is
hardware-bound-via-OS. On Linux `libsecret` has no TPM integration;
this is flagged honestly in the per-platform backing matrix below.

- Recoverable: replacing the device is transparent as long as the
  user can transfer the keychain, and `.lfs` archives carry
  everything except the security configuration itself (which is
  re-established by the wizard on the new device).
- Convenient: first-launch wizard prefers this tier when no hardware
  vault is available.

### Upgrade — hardware-bound key (T2)

An opt-in advanced option. The database key is wrapped directly by
the hardware chip (Secure Enclave / StrongBox / TPM 2.0), producing a
sealed blob that lives on the file system. The OS keychain is **not
in the path**. The chip refuses to unseal without the original device.

- Adds **off-device extraction resistance** on top of T1. An attacker
  with a disk image, a stolen backup, or an exfiltrated keychain
  snapshot cannot decrypt the sealed blob elsewhere.
- **Does not improve runtime protection.** A malicious process with
  access to our running app will trigger the chip to unseal just as
  easily as it would read a keychain entry. T2's value lives
  entirely in the at-rest / off-device axis.
- **Trades against recoverability.** A lost or replaced device chip
  means the sealed blob cannot be unsealed again anywhere. The user
  needs to re-run the wizard on the new device and re-add their
  sessions from a `.lfs` archive or manual re-entry. The wizard
  warns about this in its T2 subtitle.

### Escape — derived-only (Paranoid)

A separate branch, not a "higher tier". The database key is **not
persisted** anywhere. The user chooses a master password; on every
unlock the key is derived per-session through Argon2id (46 MiB / 2
iterations / 1 lane — OWASP 2024 recommended floor, per
`KdfParams.productionDefaults`) and lives only in a page-locked
native buffer during the unlocked window. On lock the buffer is
zeroed and freed.

- **Protects against OS compromise + locked-machine RAM forensics.**
  These are the threats the numbered tiers cannot close — any tier
  that persists the key via the OS loses to a kernel / keychain CVE
  or a cold-RAM attack on the locked app. Paranoid keeps nothing
  persistently, so there is nothing to steal from the locked state.
- **Does not improve runtime protection for the unlocked app.** The
  derived key has to be in memory to decrypt database pages; while
  unlocked, Paranoid is no harder to attack in-process than T1 or T2.
- Weak passwords are a real vulnerability for Paranoid — Argon2id
  slows brute force but does not block a determined attacker against
  a 4-digit password. A long passphrase is the actual defence. The
  wizard subtitle carries this honesty note inline.

### Per-platform trust-backing matrix

The strength of each tier varies by platform. This is a property of
the underlying OS keychain / hardware API, not of our code. The
wizard and Settings surface the active backing level as a subtitle
("Backing: Hardware / TEE / Secure Enclave / software") so users see
exactly what they are relying on.

| Platform | T1 backing | T2 backing |
|---|---|---|
| iOS | Keychain → Secure Enclave | Secure Enclave (direct) |
| macOS | Keychain → Secure Enclave (T2 chip / Apple Silicon) or software-only on older Intel | Secure Enclave (direct); T2 unavailable on older Intel Macs |
| Android | EncryptedSharedPreferences → Keystore (StrongBox / TEE) | Keystore direct (StrongBox / TEE) |
| Windows | Credential Manager → DPAPI (TPM-bound when available) | CNG / NCrypt direct → TPM 2.0 |
| Linux | libsecret → **software-only** (no TPM integration in `libsecret`) | TPM 2.0 direct via `tpm2-tools` |

**Linux notes.** T1 on Linux is the weakest default across the
matrix because `libsecret` does not integrate with TPM. Users who
want hardware binding on Linux should pick T2 (requires a TPM 2.0 +
`tpm2-tools`; install snippet in the main README). The biometric
modifier on Linux flows through `fprintd` and requires at least one
enrolled finger.

## Orthogonal modifiers

Modifiers are applied on top of a chosen KEK provider. They change
the UX of the unlock path, not the KEK provider itself. They are
"orthogonal" in the strict sense: the modifier set does not affect
which off-device / cold-disk / OS-compromise threats the tier
defeats. What it affects is `bystanderUnlockedMachine`, the runtime
brute-force surface, and the set of UX moments during which the user
is prompted for a secret.

- **password** — user-typed secret. On T1 it is the primary auth
  gate: the app compares an HMAC of the typed password against a
  stored value before the keychain is touched, so a wrong password
  fails without consulting the OS keychain. On T2 it is the
  hardware-chip auth value (Linux / Windows) or a pre-unseal HMAC
  gate (Apple / Android). Paranoid requires a password by design —
  the key is derived from it.
- **biometric** — shortcut that releases the typed password from a
  biometric-gated OS slot so the user does not retype it. **Biometric
  requires password** by invariant: biometric is a shortcut for
  entering the password, never a replacement. The slot is gated by
  the platform biometric ACL (`biometryCurrentSet` on Apple,
  `setInvalidatedByBiometricEnrollment(true) + BiometricPrompt` on
  Android, `fprintd` on Linux, CNG `NCRYPT_UI_PROTECT_KEY_FLAG` on
  the Hello-gated overlay key on Windows). Re-enrolling biometrics
  invalidates the slot and forces a password re-entry.

## Orthogonal mitigations

These apply across every KEK provider and every modifier combo. They
do not change what a tier protects against at rest; they shrink the
attack surface during the running unlocked window, and close
ancillary leakage channels that are independent of the tier
architecture.

- **Encrypted `.lfs` export / import** — Argon2id-derived AES-256-GCM
  key, pre-decrypt size cap, atomic tmp-then-rename writes, and a
  mandatory manifest. v1 is the permanent floor; any archive whose
  header version byte is not the current Argon2id one, whose magic is
  missing, or whose manifest `schema_version` does not match is
  rejected with `UnsupportedLfsVersionException` — users re-export
  from the current app version to cross upgrade boundaries. Archives
  never carry per-machine security setup.
- **Auto-lock** — idle-timer lock + mobile lifecycle-paused lock +
  OS workstation-lock hook. Any tier with a typed secret arms the
  timer (Paranoid + any tier with the password modifier). Locking
  the OS (`Win+L`, `Ctrl+Cmd+Q`, GNOME lock) routes through
  `SessionLockListener` — Windows WTS, macOS
  `NSDistributedNotificationCenter`, Linux systemd-logind D-Bus — so
  the in-app lock fires even when the user hasn't been idle long
  enough to trip the timer. **Every lock unconditionally wipes the
  DB key and closes the drift / SQLite3MultipleCiphers handle**,
  zeroing both the Dart-side `SecretBuffer` and the C-layer
  page-cipher cache (the live cipher is ChaCha20-Poly1305).
  Previously the wipe was gated on "no active SSH sessions" so the
  user's reconnect UX survived; that gate left the DB key warm
  whenever any session was connected, which flattened T1+password
  and T2+password in the threat matrix. The gate is gone now. Live
  sessions stay reconnectable through a per-session credential
  cache (`SessionCredentialCache`) — each session's password / key
  bytes / passphrase are kept in `mlock`-pinned native memory
  outside the encrypted store, so closing the store on lock does
  not cost the user their connections. The cache is evicted on
  explicit disconnect, on any wipe / reset path, and on app
  shutdown.
- **Page-locked in-memory secrets** — DB key, Argon2id-derived keys,
  and biometric-stored passwords live in FFI-allocated buffers
  locked into physical RAM with `mlock` (POSIX) or `VirtualLock`
  (Windows), zeroed and unlocked on dispose. They cannot page to
  swap or hibernate.
- **Hardened password entry** — every secret-entry field goes
  through `SecurePasswordField`, which forces `autocorrect`,
  `enableSuggestions`, `enableIMEPersonalizedLearning`, smart-quote
  substitution, and text-capitalisation hinting off so a typed
  master password cannot feed the OS spellcheck dictionary,
  predictive-text history, or IME personalisation model. The
  controller is wiped on dispose — `text` overwritten with
  same-length null bytes, then cleared — so the widget no longer
  references the secret `String` by the time the parent state
  tears down. On obscured fields the context menu is stubbed out
  entirely so paste / share / dictation / lookup cannot surface
  the buffer content. The widget is a single Dart implementation
  on all five OSes: Flutter's engine bridges `obscureText` +
  `visiblePassword` keyboard to the native secure-input field
  (`TYPE_TEXT_VARIATION_PASSWORD` / `UITextField.isSecureTextEntry`)
  where the OS offers one, which covers IME-learning suppression
  on every platform and screen-recording blackout on iOS. The one
  OS-level primitive the Flutter bridge does not request is macOS
  `EnableSecureEventInput()` (HID-level keylogger block) — a Mac
  user concerned about a keylogger with Accessibility permission
  should deny Accessibility to untrusted apps in System Settings →
  Privacy & Security → Accessibility, which is the macOS-standard
  mitigation for that threat regardless of how the app renders
  its text field.
- **Process hardening at startup** — `prctl(PR_SET_DUMPABLE, 0)` on
  Linux / Android (no core dumps, no `gdb -p` from same UID without
  `CAP_SYS_PTRACE`), `ptrace(PT_DENY_ATTACH)` on macOS,
  `SetErrorMode` / mitigation policies on Windows (suppresses WER
  crash dumps that would otherwise contain the cipher key).
- **Clipboard hygiene** — password / token / passphrase copies
  route through `SecureClipboard.setText`, which declares the
  per-OS "don't sync, don't history" markers in the same system
  call as the text (`CanIncludeInClipboardHistory` +
  `CanUploadToCloudClipboard` on Windows, nspasteboard
  transient/concealed types on macOS, `localOnly` +
  `expirationDate` on iOS, `ClipDescription.EXTRA_IS_SENSITIVE`
  on Android 13+). A 30-second auto-wipe timer on top only clears
  the clipboard when the live value still matches what the app
  wrote, so a user who copied something else mid-window never loses
  their own data.
- **Known hosts / TOFU verification** — DB-backed; the host-key
  callback refuses silent changes and surfaces an unambiguous dialog
  with both fingerprints.
- **Deep-link URI parsing** — `letsflutssh://` scheme with host / port
  validation and path-traversal rejection.
- **File permission handling** — `chmod 600` on credentials,
  known_hosts, and config files after every write. Atomic
  write-to-temp-then-rename prevents corruption on crash.
- **SFTP recursion depth limit** (100 levels) — prevents stack
  overflow on malicious server paths.
- **Error message sanitization** — file paths, IPs, and
  `user@host` fragments stripped from user-facing and logged errors.
- **Reset all data** — Settings → Security carries a single
  destructive reset path. Clears every managed file, every OS
  keychain entry in the app namespace, every native hw-vault
  Keystore / SE / TPM key, and the log directory. Writes a
  `.wipe-pending` marker first so a crash mid-wipe resumes
  idempotently on the next launch. Needed on desktop, where app
  uninstall does not reliably purge keychain entries
  (`macOS` / `Windows` / `Linux` leak).

## Combined threat matrix

The full truth table ships in-app under **Settings → Security →
Compare all tiers** and is the same matrix the wizard exposes. It is
generated directly from the canonical `SecurityThreat` /
`ThreatStatus` vocabulary in `lib/core/security/threat_vocabulary.dart`
so this document and the UI cannot drift. Short summary:

| Threat | T0 | T1 | T1 + pw | T2 | T2 + pw | Paranoid |
|---|---|---|---|---|---|---|
| Cold disk theft | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Keyring / keychain file exfiltration | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |
| Offline brute force on password | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ |
| Bystander at unlocked machine | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ |
| RAM forensics on locked machine | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ |
| OS kernel / keychain breach | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ |

*Deliberately omitted:* same-user malware and live process memory
dump are ✗ on every tier. Including them in the per-tier table would
add no signal for the user's tier choice (the row shape is identical
across T0…Paranoid); they are covered in the threat-boundary
discussion above instead, so the gap stays explicit without
flattening the comparison. The orthogonal mitigations — process
hardening (`PR_SET_DUMPABLE=0`, `PT_DENY_ATTACH`,
`SetProcessMitigationPolicy`), `mlock` on the derived key,
DB-close-on-lock, auto-lock — raise the bar against unprivileged
same-user code; a privileged same-user attacker defeats everything
at app level, same as every commercial password manager, SSH client,
or crypto wallet on consumer hardware.

*Per-row rationale:*

* **Keyring / keychain file exfiltration** splits T1 from T2 without
  a password: T1 keeps the wrapped key inside the OS keychain file
  (libsecret `login.keyring`, Windows `Credential Manager .vcrd`,
  macOS `login.keychain-db`) — a disk attacker reads the file offline
  and recovers the key. T2 stores the wrapped blob on disk but the
  unwrap key is inside the TPM / Secure Enclave / StrongBox; the chip
  refuses key export regardless of whether an auth value is set, so
  the on-disk blob is useless without the physical hardware.
* **Offline brute force** is ✓ only when a user password is set —
  the threat as formulated ("attacker tries passwords offline") does
  not apply without a password, and Argon2id with production
  parameters (46 MiB / 2 iterations / 1 lane — the OWASP 2024 floor
  per `KdfParams.productionDefaults`) is what turns brute-force
  attempts into a wall-clock problem. T2 + pw gets the
  same ✓ as T1 + pw because the blob-plus-chip requirement adds to
  (not replaces) the Argon2id cost; removing the pw on T2 drops the
  row to ✗ symmetrically with T1.
* **RAM forensics on locked machine** and **OS kernel / keychain
  breach** split T1 + pw from T2 + pw because the always-wipe-on-lock
  policy zeroes the DB key the moment the lock fires, so what remains
  of the wrapping key at rest differs by tier. T1 keeps its wrapping
  key in the OS keychain daemon — a separate process, outside the
  app's wipe reach — so a RAM dump of the locked device still finds
  the daemon's copy and a kernel / keychain breach reads the daemon
  memory or the `login.keyring` / `.vcrd` file directly; T1 + pw
  stays ✗. T2 keeps its wrapping key inside the TPM / Secure Enclave
  / StrongBox / Windows Hello NCrypt handle; the on-disk blob is
  ciphertext the chip refuses to export (`NCRYPT_EXPORT_POLICY`
  rejects export, Secure Enclave attributes mark the key
  non-extractable, TPM sealed blobs are bound to the TPM's storage
  key), and unsealing requires the chip to answer a user-auth prompt
  that is rate-limited by hardware lockout. Kernel breach can drive
  the chip but not faster than the lockout allows. T2 + pw becomes
  ✓. Paranoid remains ✓ by construction — the key is derived per
  unlock via Argon2id + master password and never persisted, so no
  at-rest key exists for either vector to reach.

## Import / export

`.lfs` archives carry portable user data — sessions, SSH keys,
known_hosts, snippets, tags, and user preferences. They **never
carry** `security_tier` or `security_modifiers`. Security
configuration is strictly per-install: importing on a device B an
archive made on device A does not try to adopt device A's
hardware-vault setup; device B's existing security setup is
preserved. Users re-run the wizard only when setting up a new device
from scratch.

The encryption format is AES-256-GCM under an Argon2id-derived key,
with the `LFSE 0x02` header carrying the KDF parameters. The import
path enforces parameter caps (`maxImportArgon2idMemoryKiB`,
`maxImportArgon2idIterations`, `maxImportArgon2idParallelism`) so a
hostile header cannot pin the isolate into swap. Archives declaring
a schema version the current build does not understand are rejected
with `UnsupportedLfsVersionException` rather than silently dropping
unknown fields.

## Known limits

- The running unlocked app must hold the decrypted DB key in process
  memory. Streaming every SQLite page decrypt through a TPM would
  kill performance (thousands of 10 ms chip operations per query).
  No consumer SSH client does this; the limit is inherent to the
  workload.
- Linux T1 (libsecret) has no TPM integration. If the user wants
  hardware binding on Linux, T2 is the path; T1 on Linux is
  software-backed.
- Biometric modifier on Linux requires `fprintd` as an opt-in OS
  dep. Without it the biometric toggle is rendered disabled with a
  tooltip pointing to the README install snippet.
- Reset-all-data cannot reach backup archives that have already left
  the device (iCloud backup, Time Machine, Android Auto Backup,
  Windows File History). The app opts out of the Apple paths at
  startup (`NSURLIsExcludedFromBackupKey` on iOS, the
  `com_apple_backup_excludeItem` xattr on macOS) and manifest-level
  `data_extraction_rules.xml` excludes every managed file on
  Android, so fresh installs never start leaking into those
  backups. Users exporting the app's app-support directory to
  external storage should still understand that that snapshot
  carries the sealed blob + salt + KDF params + metadata and
  should be treated accordingly; the sealed blob without the
  original hardware is not directly decryptable, but the metadata
  leakage is real.

## Release signing

Each release is signed by a single Ed25519 signature over a
`.sha256sums` manifest that lists every artefact and its sha256
digest. Two files are published alongside the binaries:

- `letsflutssh-<version>.sha256sums` — plaintext manifest,
  `sha256sum` format (compatible with `sha256sum --check`)
- `letsflutssh-<version>.sha256sums.sig` — detached Ed25519 signature
  over the manifest

The auto-updater is the only consumer of this pair. It verifies the
manifest signature against the public key baked into the installed
app (`lib/core/update/release_signing.dart`), then compares the
downloaded artefact's sha256 with the entry in the verified manifest.
A MITM'd GitHub response cannot forge a manifest signature without
the private key.

**Trust anchor.** The baked public key in the installed binary — not
anything downloaded at update time. The PEM public key is
intentionally **not** published alongside the release: a `.pub` file
served from a hostile mirror would be byte-consistent with a forged
manifest + signature, implying an authenticity check it cannot
actually provide.

**In-app security warning.** When signature verification fails the
Settings → Updates panel shows a security-styled tile (not the
generic "Update check failed" error) with an explicit "Open Releases
page" action, steering the user towards a manual reinstall rather
than a retry of the same failing download.

**Fresh-install trust.** Installing for the first time is outside
the scope of this signing scheme — the trust chain starts at the
first install and protects every subsequent update. First-time users
implicitly trust the GitHub HTTPS pipeline and whatever package
manager brought them to the release page; this repo does not try to
layer on top of that. The `letsflutssh-<version>.intoto.jsonl`
attestation file continues to be published alongside the release
because `actions/attest-build-provenance` produces it for free and
it carries a SLSA build-provenance record that survives in Sigstore
Rekor's public transparency log — but we do not prescribe a
user-facing command that depends on it.

**Single-pin design.** The app embeds one public key. Keeping a
second pinned key as a rotation fallback is a deliberate non-goal —
the extra key doubles the maintenance surface for a scenario that,
for a solo-dev repo, is survivable with a manual reinstall.

**Reproducible builds (partial).** The Linux artefacts
(`.tar.gz`, `.deb`, `.AppImage`) are built with `SOURCE_DATE_EPOCH`
pinned to the HEAD commit's timestamp + deterministic `tar`
ordering + `gzip -n`. Two runs of the release workflow on the
same commit produce byte-identical Linux artefacts — any third
party can rebuild from source and compare `sha256sum` against the
official release as a supply-chain check separate from the
Ed25519 signature (which only proves "CI-signed this", not "this
matches source"). The Windows `.zip` / `.exe` installer and the
macOS `.tar.gz` / `.dmg` are **not** byte-reproducible because
Authenticode / codesign timestamp each run, the self-signed cert
is generated fresh per run, and `hdiutil` bakes run-scoped
catalog metadata into the .dmg. Users who need reproducibility
today should cross-check against the Linux build.

**If the private key leaks.** The auto-update channel is effectively
dead for existing installs. Incident response:

1. Rotate the `RELEASE_SIGNING_KEY` GitHub secret to an entirely
   fresh Ed25519 key pair (generated offline).
2. Replace the `_pinnedPublicKeys` entry in
   `lib/core/update/release_signing.dart` with the fresh public key.
3. Cut a new release. Existing installs will refuse to auto-update
   (they still trust only the leaked key) — this is the correct
   defensive behaviour.
4. Announce on the GitHub Releases page and README: users must
   manually reinstall to pick up the new pinned key.

**If the private key is lost.** Same playbook — generate a new key,
ship a new release, users reinstall manually. No auto-update across
the boundary.

## Automated security checks

- **OSV-Scanner** — scans `pubspec.lock` against the
  [OSV.dev](https://osv.dev) vulnerability database on every
  dependency change and weekly. Results appear in the GitHub
  Security tab. Build releases are blocked if known CVEs are found.
- **OpenSSF Scorecard** — evaluates repository security practices
  (branch protection, dependency pinning, CI hardening). Results
  published at
  [scorecard.dev](https://scorecard.dev/viewer/?uri=github.com/Llloooggg/LetsFLUTssh).
- **CodeQL** — static analysis of GitHub Actions workflows (weekly).
  Dart is not supported by CodeQL; application code is covered by
  SonarCloud instead.
- **SonarCloud** — static analysis, code quality, coverage, and
  security hotspot detection for Dart / Flutter code on every CI
  run.
- **Dependency Review** — checks new dependencies for known
  vulnerabilities on pull requests.
- **Dependabot** — automated security updates (CVE-triggered) and
  version updates (weekly) for pub packages and GitHub Actions.
- **Pinned Dependencies** — all GitHub Actions are pinned to commit
  SHA hashes to prevent supply chain attacks via tag manipulation.
- **Branch Protection** — main branch requires CI and OSV-Scanner
  checks to pass, force pushes and branch deletion are blocked.
- **Least Privilege** — all workflows default to read-only token
  permissions (`permissions: read-all`), jobs explicitly request only
  what they need.
- **OpenSSF Best Practices** — project meets
  [OpenSSF Best Practices](https://www.bestpractices.dev/projects/12283)
  passing criteria.

## Reporting a vulnerability

If you discover a security vulnerability in LetsFLUTssh, **please do
not open a public issue**.

Instead, report it privately via
**[GitHub Security Advisories](https://github.com/llloooggg/LetsFLUTssh/security/advisories/new)**.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Potential impact

### What to expect

This is a personal open-source project, so there are no guaranteed
response times. That said, I take security seriously and will do my
best to:

- Acknowledge the report as soon as possible
- Provide a fix in the next patch release
- Credit the reporter (unless they prefer to stay anonymous)

## Supported versions

Security updates are applied to the **latest release** only. Older
versions are not supported.

Check [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases)
for the current version.

## Out of scope

- Vulnerabilities in upstream dependencies (`russh` + the
  RustCrypto stack vendored under `rust/`, `pointycastle`, `xterm`) —
  please report those to their maintainers directly.
- Denial of service via local access.
- Issues requiring physical device access (cold-RAM attacks, chip
  probes, boot-media swaps).
