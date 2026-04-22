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
- **Security** — encrypted SQLite storage (ChaCha20-Poly1305 AEAD via SQLite3MultipleCiphers — native AEAD with per-page 16-byte authentication tags, constant-time by design, D.J. Bernstein / Signal / WireGuard lineage). Three security tiers with a separate Paranoid alternative (T0 plaintext / T1 OS keychain / T2 hardware-bound key in Secure Enclave, StrongBox, or TPM 2.0 / Paranoid: master-password-derived, no OS storage). Two orthogonal modifiers on T1 / T2: password (pre-vault HMAC gate) and biometric (OS-biometric shortcut releasing the stored password — never a replacement for it). Atomic re-encryption on every tier or modifier change. Page-locked in-memory secrets (`mlock` / `VirtualLock`), startup process hardening (`prctl PR_SET_DUMPABLE`, `ptrace PT_DENY_ATTACH`). Argon2id-only `.lfs` export / import. TOFU host-key verification. Full threat model in [SECURITY.md](docs/SECURITY.md)
- **Import/export** — encrypted `.lfs` archives, QR sharing for small exports, paste-deep-link import (no camera), in-app QR scanner (AndroidX CameraX + ZXing on Android, AVFoundation on iOS — no Google Play Services / MLKit)
- **Mobile** — virtual keyboard (Esc/Tab/Ctrl/Alt/F1-F12), pinch-to-zoom, deep links
- **Auth** — password, key file, PEM text
- **Themes** — OneDark / One Light, system auto-detection

### Platforms

| Platform | Version | Status |
|---|---|---|
| **Windows** | 10+ (x64)¹ | primary test platform |
| **Android** | 9.0+ (API 28) | primary test platform |
| **Linux** | x64, GTK 3 | occasionally tested |
| **macOS** | 10.15+ (Intel + Apple Silicon) | occasionally tested |
| **iOS** | 13.0+ | not built |

¹ Windows 10 RTM launches, but the optional biometric-unlock path (Windows Hello via `local_auth`) needs Windows 10 version **1809 (build 17763)** or newer because it calls into WinRT Hello APIs introduced in that release.

## Installation

Download the build for your platform from [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases), then follow the per-platform steps below. To build from source instead, see [CONTRIBUTING.md](docs/CONTRIBUTING.md).

### Linux

Available formats: **AppImage**, **.deb**, **tar.gz**.

```bash
# AppImage — single self-contained file, no install
chmod +x LetsFLUTssh-*.AppImage
./LetsFLUTssh-*.AppImage

# .deb — Debian / Ubuntu / Mint
sudo apt install ./letsflutssh_*.deb

# tar.gz — portable, extract anywhere
tar xzf letsflutssh-*.tar.gz
cd letsflutssh && ./letsflutssh
```

> Optional: `libsecret-1-0` for the T1 OS-keychain tier (`sudo apt install libsecret-1-0`). Without it the app still works — the wizard falls back to T0 plaintext, T2 hardware (if a TPM 2.0 is present + `tpm2-tools` installed), or the Paranoid master-password alternative. Biometric modifier on Linux additionally requires `fprintd` with at least one enrolled finger.

