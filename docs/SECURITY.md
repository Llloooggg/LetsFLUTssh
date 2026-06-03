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
- **Upstream dependency vulnerabilities** — `russh` + `russh-sftp` +
  the broader RustCrypto stack vendored at `rust/`, the bundled
  SQLCipher 4.x + OpenSSL `rusqlite` vendors, `alacritty_terminal`,
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
Linux). Android keeps its T1 secret in an AES-256-GCM frame whose
wrap key lives in **AndroidKeyStore** (TEE / StrongBox-backed when the
device exposes one), with the wrapped ciphertext bytes persisted as a
0600 file under `<appFilesDir>/lfs_secure_storage/<alias>.bin` —
deliberately not `EncryptedSharedPreferences` (avoids dragging in
`androidx-security-crypto` which duplicates the GCM frame work
`lfs_core` already does). On Apple, Android, and Windows the wrap
key is hardware-backed (Secure Enclave, StrongBox / TEE, DPAPI with
TPM binding) — the effective guarantee is hardware-bound-via-OS. On
Linux `libsecret` has no TPM integration; this is flagged honestly
in the per-platform backing matrix below.

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
- **Password is mandatory.** T2 always seals the database key under a
  user-typed password; biometric is the optional shortcut that
  releases that password from a biometric-gated OS slot, never a
  replacement for it.

### Escape — derived-only (Paranoid)

A separate branch, not a "higher tier". The database key is **not
persisted** anywhere. The user chooses a master password; on every
unlock the key is derived per-session through Argon2id (64 MiB / 3
iterations / 1 lane — one tier above the OWASP 2024 floor, canonical
in `lfs_core::security::master_password::KdfParams::defaults` and
mirrored Dart-side as `KdfParams.productionDefaults`) and lives only in a page-locked
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

T2 is mandatory-password by tier across every platform — biometric
is the optional shortcut layer that releases the typed password from
an OS-managed slot, never a replacement. The "Biometric overlay"
column names the OS API used to gate that slot; "—" means the
overlay is not wired on this platform yet (the password path still
works, the biometric shortcut is unavailable).

| Platform | T1 backing | T2 backing | Biometric overlay | Rust ownership |
|---|---|---|---|---|
| iOS | Keychain → Secure Enclave | Secure Enclave (direct) | `kSecAccessControlBiometryCurrentSet` ACL on the overlay key | `lfs_os_security::secure_key_storage` + `hardware_tier_vault::apple` (`security-framework` + `objc2`) |
| macOS | Keychain → Secure Enclave (T2 chip / Apple Silicon) or software-only on older Intel | Secure Enclave (direct); T2 unavailable on older Intel Macs | `kSecAccessControlBiometryCurrentSet` ACL on the overlay key | same as iOS — shared Apple-cfg Rust path |
| Android | AES-256-GCM wrap key in AndroidKeyStore (TEE / StrongBox), wrapped value bytes in 0600 file under `getFilesDir()` | StrongBox-backed AES-256-GCM key with password-HMAC frame envelope, falls back to TEE on `StrongBoxUnavailableException` | `setUserAuthenticationRequired(true)` + `setInvalidatedByBiometricEnrollment(true)` alias `lfs.hardware_tier_vault.l3.bio` | `lfs_os_security::android::keystore` + `android::hardware_vault` (direct JNI to `java.security.KeyStore` provider `"AndroidKeyStore"`, no Kotlin shim) |
| Windows | Credential Manager → DPAPI (TPM-bound when available) | CNG / NCrypt direct → TPM 2.0 | Hello-gated NCrypt persistent key `letsflutssh_hardware_vault_bio_v1` with `NCRYPT_UI_PROTECT_KEY_FLAG \| NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`, separate from the primary so enrolment changes invalidate only the overlay | `lfs_os_security::secure_key_storage::windows` (`extern "system"` to `CredReadW` / `CredWriteW`); hardware vault → `lfs_os_security::windows::hardware_vault` (direct `windows` crate FFI to NCrypt) |
| Linux | libsecret → **software-only** (no TPM integration in `libsecret`) | TPM 2.0 direct: subprocess `tpm2-tools` (default) **or** native `tss-esapi` via `LFS_TPM_BACKEND=native` env opt-in. v3 envelope format wraps the sealed `(public, private)` pair as a TCG ASN.1 DER `id-loadablekey` body per `draft-bottomley-tpm2-keys-asn1` — wire-compatible with `openssl-tpm2-engine` and `ssh-tpm-agent` | TPM2-sealed `hardware_vault_password_overlay_linux.bin` keyed by the `fprintd` enrolment hash (SHA-256 of sorted enrolled-finger names); re-enrolment flips the hash so the overlay invalidates while the primary password vault keeps working. Requires `fprintd` (capability-ladder rung 5 — optional OS dep with graceful degradation; the install snippet lives in the main README) | `lfs_os_security::secure_key_storage::linux` (`secret-service` crate); `lfs_os_security::linux::tpm` + `tpm_native` + `tpm_tcg_pem` (subprocess + native backends share a TCG ASN.1 PEM envelope); `lfs_core::security::hardware_tier_vault::linux` (overlay orchestrator over fprintd + TPM2 seal) |

