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

- Credential storage and encryption (`CredentialStore`, AES-256-GCM) — key generation race guard, `CredentialStoreException` for decryption failures
- SSH key handling and authentication
- Known hosts / TOFU verification — `chmod 600` on `known_hosts` file
- Export/import archive encryption (`.lfs` format, PBKDF2-SHA256 600k iterations)
- Deep link URI parsing (`letsflutssh://` scheme) — host/port validation, path traversal rejection
- File permission handling (`chmod 600` on credentials, known_hosts, config files)
- Atomic file writes — write-to-temp-then-rename prevents data corruption on crash
- SFTP recursion depth limit (100 levels) — prevents stack overflow on malicious paths
- Error message sanitization (file paths stripped from user-facing errors)

### Automated Security Checks

- **OSV-Scanner** — scans `pubspec.lock` against the [OSV.dev](https://osv.dev) vulnerability database on every dependency change and weekly. Results appear in the GitHub Security tab. Build releases are blocked if known CVEs are found
- **OpenSSF Scorecard** — evaluates repository security practices (branch protection, dependency pinning, CI hardening). Results published at [scorecard.dev](https://scorecard.dev/viewer/?uri=github.com/Llloooggg/LetsFLUTssh)
- **CodeQL** — static analysis of GitHub Actions workflows (weekly)
- **SonarCloud** — code quality, coverage, and security hotspot analysis on every CI run
- **Dependency Review** — checks new dependencies for known vulnerabilities on pull requests
- **Dependabot** — automated security updates (CVE-triggered) and version updates (weekly) for pub packages and GitHub Actions
- **Pinned Dependencies** — all GitHub Actions are pinned to commit SHA hashes to prevent supply chain attacks via tag manipulation

### Out of scope

- Vulnerabilities in upstream dependencies (`dartssh2`, `pointycastle`, `xterm`) — please report those to their maintainers directly
- Denial of service via local access
- Issues requiring physical device access
