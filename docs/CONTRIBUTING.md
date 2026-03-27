# Contributing to LetsFLUTssh

## Build from Source

**Prerequisites:**

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x (Dart 3.x included)
- Platform-specific toolchain (see below)

### Linux (Debian/Ubuntu)

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

### Linux (Fedora/RHEL)

```bash
sudo dnf install clang cmake ninja-build gtk3-devel lld pkg-config
```

### Linux (Arch)

```bash
sudo pacman -S clang cmake ninja gtk3 lld pkg-config
```

### Windows

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

### macOS

Requires Xcode command line tools.

```bash
xcode-select --install

git clone https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
make deps
make build-macos
```

Build output: `build/macos/Build/Products/Release/`

### Android

Requires Android SDK (via Android Studio or standalone SDK).

```bash
make build-apk    # APK
make build-aab    # App Bundle (for Play Store)
```

### iOS

Requires Xcode on macOS.

```bash
make build-ios
```

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

See [CLAUDE.md](CLAUDE.md) for architecture details and coding conventions.

## Commit Messages

Format: `type: short description`

| Prefix | Use for |
|--------|---------|
| `feat:` | New features |
| `fix:` | Bug fixes |
| `refactor:` | Code improvements |
| `test:` | Test changes only |
| `docs:` | Documentation only |
| `chore:` | Dependencies, config |
| `ci:` | CI/CD changes |

Commit messages appear in auto-generated release notes — keep them clear and user-readable.

## Pull Requests

1. Fork the repo
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. `make analyze` and `make test` must pass
4. All new code must have tests (80% coverage minimum, 100% target)
5. One logical change per PR
6. Open a Pull Request

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