**Linux notes.** T1 on Linux is the weakest default across the
matrix because `libsecret` does not integrate with TPM. Users who
want hardware binding on Linux should pick T2 (requires a TPM 2.0 +
either `tpm2-tools` or `libtss2-dev` for the native backend; install
snippet in the main README). The biometric modifier on Linux flows
through `fprintd` and requires at least one enrolled finger. The
`tss-esapi` native backend ([`lfs_os_security::linux::tpm_native`](
../rust/crates/lfs_os_security/src/linux/tpm_native.rs)) talks
directly to `/dev/tpm0` through the TSS2 ABI — no per-operation
`fork()` + temp-file plumbing — and produces byte-identical sealed
envelopes to the subprocess path so the two paths interoperate
seamlessly.

**Linux T2 biometric overlay.** The Hardware tier's biometric
shortcut on Linux is a second TPM2-sealed envelope
(`hardware_vault_password_overlay_linux.bin`) keyed by the fprintd
enrolment hash, orchestrated by
[`lfs_core::security::hardware_tier_vault::linux`](
../rust/crates/lfs_core/src/security/hardware_tier_vault.rs). It is
intentionally separate from the primary `hardware_vault.bin` so a
new fingerprint enrolled / an old one dropped flips the hash, the
overlay's TPM unseal fails, and the user only loses the shortcut —
the primary password path keeps unsealing under the typed password.
The overlay requires `fprintd` (capability-ladder rung 5 — optional
OS dep with graceful degradation): when the daemon is unreachable
the Settings toggle disables with a localised reason and the
README install snippet covers the per-distro `apt` / `dnf` /
`pacman` / `zypper` commands.

**Android notes.** The AndroidKeyStore wrap key is generated via
direct JNI to `java.security.KeyStore` (no Kotlin business-logic
shim — the Kotlin side carries only the JavaVM bootstrap object
`LfsJniBootstrap` and the `BiometricPrompt` callback adapter
`LfsBiometricCallback`, both pure plumbing). Biometric variant uses
`setUserAuthenticationValidityDurationSeconds(60)` for cross-API
time-bound auth. StrongBox-backed wrap keys (`setIsStrongBoxBacked(true)`,
API 28+) are requested for the T2 hardware tier; failure
silently falls back to TEE.

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
  the OS (`Win+L`, `Ctrl+Cmd+Q`, GNOME lock) routes through the
  Rust path `lfs_os_security::session_lock_listener` —
  Windows hidden message-only window subscribing to
  `WTSRegisterSessionNotification`, macOS dedicated `NSRunLoop`
  thread observing `NSDistributedNotificationCenter`
  `com.apple.screenIsLocked`, Linux zbus subscription to
  `org.freedesktop.login1.Session.Lock`. All three forward via a
  shared `tokio::sync::broadcast` to a single FRB Stream, so the
  Dart side has one subscription regardless of OS. The in-app
  lock fires even when the user hasn't been idle long enough to
  trip the timer. **Every lock unconditionally wipes the
  DB key and closes the rusqlite / SQLCipher handle**,
  zeroing both the Dart-side `SecretBuffer` and the C-layer
  page-cipher cache (the live cipher is AES-256-CBC + HMAC-SHA512).
  Live sessions stay reconnectable through a per-session credential
  cache (`SessionCredentialCache`) — each session's password / key
  bytes / passphrase are kept in `mlock`-pinned native memory
  outside the encrypted store, so closing the store on lock does
  not cost the user their connections. The cache is the only
  reason the wipe can be unconditional: a "skip wipe while a
  session is connected" exception would leave the DB key warm
  whenever any session was alive, flattening T1+password and
  T2+password against RAM-forensics-on-locked-machine in the
  matrix below — defence the cache lets the policy keep. The cache is evicted on
  explicit disconnect, on any wipe / reset path, and on app
  shutdown.
