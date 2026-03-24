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

### Security
- Credentials stored in OS keychain (not plain text)
- Known hosts verification (TOFU)
- Data export/import with AES-256-GCM encryption

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
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x
- Dart 3.x (included with Flutter)

**Linux:**
```bash
# Install Flutter dependencies
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

# Clone and build
git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
flutter pub get
flutter build linux
```

**Windows:**
```powershell
git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
flutter pub get
flutter build windows
```

**macOS:**
```bash
git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
flutter pub get
flutter build macos
```

**Android:**
```bash
flutter build apk
# or
flutter build appbundle
```

## Development

```bash
# Run in debug mode
flutter run

# Run tests
flutter test

# Analyze code
flutter analyze
```

See [CLAUDE.md](CLAUDE.md) for architecture details and [PLAN.md](PLAN.md) for the development roadmap.

## Tech Stack

- **Flutter** — cross-platform UI framework (Skia/Impeller rendering)
- **dartssh2** — SSH2 protocol implementation (auth, shell, SFTP, port forwarding)
- **xterm.dart** — terminal emulator widget (VT100/xterm, 256-color, RGB, mouse)
- **Riverpod** — state management
- **flutter_secure_storage** — OS keychain integration

## Predecessor

This project is a rewrite of [LetsGOssh](https://github.com/Llloooggg/LetsGOssh) (Go/Fyne). All features from the Go version are carried over, with improvements enabled by Flutter's richer widget ecosystem and cross-platform mobile support.

## License

MIT

## Contributing

_Coming soon_
