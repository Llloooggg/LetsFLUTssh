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

### Release signing and key rotation

Every release binary ships with a detached Ed25519 signature
(`<asset>.sig`) produced in CI from the `RELEASE_SIGNING_KEY` secret.
The updater verifies the signature against public keys compiled into
the app (`lib/core/update/release_signing.dart`) before installing an
update — an attacker who rewrites the GitHub response cannot forge a
signature without one of the private keys.

**Multi-pin design:** the app embeds **two** public keys (current +
backup). Old installs continue to verify even after a key rotation, as
long as the new signing key is one of the two they already know.

**Rotation playbook:**

1. The maintainer holds two Ed25519 private keys offline:
   - `release-key-current.pem` — used by CI via the `RELEASE_SIGNING_KEY` secret
   - `release-key-backup.pem` — stored offline (USB, password manager)

2. **If current leaks:**
   1. Swap the `RELEASE_SIGNING_KEY` GitHub secret to the backup private
      key's PEM contents.
   2. Generate a fresh backup pair offline:
      `openssl genpkey -algorithm Ed25519 -out release-key-backup.pem`
      and extract its 32-byte public key:
      `openssl pkey -in release-key-backup.pem -pubout -outform DER | tail -c 32 | od -An -tx1`
   3. Edit `lib/core/update/release_signing.dart` — replace the
      `_pinnedPublicKeys` entries with `[backup, fresh-backup]`. The
      previously-current (now-leaked) key is dropped.
   4. Ship a new release. Old installs still verify via the (now-active)
      backup pin; new installs learn the fresh backup.

3. **Periodic rotation (every 12 months, even without leak):**
   Same steps, just scheduled rather than incident-driven. Reduces the
   blast radius of an undetected leak.

**What if you lose both private keys?** Publish a new release branch
with a brand-new pubkey pair, but users on the abandoned key pair can
never receive verified updates from the old app. Recover manually by
asking users to download the new version from the website. Prevent
with redundant offline backups of both PEM files.

### Out of scope

- Vulnerabilities in upstream dependencies (`dartssh2`, `pointycastle`, `xterm`) — please report those to their maintainers directly
- Denial of service via local access
- Issues requiring physical device access
