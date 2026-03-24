# LetsFLUTssh

Lightweight cross-platform SSH/SFTP client with GUI, built with Flutter.

Open-source alternative to Xshell and Termius — runs on Windows, Linux, macOS, Android, and iOS.

## Features

### SSH Terminal
- Full xterm/VT100 terminal emulation (256-color, RGB, curses apps)
- Password, key file, PEM text, and SSH agent authentication
- Keep-alive and auto-reconnect
- Scrollback buffer (configurable, default 5000 lines)
- Text selection, copy/paste
- Mouse reporting for TUI apps (htop, vim, mc)
- **Tiling / split panes** — split vertically or horizontally (like tmux), recursive nesting, drag-to-resize
- Terminal search (Ctrl+Shift+F) with match highlighting

### Session Manager
- Save and organize SSH sessions
- Nested group folders (e.g. `Production/Web/nginx1`)
- Search and filter
- Quick Connect for one-off connections
- Context menu: connect, edit, delete, duplicate

### SFTP File Browser
- Dual-pane layout: local files | remote files
- Upload, download, rename, delete, create folders
- Drag & drop between panes and from OS file manager
- Transfer queue with parallel workers
- Transfer history with progress tracking
- Sortable file table (name, size, permissions, date)

### Multi-Tab Interface
- Multiple terminal and SFTP tabs
- Drag-to-reorder tabs
- Multiple SFTP tabs per SSH connection
- SFTP-only connections (no terminal)

### Security & Data Portability
- Credentials encrypted with AES-256-GCM (stored separately from session metadata)
- Known hosts verification (TOFU)
- Data export/import to `.lfs` archive (ZIP + AES-256-GCM, master password protected)
- Import modes: merge (add new) or replace (overwrite all)
- Auto-migration from plaintext to encrypted storage on upgrade

### Cross-Platform
- **Desktop:** Windows, Linux, macOS
- **Mobile:** Android, iOS
- Native rendering via Flutter (Skia/Impeller) — no WebView

## Screenshots

_Coming soon_

## Installation

### Pre-built Binaries

_Coming soon — see Releases page_

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

**v0.5.0** — Phase 5 (Data Portability & Security) complete. Encrypted credential storage (AES-256-GCM), .lfs archive export/import with master password, SFTP file browser with transfer queue, settings screen, toast notifications, responsive layout.

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

See [CLAUDE.md](CLAUDE.md) for architecture details and [PLAN.md](PLAN.md) for the development roadmap.

## Tech Stack

- **Flutter** — cross-platform UI framework (Skia/Impeller rendering)
- **dartssh2** — SSH2 protocol implementation (auth, shell, SFTP, port forwarding)
- **xterm.dart** — terminal emulator widget (VT100/xterm, 256-color, RGB, mouse)
- **Riverpod** — state management

## Predecessor

This project is a rewrite of [LetsGOssh](https://github.com/Llloooggg/LetsGOssh) (Go/Fyne). All features from the Go version are carried over, with improvements enabled by Flutter's richer widget ecosystem and cross-platform mobile support.

## License

MIT

## Contributing

_Coming soon_
