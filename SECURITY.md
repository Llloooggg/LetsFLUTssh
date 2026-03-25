# Security Policy

## Supported Versions

LetsFLUTssh is currently in active pre-release development. Security updates are applied to the latest version only.

| Version | Supported          |
| ------- | ------------------ |
| 0.9.x   | :white_check_mark: |
| < 0.9   | :x:                |

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

- Credential storage and encryption (`CredentialStore`, AES-256-GCM)
- SSH key handling and authentication
- Known hosts / TOFU verification
- Export/import archive encryption (`.lfs` format, PBKDF2)
- Deep link URI parsing (`letsflutssh://` scheme)
- File permission handling (`chmod 600`)

Out of scope:

- Vulnerabilities in upstream dependencies (`dartssh2`, `pointycastle`, `xterm`) — please report those to their maintainers directly
- Denial of service via local access
- Issues requiring physical device access
