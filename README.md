# LetsFLUTssh

[![Release](https://img.shields.io/github/v/release/Llloooggg/LetsFLUTssh?include_prereleases)](https://github.com/Llloooggg/LetsFLUTssh/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20Android%20%7C%20iOS-blue)](https://github.com/Llloooggg/LetsFLUTssh)
[![License](https://img.shields.io/badge/License-GPL_3.0-blue.svg)](LICENSE)<br>
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/12283/badge)](https://www.bestpractices.dev/projects/12283)<br>
[![CI](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/ci.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/ci.yml)
[![ClusterFuzzLite](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/cfl-fuzz.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/cfl-fuzz.yml)
[![Build](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/build-release.yml/badge.svg?event=push)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/build-release.yml)
<br>
[![OSV-Scanner](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/osv.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/osv.yml)
[![CodeQL](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/codeql.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/codeql.yml)
[![Semgrep](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/semgrep.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/semgrep.yml)<br>
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=coverage)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Llloooggg/LetsFLUTssh/badge)](https://scorecard.dev/viewer/?uri=github.com/Llloooggg/LetsFLUTssh)

> **Disclaimer:** This is a functional neuroslop pet project — built with AI assistance under the supervision and direction of a real developer, for personal use, self-education, and fun. Use at your own risk.

Lightweight cross-platform SSH/SFTP client with GUI, built with Flutter.

Open-source alternative to Xshell and Termius — runs on Windows, Linux, macOS, Android, and iOS.

![SSH Terminal — session tree, tabbed terminal with htop](docs/screenshots/LetsFLUTssh_terminal.png)
![SFTP File Browser — dual-pane local/remote with transfer panel](docs/screenshots/LetsFLUTssh_files.png)

## Features

- **SSH** — xterm/VT100 terminal (256-color, RGB, mouse), tiling with recursive splits, search, multi-tab, keep-alive & reconnect
- **SFTP** — dual-pane file browser, drag & drop, transfer queue with parallel workers
- **Sessions** — tree with nested folders, search, drag & drop, QR code sharing, host key verification
- **Snippets** — reusable command snippets, pin to sessions, one-click terminal injection (now also reachable from the mobile SSH keyboard bar)
- **Tags** — color-coded tags for sessions and folders, visual dots in tree view; assign right inside Edit Session
- **Security** — encrypted SQLite storage (AES-256-GCM via SQLite3MultipleCiphers), three storage modes (plaintext / OS keychain / master password) with on-the-fly switching, optional biometric unlock and idle auto-lock in master-password mode, page-locked in-memory secrets (mlock/VirtualLock), startup process hardening (`prctl PR_SET_DUMPABLE`, `ptrace PT_DENY_ATTACH`), encrypted `.lfs` export/import, TOFU host key verification
- **Import/export** — encrypted `.lfs` archives, QR sharing for small exports, paste-deep-link import (no camera), in-app QR scanner (AndroidX CameraX + ZXing on Android, AVFoundation on iOS — no Google Play Services / MLKit)
- **Mobile** — virtual keyboard (Esc/Tab/Ctrl/Alt/F1-F12), pinch-to-zoom, deep links
- **Auth** — password, key file, PEM text
- **Themes** — OneDark / One Light, system auto-detection

### Platforms

| Platform | Version | Status |
|---|---|---|
| **Windows** | 10+ (x64) | primary test platform |
| **Android** | 7.0+ (API 24) | primary test platform |
| **Linux** | x64, GTK 3 | occasionally tested |
| **macOS** | 10.15+ (Intel + Apple Silicon) | occasionally tested |
| **iOS** | 13.0+ | not built |

## Installation

### Pre-built Binaries

Download from [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases):

- **Linux:** AppImage, .deb, tar.gz
  > Optional: `libsecret-1-0` for OS keychain encryption (`sudo apt install libsecret-1-0`). Without it the app works fine — only plaintext and master password modes are available.
- **Windows:** EXE installer, portable zip
- **macOS:** dmg, tar.gz
- **Android:** APK (arm64, arm, x64)

To build from source, see [CONTRIBUTING.md](docs/CONTRIBUTING.md).

> [!IMPORTANT]
> **One-time manual reinstall (from 5.8.1 and earlier).** Starting with 5.8.2 the release-signing scheme moves from per-artefact `.sig` files to a single signed `SHA256SUMS` manifest per release. Auto-update cannot bridge that boundary: older installs still look for per-artefact signatures that 5.8.2+ no longer publish. Download the latest binary from the [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases) page manually once — from then on auto-update works as before.

### Manual Verification

Every release ships three companion files so users can verify binaries by hand:

- `letsflutssh-<version>-SHA256SUMS` — plaintext hash manifest
- `letsflutssh-<version>-SHA256SUMS.sig` — Ed25519 signature over the manifest
- `letsflutssh-release.pub` — PEM public key (byte-identical to the key pinned in the app)

```bash
# Verify the manifest signature
openssl pkeyutl -verify -pubin -inkey letsflutssh-release.pub \
  -rawin -in letsflutssh-<version>-SHA256SUMS \
  -sigfile letsflutssh-<version>-SHA256SUMS.sig

# Verify the artefact's hash against the signed manifest
sha256sum --check letsflutssh-<version>-SHA256SUMS --ignore-missing
```

Both steps must succeed before installing. See [SECURITY.md](.github/SECURITY.md) for the full trust model.

### Data Locations

Sessions, credentials, known hosts, snippets, tags, and app config are stored in the OS per-app data directory. Logs live in a `logs/` subfolder. Remove these paths for a clean reinstall (e.g. after a release-key rotation where auto-update refuses to cross the boundary, or to reset all state).

| Platform | Path |
|---|---|
| **Linux** | `~/.local/share/com.llloooggg.letsflutssh/` |
| **macOS** | `~/Library/Application Support/com.llloooggg.letsflutssh/` |
| **Windows** | `%APPDATA%\com.llloooggg.letsflutssh\` (i.e. `C:\Users\<you>\AppData\Roaming\com.llloooggg.letsflutssh\`) |
| **Android** | App uninstall removes everything (no user-reachable path) |
| **iOS** | App uninstall removes everything (sandboxed) |

Downloaded update binaries are cached separately under the same directory (`updates/` subfolder) and are deleted after install.

> [!WARNING]
> Wiping the data directory deletes **all** saved sessions and any unexported credentials. Export your data first via **Settings → Export** if you want to keep it.

## Security

See [SECURITY.md](.github/SECURITY.md) for vulnerability reporting and security scope.

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.

## Architecture

For detailed technical documentation — module structure, data models, data flow diagrams, API references, design decisions, and CI/CD pipeline — see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Contributions welcome — see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for build instructions, dev workflow, and PR guidelines.

## Support

If you find this project useful, you can support its development:

[![Donate](https://img.shields.io/badge/Donate-DonationAlerts-orange?style=for-the-badge)](https://www.donationalerts.com/r/llloooggg)
