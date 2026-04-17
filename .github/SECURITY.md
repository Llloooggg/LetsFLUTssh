# Security Policy

## Supported Versions

Security updates are applied to the **latest release** only. Older versions are not supported.

Check [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases) for the current version.

## Reporting a Vulnerability

If you discover a security vulnerability in LetsFLUTssh, **please do not open a public issue**.

Instead, report it privately via **[GitHub Security Advisories](https://github.com/llloooggg/LetsFLUTssh/security/advisories/new)**.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Potential impact

### What to expect

This is a personal open-source project, so there are no guaranteed response times. That said, I take security seriously and will do my best to:

- Acknowledge the report as soon as possible
- Provide a fix in the next patch release
- Credit the reporter (unless they prefer to stay anonymous)

### Scope

The following areas are in scope:

- Credential storage and encryption (drift + SQLite3MultipleCiphers, AES-256-GCM)
- Three storage modes — plaintext (DB unencrypted), OS keychain (key in system credential store), master password (PBKDF2-SHA256 600k iterations) — switchable on the fly via `PRAGMA rekey`
- Optional biometric unlock for master-password mode (`local_auth` + biometric-gated `flutter_secure_storage` slot)
- Optional auto-lock — idle timer zeroes the in-memory DB key and overlays a lock screen until re-authentication
- In-memory secret protection — DB key and PBKDF2-derived archive keys live in page-locked native buffers (`mlock` on POSIX, `VirtualLock` on Windows), zeroed + munlocked + freed on dispose
- Lazy-load credentials — session passwords / passphrases / private keys are not held in the in-memory store cache; fetched from the encrypted DB only at the moment of connect, edit, duplicate, or export
- Process hardening at startup — `prctl(PR_SET_DUMPABLE, 0)` on Linux/Android (no core dumps, no `gdb -p` from same UID without `CAP_SYS_PTRACE`), `ptrace(PT_DENY_ATTACH)` on macOS, `SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)` on Windows (suppresses WER crash dumps that would otherwise contain the cipher key)
- SSH key handling and authentication
- Known hosts / TOFU verification (DB-backed)
- Export/import archive encryption (`.lfs` format, PBKDF2-SHA256 600k iterations, AES-256-GCM, atomic tmp-then-rename writes, 50 MiB pre-decrypt size cap, OpenSSH-config import rejects `..`-traversal `IdentityFile` paths)
- Deep link URI parsing (`letsflutssh://` scheme) — host/port validation, path traversal rejection
- File permission handling (`chmod 600` on credentials, known_hosts, config files)
- Atomic file writes — write-to-temp-then-rename prevents data corruption on crash
- SFTP recursion depth limit (100 levels) — prevents stack overflow on malicious paths
- Error message sanitization (file paths stripped from user-facing errors)

### Automated Security Checks

- **OSV-Scanner** — scans `pubspec.lock` against the [OSV.dev](https://osv.dev) vulnerability database on every dependency change and weekly. Results appear in the GitHub Security tab. Build releases are blocked if known CVEs are found
- **OpenSSF Scorecard** — evaluates repository security practices (branch protection, dependency pinning, CI hardening). Results published at [scorecard.dev](https://scorecard.dev/viewer/?uri=github.com/Llloooggg/LetsFLUTssh)
- **CodeQL** — static analysis of GitHub Actions workflows (weekly). Dart is not supported by CodeQL; application code is covered by SonarCloud instead
- **SonarCloud** — static analysis, code quality, coverage, and security hotspot detection for Dart/Flutter code on every CI run
- **Dependency Review** — checks new dependencies for known vulnerabilities on pull requests
- **Dependabot** — automated security updates (CVE-triggered) and version updates (weekly) for pub packages and GitHub Actions
- **Pinned Dependencies** — all GitHub Actions are pinned to commit SHA hashes to prevent supply chain attacks via tag manipulation
- **Branch Protection** — main branch requires CI and OSV-Scanner checks to pass, force pushes and branch deletion are blocked
- **Least Privilege** — all workflows default to read-only token permissions (`permissions: read-all`), jobs explicitly request only what they need
- **OpenSSF Best Practices** — project meets [OpenSSF Best Practices](https://www.bestpractices.dev/projects/12283) passing criteria

For detailed technical documentation on the security model (credential encryption, TOFU, .lfs format, error sanitization), see [ARCHITECTURE.md §13 Security Model](ARCHITECTURE.md#13-security-model).

### Release signing

Each release is signed by a single Ed25519 signature over a
`.sha256sums` manifest that lists every artefact and its sha256
digest. Two files are published alongside the binaries:

- `letsflutssh-<version>.sha256sums` — plaintext manifest, `sha256sum`
  format (compatible with `sha256sum --check`)
- `letsflutssh-<version>.sha256sums.sig` — detached Ed25519 signature
  over the manifest

The auto-updater is the only consumer of this pair. It verifies the
manifest signature against the public key baked into the installed
app (`lib/core/update/release_signing.dart`), then compares the
downloaded artefact's sha256 with the entry in the verified manifest.
A MITM'd GitHub response cannot forge a manifest signature without
the private key.

**Trust anchor.** The baked public key in the installed binary — not
anything downloaded at update time. We intentionally do **not**
publish the PEM public key alongside the release: a `.pub` file
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

**If the private key leaks.** The auto-update channel is effectively
dead for existing installs. Incident response:

1. Rotate the `RELEASE_SIGNING_KEY` GitHub secret to an entirely fresh
   Ed25519 key pair (generated offline).
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

### Out of scope

- Vulnerabilities in upstream dependencies (`dartssh2`, `pointycastle`, `xterm`) — please report those to their maintainers directly
- Denial of service via local access
- Issues requiring physical device access