- **Page-locked in-memory secrets** — DB key, Argon2id-derived keys,
  and biometric-stored passwords live in FFI-allocated buffers
  locked into physical RAM with `mlock` (POSIX) or `VirtualLock`
  (Windows), zeroed and unlocked on dispose. They cannot page to
  swap or hibernate. The Rust side adds `Zeroizing<Vec<u8>>` for
  every transient cleartext copy held in `lfs_core::security::SecretStore`
  (the only cached-plaintext owner per the plaintext-discipline boundary contract);
  drop = byte-clear regardless of whether the buffer was page-locked,
  belt-and-braces against accidental compiler-side copy elision.
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
  Complementary runtime probe `lfs_os_security::is_being_debugged()`
  (FRB-exposed as `osSecurityIsBeingDebugged`) reads the *current*
  tracer state (Linux `/proc/self/status` → TracerPid, macOS
  `sysctl` → `P_TRACED`, Windows `IsDebuggerPresent`; iOS
  short-circuits to `false`). Startup hardening BLOCKS new attaches;
  the runtime probe READS the current attach state.
- **Anti-debug biometric gate** — every biometric unlock attempt
  (startup `T1+pw` / `T2+pw` ladder, mid-session `LockScreen` retry,
  inline retry inside the typed-secret unlock dialog) routes through
  one funnel: `_tryBiometricCommit` in
  [`SecurityInitController`](../lib/app/security_init_controller.dart).
  The funnel calls `ProcessHardening.isBeingDebugged()` first; on a
  positive probe it logs through `logCritical` and returns false
  without touching the OS-stored password. The dialog falls through
  to the typed-secret form (master password / PIN), so a debugger
  watching the process cannot scoop the auto-released secret out of
  RAM after a biometric prompt completes — the user has to type the
  secret, narrowing the attack window to keystrokes the user is
  actively producing. Probe is fail-safe-false on FRB error
  (unreadable `/proc`, sandboxed iOS) so a hardened host cannot
  brick legitimate unlock. Developer caveat: a Flutter dev build
  attached via Xcode / `gdb -p` will see biometric refused on
  every unlock — the user types the password in that session, no
  security regression for the legit path.
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
  their own data. Failure posture is platform-aware: a Rust-path
  failure on Windows / macOS / iOS / Android **refuses** the copy
  and the caller surfaces a toast, because the stock fallback
  would deposit the secret into a cloud-syncing pasteboard
  without the opt-out flags. Linux has no cloud clipboard so the
  fallback there is the same posture as the Rust path.
- **Known hosts / TOFU verification** — DB-backed; the host-key
  callback refuses silent changes and surfaces an unambiguous dialog
  with both fingerprints.
- **OpenSSH user certificates** — stored keys may be paired with a
  CA-signed certificate (`ssh-keygen -s ca_key id_*.pub`). The app
  matches the OpenSSH semantics: it holds the cert blob alongside
  the private key, presents `(key, cert)` at userauth time, and
  lets the server enforce the validity window, principals list, and
  critical-options (`force-command`, `source-address`, etc.). The
  client does not validate the CA signature against a trusted-CA
  set itself — that's the server's job (`TrustedUserCAKeys` in
  `sshd_config`); a tampered cert simply fails the connect with an
  auth error. The cert blob is public material (the signed half),
  but the storage and connect path route it through the same
  SecretStore staging path as the private PEM so the connect
  cascade audit lists a single uniform namespace
  (`key.priv.<id>` + `key.cert.<id>`).
- **WebDAV credentials** — WebDAV passwords and bearer tokens live
  in the same SecretStore that holds SSH credentials, under the
  `session.webdav.<session_id>` id. The persisted
  `webdav_session_details` row carries only the base URL, username,
  auth method tag (`basic` / `digest` / `bearer`), and an optional
  self-signed cert fingerprint — never the secret itself. The
  auth-method tag is per-session, so an enterprise install can mix
  Basic-over-TLS and Bearer-token sessions without a global
  preference. Self-signed fingerprint pinning is opt-in; an empty
  fingerprint uses the system trust store (bundled `webpki-roots`)
  exactly like the auto-update channel.
