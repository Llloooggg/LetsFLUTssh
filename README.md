# LetsFLUTssh

[![CI & Build](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/build.yml/badge.svg)](https://github.com/Llloooggg/LetsFLUTssh/actions/workflows/build.yml)
[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=coverage)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=Llloooggg_LetsFLUTssh&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=Llloooggg_LetsFLUTssh)
[![License: GPL-3.0](https://img.shields.io/github/license/Llloooggg/LetsFLUTssh)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Llloooggg/LetsFLUTssh?include_prereleases)](https://github.com/Llloooggg/LetsFLUTssh/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS%20%7C%20Android%20%7C%20iOS-blue)](https://github.com/Llloooggg/LetsFLUTssh)

> **Disclaimer:** This is a functional neuroslop pet project — built entirely with AI assistance for personal use, self-education, and fun. Use at your own risk.

Lightweight cross-platform SSH/SFTP client with GUI, built with Flutter.

Open-source alternative to Xshell and Termius — runs on Windows, Linux, macOS, Android, and iOS.

![SSH Terminal — session tree, tabbed terminal with htop](docs/screenshots/LetsFLUTssh_ssh.png)
![SFTP File Browser — dual-pane local/remote with transfer panel](docs/screenshots/LetsFLUTssh_sftp.png)

## Tech Stack

- **Flutter** — cross-platform UI framework (Skia/Impeller rendering)
- **dartssh2** — SSH2 protocol implementation (auth, shell, SFTP, port forwarding)
- **xterm.dart** — terminal emulator widget (VT100/xterm, 256-color, RGB, mouse)
- **Riverpod** — state management
- **pointycastle** — AES-256-GCM encryption (pure Dart, no native deps)
- **permission_handler** — runtime permission requests (Android storage access)

## Features

### SSH Terminal

- Full xterm/VT100 terminal emulation (256-color, RGB, curses apps)
- Password, key file, PEM text, and SSH agent authentication
- Auto-detect SSH keys from `~/.ssh/` (id_ed25519, id_ecdsa, id_rsa)
- Keep-alive and auto-reconnect
- Scrollback buffer (configurable, default 5000 lines)
- Text selection, copy/paste
- Mouse reporting for TUI apps (htop, vim, mc)
- **Tiling / split panes** — split vertically or horizontally (like tmux), recursive nesting, drag-to-resize
- Terminal search (Ctrl+Shift+F) with match highlighting
- Right-click context menu (Copy / Paste / Split / Close Pane)

### Session Manager

- Save and organize SSH sessions
- Nested group folders (e.g. `Production/Web/nginx1`) with create/rename/delete
- Search and filter by label, group, host, user
- Unified New Session dialog (connect without saving, or save & connect)
- Drag & drop sessions and folders to reorganize
- Context menu: SSH, SFTP, edit, delete, duplicate
- Indent guide lines for nested groups
- Host key verification (TOFU) with SHA256 fingerprint dialog

### SFTP File Browser

- Dual-pane layout: local files | remote files
- Upload, download, rename, delete, create folders
- Drag & drop between panes and from OS file manager
- Rubber-band (marquee) multi-select
- Transfer queue with parallel workers
- Transfer history with Local/Remote paths, size, duration details
- Sortable columns (name, size, modified, mode, owner) with column dividers
- Mouse back/forward button navigation

### Multi-Tab Interface

- Multiple terminal and SFTP tabs
- Drag-to-reorder tabs
- Multiple SFTP tabs per SSH connection
- SFTP-only connections (no terminal)

### Security & Data Portability

- Credentials encrypted with AES-256-GCM (stored separately from session metadata)
- File permissions restricted (chmod 600) on Unix systems
- Known hosts verification (TOFU) — explicit user confirmation required, no auto-accept
- Data export/import to `.lfs` archive (ZIP + AES-256-GCM, PBKDF2-SHA256 600k iterations)
- Import modes: merge (add new) or replace (overwrite all)
- Auto-migration from plaintext to encrypted storage on upgrade

### Appearance

- **OneDark theme** — Atom OneDark Pro color palette (dark mode)
- **One Light theme** — matching light variant
- System theme auto-detection
- Configurable font size, scrollback, keep-alive, and more
- About section with version and GitHub link

### Mobile

- Bottom navigation (Sessions / Terminal / Files)
- **SSH virtual keyboard** — Esc, Tab, Ctrl, Alt, arrows, F1-F12, sticky modifiers
- Pinch-to-zoom terminal font size
- Single-pane SFTP with Local/Remote toggle
- Long-press context menu for session management (connect, edit, delete, move to folder)
- Long-press selection mode with bulk actions in file browser
- Swipe left/right to switch navigation tabs
- Deep link: `letsflutssh://connect?host=X&user=Y`
- Open SSH key files (.pem/.key) and .lfs archives directly from file manager

### Cross-Platform

- **Windows:** 10+ (x64)
- **Linux:** x64, GTK 3 (Ubuntu 20.04+, Fedora 33+, Arch, etc.)
- **macOS:** 10.15 Catalina+ (universal — Intel + Apple Silicon)
- **Android:** 7.0 Nougat+ (API 24)
- **iOS:** 13.0+
- Native rendering via Flutter (Skia/Impeller) — no WebView

## Installation

### Pre-built Binaries

Download from [Releases](https://github.com/Llloooggg/LetsFLUTssh/releases):

- **Linux:** AppImage, .deb, tar.gz
- **Windows:** EXE installer, portable zip
- **macOS:** dmg, tar.gz
- **Android:** APK (arm64, arm, x64)

### Build from Source

**Prerequisites:**

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x (Dart 3.x included)
- Platform-specific toolchain (see below)

#### Linux (Debian/Ubuntu)

```bash
# System dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev lld

# If using LLVM-based clang (e.g. clang-19), install matching lld:
sudo apt-get install lld-19

# Clone, install deps, build
git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
make deps
make build-linux

# Or use the shortcut:
make deps-linux   # installs system deps
make build-linux  # builds release binary
```

Build output: `build/linux/x64/release/bundle/`

#### Linux (Fedora/RHEL)

```bash
sudo dnf install clang cmake ninja-build gtk3-devel lld pkg-config
```

#### Linux (Arch)

```bash
sudo pacman -S clang cmake ninja gtk3 lld pkg-config
```

#### Windows

Requires Visual Studio 2022 with **"Desktop development with C++"** workload.

```powershell
# Install Visual Studio C++ workload (if not installed)
winget install Microsoft.VisualStudio.2022.Community
# (select "Desktop development with C++" during setup)

git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
flutter pub get
flutter build windows
```

Build output: `build\windows\x64\runner\Release\`

#### macOS

Requires Xcode command line tools.

```bash
xcode-select --install

git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
make deps
make build-macos
```

Build output: `build/macos/Build/Products/Release/`

#### Android

Requires Android SDK (via Android Studio or standalone SDK).

```bash
make build-apk    # APK
make build-aab    # App Bundle (for Play Store)
```

#### iOS

Requires Xcode on macOS.

```bash
make build-ios
```

## Current Status

**v0.9.4** — All core features implemented across 9 development phases:

| Phase | What                                                                       |
| ----- | -------------------------------------------------------------------------- |
| 1-3   | SSH terminal, session manager, SFTP file browser (MVP)                     |
| 4     | Polish — tab reorder, toast notifications, settings, responsive layout     |
| 5     | Security — AES-256-GCM credential encryption, .lfs export/import           |
| 6     | Terminal search, auto-detect SSH keys, session folders                     |
| 7     | Tiling terminal layout — recursive split, drag-to-resize, focus tracking   |
| 8     | Mobile UI — bottom nav, SSH virtual keyboard, deep links, swipe navigation |
| 9     | 490 tests, security audit, performance profiling, packaging, user docs     |

## Development

```bash
make run            # Run in debug mode
make test           # Run all tests
make analyze        # Run Dart analyzer
make check          # Analyzer + tests
make gen            # Code generation (freezed, json_serializable)
make clean          # Remove build artifacts
make help           # Show all available targets
```

See [User Guide](docs/USER_GUIDE.md) for usage instructions, [CLAUDE.md](CLAUDE.md) for architecture details, and [PLAN.md](PLAN.md) for the development roadmap.

## License

GPL-3.0 — see [LICENSE](LICENSE) for details.

## Contributing

_Coming soon_