> Optional: `fprintd` for biometric unlock in master-password mode (fingerprint reader required). Install + enrol one finger once, the Settings toggle picks it up on next launch. Without it the biometric toggle stays disabled with a clear reason; master-password unlock keeps working.
>
> ```bash
> # Debian / Ubuntu / Mint
> sudo apt install fprintd libpam-fprintd
> # Fedora
> sudo dnf install fprintd fprintd-pam
> # Arch / Manjaro
> sudo pacman -S fprintd
> # openSUSE
> sudo zypper install fprintd fprintd-pam
>
> # one-off: enrol a finger (any distro)
> fprintd-enroll
> ```
>
> Optional (upgrades the biometric-unlock backing from software to TPM2-hardware): `tpm2-tools` if your machine has a TPM2 chip (`ls /dev/tpmrm0` → exists). The Settings biometric row labels itself `Hardware-backed` when both TPM2 and `fprintd` are available; any biometric-enrolment change invalidates the sealed blob the next time around (equivalent to Apple's `biometryCurrentSet`).
>
> ```bash
> # Debian / Ubuntu / Mint
> sudo apt install tpm2-tools
> # Fedora
> sudo dnf install tpm2-tools
> # Arch / Manjaro
> sudo pacman -S tpm2-tools
> # openSUSE
> sudo zypper install tpm2.0-tools
>
> # one-off: make sure the current user can talk to the TPM
> sudo usermod -aG tss "$USER"
> # log out + back in for the group change to take effect
> ```

### Windows

Available formats: **EXE installer** (Inno Setup), **portable zip**.

- **Installer:** double-click the `.exe`, follow the wizard. Adds Start Menu entry and uninstaller.
- **Portable:** extract the zip anywhere, run `letsflutssh.exe` directly. No install, no registry writes.

### macOS

Available formats: **.dmg**, **tar.gz**. Universal binary (Intel + Apple Silicon).

- **.dmg:** open, drag `LetsFLUTssh.app` to `/Applications/`.
- **tar.gz:** extract, move `LetsFLUTssh.app` to `/Applications/`.

The build is **ad-hoc signed**, not Developer-ID signed (no Apple account). On first launch macOS Gatekeeper will block it — right-click the app and choose **Open**, then confirm. Or remove the quarantine attribute once:

```bash
xattr -dr com.apple.quarantine /Applications/LetsFLUTssh.app
```

**Keychain tier (T1) needs a personal re-sign.** The ad-hoc Code Directory hash changes every release, and macOS Keychain Services bind stored items to that hash — first write fails with `errSecMissingEntitlement` and the app surfaces the wizard with T1 greyed out. A one-shot helper script is shipped with the macOS release assets; download `macos-resign.sh` from the same release, then:

```bash
chmod +x macos-resign.sh
./macos-resign.sh sign           # default action — `./macos-resign.sh` also works
./macos-resign.sh uninstall      # later, to remove the personal cert
./macos-resign.sh help           # full options
```

`sign` creates a personal self-signed code-signing cert the first time it runs (stored in your login keychain, trusted for codesign only), re-signs the installed app with it, and drops quarantine. Re-run after each release — the cert is reused so Keychain Services keeps treating the app as the same identity across upgrades. Nothing is granted system-wide; no admin password is needed beyond `sudo` for the codesign step if the app lives in `/Applications`.

`uninstall` removes the personal cert from your login keychain and the trust database. The app stays installed but any keychain items written under the cert become unreadable — the first launch after uninstall will surface the tier wizard again so you can switch to Paranoid or T0.

If you do not need T1 (keychain) unlock, the **Paranoid** tier (master password, Argon2id-derived DB key) works without the script and gives stronger encryption at the cost of a password prompt on every launch.

### Android

Available format: **APK** (split per ABI: `arm64-v8a`, `armeabi-v7a`, `x86_64`). Pick `arm64-v8a` for any modern device.

In Android Settings, enable **Install unknown apps** for the file manager or browser you'll use to open the APK. Tap the `.apk` file and confirm. No Google Play Services required, no MLKit, no GPS dependency.

### User Data & Uninstalling

Sessions, credentials, known hosts, snippets, tags, and app config live in the OS per-app data directory (`logs/` subfolder for logs, `updates/` subfolder for cached update binaries — deleted after install). The data directory is **separate from the app binary**, so removing the app does **not** wipe data by design (protects against accidental loss on reinstall / upgrade or release-key rotation). For a clean reset, delete the data path manually after uninstalling.

| Platform | Data path | Uninstall app | Data wiped on uninstall? |
|---|---|---|---|
| **Linux** | `~/.local/share/com.llloooggg.letsflutssh/` | AppImage: delete the file • .deb: `sudo apt remove letsflutssh` • tar.gz: delete the extracted folder | No — wipe data path manually |
| **macOS** | `~/Library/Application Support/com.llloooggg.letsflutssh/` | Drag `/Applications/LetsFLUTssh.app` to Trash | No — wipe data path manually |
| **Windows** | `%APPDATA%\com.llloooggg.letsflutssh\` | Installer: Settings → Apps → LetsFLUTssh → Uninstall (offers an "Also delete user data" checkbox, off by default) • Portable: delete the extracted folder | Only if installer checkbox ticked |
| **Android** | sandbox (no user-reachable path) | Long-press app icon → Uninstall (or Settings → Apps → LetsFLUTssh → Uninstall) | Yes — sandbox is wiped |
| **iOS** | sandbox (no user-reachable path) | Long-press icon → Remove App → Delete App | Yes — sandbox is wiped |

> [!WARNING]
> Wiping the data directory deletes **all** saved sessions and any unexported credentials. Export your data first via **Settings → Export** if you want to keep it.

## Security

See [SECURITY.md](docs/SECURITY.md) for vulnerability reporting and security scope.

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.

## Architecture

For detailed technical documentation — module structure, data models, data flow diagrams, API references, design decisions, and CI/CD pipeline — see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Contributing

Contributions welcome — see [CONTRIBUTING.md](docs/CONTRIBUTING.md) for build instructions, dev workflow, and PR guidelines.

## Support

If you find this project useful, you can support its development:

[![Donate](https://img.shields.io/badge/Donate-DonationAlerts-orange?style=for-the-badge)](https://www.donationalerts.com/r/llloooggg)