- **S3 credentials** — S3 secret access keys live in the same
  SecretStore under the `session.s3.<session_id>` id. The persisted
  `s3_session_details` row carries only the access key id, region,
  endpoint, addressing style, default bucket, and default prefix —
  never the secret itself. Presigned URLs for time-limited
  downloads are signed with AWS Signature V4 in query-parameter
  mode; the signature lands as `X-Amz-Signature` in the URL, and
  the URL ceases to authorise once the chosen expiry passes (the
  UI offers presets up to AWS's 7-day maximum). Anyone with the
  URL inside the validity window can download the object, so the
  user is responsible for sharing it through a channel that is at
  least as confidential as the bucket itself.
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

| Threat | T0 | T1 | T1 + pw | T2 + pw | Paranoid |
|---|---|---|---|---|---|
| Cold disk theft | ✗ | ✓ | ✓ | ✓ | ✓ |
| Keyring / keychain file exfiltration | ✗ | ✗ | ✓ | ✓ | ✓ |
| Offline brute force on password | ✗ | ✗ | ✓ | ✓ | ✓ |
| Bystander at unlocked machine | ✗ | ✗ | ✓ | ✓ | ✓ |
| RAM forensics on locked machine | ✗ | ✗ | ✗ | ✓ | ✓ |
| OS kernel / keychain breach | ✗ | ✗ | ✗ | ✓ | ✓ |

The standalone "T2" column is gone — Hardware tier is always
password-gated by contract; biometric is the optional shortcut
that releases that password from a biometric-gated OS slot, not
a separate tier variant.

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
  parameters (64 MiB / 3 iterations / 1 lane — one tier above the
  OWASP 2024 floor, canonical in
  `lfs_core::security::master_password::KdfParams::defaults` and
  mirrored Dart-side as `KdfParams.productionDefaults`) is what turns brute-force
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
known_hosts, snippets, tags, user preferences, paired OpenSSH
certificates, WebDAV / S3 per-session config, SFTP bookmarks, and
port-forward rules. They **never carry** `security_tier` or
`security_modifiers`. Security configuration is strictly
per-install: importing on a device B an archive made on device A
does not try to adopt device A's hardware-vault setup; device B's
existing security setup is preserved. Users re-run the wizard only
when setting up a new device from scratch.

### Per-row secret discipline

Several per-session secrets stay on the source device by design.
The archive ships only an opaque SecretStore-id pointer for each;
the receiving device finds the pointer missing in its own
SecretStore and surfaces a "re-enter password" / "re-enter access
key" prompt on first connect:

| Travels (sensitive part) | Travels (opaque pointer) | Stays on source device |
|---|---|---|
| Session passwords (inside AES-GCM envelope) | `webdav_session_details.credential_secret_id` | WebDAV password / bearer token bytes |
| Software SSH key PEM (inside AES-GCM envelope) | `s3_session_details.secret_access_key_secret_id` | S3 secret access key bytes |
| Session passphrases (inside AES-GCM envelope) | — | — |

The opaque-pointer pattern keeps the wire format honest: a peer
who decrypts the archive sees the user knows the secret exists,
not what the secret is.

### PKCS#11 token metadata sensitivity

`.lfs` archives include the PKCS#11 token serial number, the
`CKA_ID` bytes of the private-key object, and the
RFC 7512 `pkcs11:` URI for every `backend = 'pkcs11'` row. The
sensitivity rating is **low**:

- The token serial + object id let a peer device probe its own
  inserted tokens and ask "is the same hardware in my reader?".
  They do not reveal anything an attacker who already has the
  physical token would not also have via vendor tooling.
- The matching private key material lives on the token's secure
  element; the bytes never leave the chip. The serial / object id
  identify which key to call into, not how to compute its
  signatures.
- The `pkcs11_module_path` field — the per-host install location
  of the vendor library — is **never on the wire**. The receiving
  device re-discovers it locally via the well-known-paths scan
  keyed on the token serial. A peer who saw the path would learn
  nothing useful (it points at a vendor `.so` / `.dll` / `.dylib`
  that the well-known-paths scan finds anyway).

Device-bound key backends — Apple Secure Enclave, Windows Hello,
TPM 2.0, Android Hardware Keystore / StrongBox — ship as
public-half-only stubs. The wrapped private blobs (`tpm_blob`,
`enclave_tag`, `hello_credential_name`, `keystore_alias`) never
travel; only the row's label + public key + backend discriminator
do. The user picks "Re-generate here" on the stub to mint a fresh
hardware-backed key on the receiving device.

The encryption format is AES-256-GCM under an Argon2id-derived key,
with the `LFSE 0x03` header carrying the KDF parameters. The pre-IV
header (magic + version + KDF params + salt) is bound into the
AES-GCM AAD so an attacker who flips header bytes to coerce a
weaker KDF derivation invalidates the AEAD tag rather than feeding
cooked params into the verifier. Pre-AAD legacy `0x02` envelopes
still decode through a transparent fallback so existing exports
keep importing. The import path enforces parameter caps
(`maxImportArgon2idMemoryKiB`, `maxImportArgon2idIterations`,
`maxImportArgon2idParallelism`) so a hostile header cannot pin the
isolate into swap. Archives declaring a schema version the current
build does not understand are rejected with
`UnsupportedLfsVersionException` rather than silently dropping
unknown fields.

### WebDAV sync — passphrase posture

Settings → Sync ships the same encrypted `.lfs` archive to a
user-configured WebDAV endpoint. The crypto envelope is the
same as the manual export path (Argon2id + AES-256-GCM under
the LFSE header), but the at-rest key is a dedicated **sync
passphrase** — never the master password. The UI enforces this
on save: the typed passphrase is hashed through
`MasterPasswordManager.verifyAndDerive`, and if it matches the
on-disk master-password verifier, the save is rejected with the
**Sync passphrase cannot match the master password** banner.

The rationale is reuse-of-key blast radius: an attacker who
exfiltrates the WebDAV remote and breaks the sync passphrase
should not also win the local DB cipher key. Using two distinct
secrets means a passphrase leak compromises only the synced
archive, never the on-disk SQLCipher pages.

Both the WebDAV credentials and the sync passphrase live in
`lfs_core::secrets::SecretStore` under the canonical ids
`sync.webdav.password` and `sync.passphrase`. `config.json`
carries only the SecretStore id pointers; plaintext never lands
on disk in the preferences file. Wipe-all clears both slots
alongside every other SecretStore entry.

## FIDO2 hardware-bound SSH keys (`sk-*`)

OpenSSH `sk-ssh-ed25519@openssh.com` and `sk-ecdsa-sha2-nistp256@openssh.com` keys hold their private half on a hardware authenticator (YubiKey, SoloKey, Titan, Feitian, Nitrokey, Trezor). The signing scalar never leaves the device, the app never sees it, and at-rest theft of the laptop yields nothing the attacker can replay against an SSH server.

What we persist alongside the SSH key row: the opaque CTAP2 credential id, the SSH `application` field (typically `ssh:`), the user-verification flag captured at import, and the OpenSSH public-key body. None of these grants signing capability — the device matches the credential id against its on-board secret on every assertion. An attacker reading the on-disk SQLCipher DB obtains the credential id but still needs the physical device (and the PIN, when user-verification is set) to mint a signature.

PIN entry is per-connect, never cached: the `hardware_key_prompt_dialog` collects the PIN, hands it straight to `lfs_core::fido2::get_assertion`, and the PIN string is dropped at the end of the FRB call. The Rust core forwards it once to the CTAP2 layer and never retains it.

The connect path's `FidoSigner` (russh `auth::Signer` impl) SHA-256-hashes the SSH userauth signature input, sends it to the device as the WebAuthn `clientDataHash`, and embeds the resulting CTAP signature in the OpenSSH `sk-*` wire-format trailer (`flags || u32 counter` for sk-ed25519; `mpint r || mpint s || flags || u32 counter` for sk-ecdsa-p256). The counter increments per assertion — replay across the wire is detectable by any SSH server that tracks it.

### OS broker vs direct USB HID

Two transports reach the device. On Windows / macOS / iOS / Android the default is the **OS-managed security-key broker** (Windows `webauthn.dll`, Apple `ASAuthorizationSecurityKeyPublicKeyCredentialProvider`, Android `androidx.credentials.CredentialManager`). The broker dialog covers USB / NFC / BLE / the platform authenticator without an admin permission grant, without the Apple Developer Program entitlement on macOS for self-signed builds (the dispatcher transparently falls through to direct HID when AS reports the entitlement is missing), and surfaces a user-visible **system dialog** the user already recognises — making a silent / programmatic signature attempt fail to materialise as a familiar prompt and giving the user a tamper-detection signal ("I didn't initiate this"). Linux uses the direct CTAP2 HID transport via `ctap-hid-fido2` exclusively (no broker primitive exists on Linux).

The "Prefer direct USB HID over system dialog" toggle in Settings forces the direct-HID path on Windows / macOS for advanced users; it is disabled on Linux (one path) and on iOS / Android (no HID fallback). The trade-off the toggle exposes is honest: direct HID carries the full CTAP2 surface (hmac-secret, large-blob, credBlob — none of which SSH consumes today per PROTOCOL.u2f's "No extensions are yet defined for SSH use") and avoids an extra OS-mediated process boundary, but it needs a per-app permission grant (`udev` rules on Linux, HID class access on Windows) and lacks the system-dialog tamper signal.

Broker subsetting is documented for forward compatibility: WebAuthn.dll exposes `hmac-secret` only on `MakeCredential` (not `GetAssertion`), ASAuthorization and Credential Manager never expose it. A future cert-via-FIDO feature that wants to store per-host secrets in the credential's hmac-secret extension would have to use the direct HID path or stay disabled on broker-only platforms.

## Apple Secure Enclave SSH keys

On macOS (T2 Intel + Apple Silicon) and iOS, SSH keys can be generated directly on Apple's Secure Enclave coprocessor — the same silicon that holds Touch ID / Face ID templates. The chip refuses to export the private bytes; every connect-time signature routes through `SecKeyCreateSignature`, and the OS surfaces a biometric / passcode prompt at the FFI boundary per the access-control flags chosen at key creation. At-rest theft of the laptop yields nothing the attacker can replay — the chip refuses to sign without a fresh biometric / passcode unlock, and the wrapped key material is bound to the device's UID such that another device cannot deserialise it.

What we persist alongside the SSH key row: the opaque `kSecAttrApplicationTag` bytes (`letsflutssh.ssh.<uuid>`) and the OpenSSH public-key body. None of these grants signing capability — the chip matches the tag against its on-board key on every `SecKeyCreateSignature` call. An attacker reading the on-disk SQLCipher DB obtains the tag but cannot redirect the chip to sign for them.

Auth policy at create time picks between `kSecAccessControlBiometryCurrentSet` (Touch ID / Face ID required; re-enrolment invalidates the key by clearing the chip's biometric template binding) and `kSecAccessControlUserPresence` (biometry OR device passcode; survives re-enrolment, costs the passcode-as-fallback weakness). Both shapes pin to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so the key never syncs to iCloud Keychain and never persists past a passcode unset.

`.lfs` archive export of SE-bound keys carries the row + the tag envelope only; the importing device's connect path checks the chip's register via `apple_se_ssh::list()` and surfaces "Missing on this device — re-generate" when the tag isn't present. Cross-device portability is impossible by chip design.

Code-signing requirement: unsigned / ad-hoc bundles surface `errSecMissingEntitlement` (`-34018`) on the first `SecKeyCreateRandomKey` call. The wizard probe step classifies this separately so the UI can route the user at the `codesign -s -` remediation in USER_GUIDE.md. Distributed releases are signed and work out of the box.

## Windows Hello SSH keys

On Windows 10 1607+ with Hello configured, SSH keys can be generated directly under the Microsoft Platform Crypto Provider — TPM 2.0 on hardware-capable hosts, the PCP software KSP fallback otherwise. The provider refuses to export the private bytes; every connect-time signature routes through `NCryptSignHash`, and Windows surfaces the Hello prompt (PIN / fingerprint / face) at the FFI boundary per the `NCRYPT_UI_POLICY_PROPERTY` set at key creation. At-rest theft of the laptop yields nothing the attacker can replay — the chip refuses to sign without a fresh Hello unlock, and the wrapped key material is bound to the user's CNG namespace such that another Windows install cannot deserialise it.

We deliberately avoid `KeyCredentialManager.RequestSignAsync` even though it has a friendlier surface. KCM produces RSA-PSS signatures; SSH `rsa-sha2-256` / `rsa-sha2-512` requires PKCS#1 v1.5; the two padding schemes are not re-encodable into each other. The only Windows path that emits SSH-compatible signatures is NCrypt + PCP with explicit `BCRYPT_PAD_PKCS1` (RSA) or no padding (ECDSA).

What we persist alongside the SSH key row: the CNG persistent-key name (`letsflutssh-ssh-<user-hash>-<uuid>`) and the OpenSSH public-key body. None of these grants signing capability — `NCryptOpenKey` matches the name against the user's CNG namespace on every sign call, and the Hello prompt gates the operation regardless. An attacker reading the on-disk SQLCipher DB obtains the name but cannot redirect CNG to sign for them without unlocking Hello.

UI policy at create time pins `NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`. The "force high protection" flag requires Hello to be configured at the OS level — finalize fails with `NTE_USER_CANCELLED` when it isn't (the OS surfaces the configure-Hello dialog and the user dismissed it). This is the deliberate opposite default from the T2 hardware-vault path, which omits UI policy because it is the *vault* the primary master-password unlock already gated against. The SSH path takes the prompt every time because the Hello ceremony *is* the SSH authentication factor.

TPM-tier classification is honest in the UI. Probe inspects `NCRYPT_IMPL_TYPE_PROPERTY` on a throw-away key and labels the wizard accordingly: "Windows Hello" for `NCRYPT_IMPL_HARDWARE_FLAG` set (TPM 2.0 backing), "Windows Hello (Software-gated)" for the software KSP fallback. The weaker path is *never* labelled as plain "Windows Hello" — per the capability ladder's rung-6 honest-label rule, the user always knows which tier the key landed at.

`.lfs` archive export of Hello-bound keys carries the row + the CNG name only; the importing device's connect path tries `NCryptOpenKey` and surfaces `Error::KeyNotFound` when the name isn't registered in the destination user's CNG namespace. Cross-device portability is impossible by provider design.

## TPM 2.0 SSH keys

Two paths, opposite UI-policy defaults from the Hello path above:

- **Linux** uses `tss-esapi` (libtss2-esys) directly. `TPM2_Create` produces a wrapped `(public, private)` blob pair that we wrap in the TCG draft `draft-bottomley-tpm2-keys-asn1` "TSS2 PRIVATE KEY" envelope for cross-tool compat — same `id-loadablekey` shape `ssh-tpm-agent` and `openssl-tpm2-engine` consume, emitted/decoded by the shared `lfs_os_security::linux::tpm_tcg_pem` helper so the T2 hardware-vault seal path and the T-4 SSH-signing path stay in lockstep. Every sign re-issues `TPM2_Load` + `TPM2_Sign` and tears the transient handle down — the private bytes never leave the chip. PIN-bound keys carry a `TPM2B_AUTH` value; the TPM's dictionary-attack lockout fires after 4 wrong PINs and locks the **entire chip** (BitLocker / disk-unlock included) for a cooldown window.
- **Windows** reuses the Microsoft Platform Crypto Provider via `lfs_os_security::windows::ncrypt_ssh::create_silent`, but **without** setting `NCRYPT_UI_POLICY_PROPERTY` — the resulting key signs unattended. This is the deliberate opposite of the Hello-gated SSH path; the wizard surfaces the silent-warning copy in red so the user understands the trade-off before opting in. CNG-name prefix `letsflutssh-tpm-` distinguishes silent TPM keys from Hello-gated `letsflutssh-ssh-` keys when `NCryptEnumKeys` walks the provider.

What we persist on `ssh_keys` (schema v12): `tpm_provider` discriminator (`'tss-esapi'` / `'cng-pcp'`), `tpm_blob` (Linux TSS2 PRIVATE KEY ASN.1 bytes — the private half is TPM-encrypted; without the chip's storage primary it's an opaque envelope), `tpm_handle` (Linux persistent NV handle), `tpm_pin_required` (Linux PIN flag), `cng_key_name` (Windows CNG name). None of these grants signing capability on a different device — `TPM2_Load` re-derives the parent under the chip's storage primary, which differs across TPMs; `NCryptOpenKey` is bound to the user's CNG namespace on the host that created the key.

**Threat model footguns** users need to understand:

- **TPM lockout is hardware-wide.** Wrong PIN 4 times on a PIN-bound TPM SSH key locks the **entire TPM** — including BitLocker / LUKS unlock and any other TPM-bound credential — for the cooldown window. Wizard copy surfaces this aggressively at every PIN entry surface.
- **Persistent slots are scarce.** Typical fTPM ships ~7 free persistent handles. The wizard defaults to blob mode for this reason.
- **TPM clear wipes everything.** `tpm2_clear` (or a BIOS reset) re-derives the storage primary; every blob signed under the old primary is unrecoverable. Treat the chip clear as equivalent to losing the SSH key.
- **Silent variant is desktop-access-equivalent.** Windows TPM (silent) SSH keys sign without any prompt. Anyone with access to the desktop while the user is logged in can sign. This is intentional — the variant is for headless service accounts where a prompt is impossible — but it's a strictly weaker contract than Hello-gated keys. The badge popover surfaces the warning so the user knows what they get.
- **Cross-tool blob import is restricted.** `.tpm` files carrying a PCR policy reject at import in v1 with a typed reason — the PCR-binding UX is a v2 commitment (see Appendix B in `ARCHITECTURE.md`).

`.lfs` archive export semantics: Linux blob-mode rows ship the wrapped bytes + row metadata; the importing chip can sign only if its storage primary derives byte-identically (the storage-primary template matches `tpm2 createprimary -C o` defaults, which is the documented contract). Persistent-handle Linux rows and every Windows TPM row are not portable — the chip / CNG namespace differs.

## In-process ssh-agent endpoint

`Settings → External SSH client integration` exposes the app's hardware-bound keys to other SSH-protocol-speaking applications on the same host (`git`, OpenSSH `ssh`, IDE plugins). The endpoint is off by default; the user opts in explicitly. When running it binds a Unix domain socket at `${XDG_RUNTIME_DIR:-/tmp}/letsflutssh-agent.<pid>/agent.sock` (Linux / macOS) with parent-directory mode `0o700`, or a Windows named pipe at `\\.\pipe\letsflutssh-agent.<pid>` whose default DACL grants only the current user SID + SYSTEM.

Security posture: the endpoint refuses every `ADD_IDENTITY` / `ADD_IDENTITY_CONSTRAINED` / `REMOVE_IDENTITY` / `REMOVE_ALL_IDENTITIES` / `ADD_SMARTCARD_KEY` / `REMOVE_SMARTCARD_KEY` request with `SSH_AGENT_FAILURE` — external clients cannot push key material in. Software keys (plain-text PEM rows) are never published through the agent's `request_identities`; only hardware-bound rows whose `agent_policy != 'deny'` appear. Every SIGN_REQUEST routes through a confirmation dialog when the key's `agent_policy` is `'ask'` (the default); `'always'` skips the dialog, `'deny'` refuses outright AND hides the key from listing. Touch / PIN prompts the hardware backend itself requires still fire on top.

Per-key dispatch policy is stored on `ssh_keys.agent_policy` (schema v8) and never crosses the wire to peer devices on a sync merge — incoming sync rows always land at `'ask'` so authorising a key on one host does not auto-authorise it on another.

Mobile builds compile out the entire module — Android and iOS app sandboxes deny the cross-process IPC the agent protocol depends on, and there is no `ssh` / `git` shell on those platforms to consume the socket.

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
app (`rust/crates/lfs_core/src/update/signing.rs::PRIMARY_PUBLIC_KEY`),
then compares the downloaded artefact's sha256 with the entry in the
verified manifest. A MITM'd GitHub response cannot forge a manifest
signature without the private key.

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
2. Replace the `PRIMARY_PUBLIC_KEY` constant in
   `rust/crates/lfs_core/src/update/signing.rs` with the fresh public key.
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
- **Semgrep** — SAST scan of the Dart code on every PR + weekly; a
  required check on `main` (`semgrep-scan`).
- **cargo-deny** — Rust advisory / license / banned-crate audit over
  `rust/Cargo.lock` (push-main + PR + weekly), complementing OSV.
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

### Accepted Scorecard findings

Three OpenSSF Scorecard warnings are accepted rather than "fixed",
because each available fix would cost more than the finding is worth
for a solo-maintained SSH client. They are recorded here for
transparency:

- **Branch-Protection — "require approvers" / "last push approval".**
  Every other control on `main` is already at maximum (PRs required,
  enforced on admins, status checks + up-to-date branch required,
  CODEOWNER review, stale-review dismissal, no force-push, no
  deletion). The two remaining warnings need a *second human*
  reviewer; a single maintainer cannot approve their own PR, so
  requiring approvers would make every change unmergeable. Inherent to
  a one-person project.
- **Vulnerabilities — RUSTSEC-2023-0071 (`rsa` Marvin timing attack).**
  `rsa` is a transitive dependency of the core SSH crates (`ssh-key`,
  `russh`) with no fixed release upstream. The advisory targets RSA
  PKCS#1 v1.5 *decryption*; SSH uses RSA only for *signatures* (key
  exchange is ECDH/DH), so the vulnerable code path is never reached
  in this app. Removing it would mean dropping RSA SSH-key support
  entirely. Already documented and ignored in `osv-scanner.toml`, so
  the OSV gate stays green; Scorecard reports it independently.
- **Pinned-Dependencies — `choco install strawberryperl` not pinned by
  hash.** The Windows MSVC release build needs a working Perl for the
  vendored-OpenSSL build script. Chocolatey has no hash-pin mechanism
  (pinning a version would not satisfy Scorecard's hash requirement
  and risks the build breaking if that version is delisted). All
  GitHub Actions and container images *are* SHA-pinned; this one shell
  install is the sole unpinnable build dependency.

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

- Vulnerabilities in upstream dependencies (`russh` + `russh-sftp` +
  the RustCrypto stack vendored under `rust/`, bundled SQLCipher /
  OpenSSL via `rusqlite`, `alacritty_terminal`) — please report those
  to their maintainers directly.
- Denial of service via local access.
- Issues requiring physical device access (cold-RAM attacks, chip
  probes, boot-media swaps).
