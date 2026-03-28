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
flutter build windows --release
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
make build-apk    # APK (per-ABI: arm64, arm, x64)
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
make test           # Run all tests (with coverage)
make analyze        # Run Dart analyzer (--fatal-infos)
make check          # Analyzer + tests
make gen            # Code generation (freezed, json_serializable)
make clean          # Remove build artifacts
make help           # Show all available targets
```

See [CLAUDE.md](../CLAUDE.md) for architecture details and coding conventions.

## Commit Messages

Format: `type: short description`

| Prefix      | Use for                         | Appears in release notes? |
|-------------|---------------------------------|---------------------------|
| `feat:`     | New features                    | Yes — under **Features**  |
| `fix:`      | Bug fixes                       | Yes — under **Fixes**     |
| `refactor:` | Code improvements (no new behavior) | Yes — under **Improvements** |
| `test:`     | Test changes only               | No                        |
| `docs:`     | Documentation only              | No                        |
| `chore:`    | Config, tooling                 | No                        |
| `chore(deps):` | Dependency updates (auto-generated) | Yes — under **Dependencies** |
| `ci:`       | CI/CD workflow changes          | No                        |

**Examples:**

```
feat: add port forwarding support
fix: handle SSH disconnect during file transfer
refactor: extract shared dialog logic into ConfirmDialog widget
test: add tests for credential store encryption
docs: update README with mobile screenshots
chore: upgrade dartssh2 to 2.16.0
ci: add commit message linting for PRs
```

**Important:**

- Commit messages are **auto-generated into release notes** — keep them clear and user-readable.
- Start with a lowercase verb — no period at the end.
- If a commit includes both app changes and docs, the prefix describes the **app change** (docs ride along).
- CI validates commit message format on pull requests — commits that don't match the pattern will fail the check.

## Version Bumps

Changes that affect the shipped app **must** include a version bump in the same commit:

| Change                                  | Bump      |
|-----------------------------------------|-----------|
| Bug fix, refactoring, production code   | **patch** |
| New feature                             | **minor** |
| Breaking change (file format, API)      | **major** |

Bump the `version:` field in `pubspec.yaml` — it is the single source of truth (`package_info_plus` reads it at runtime).

**No bump needed:** test-only, docs-only, CI-only, or config-only changes (`test:`, `docs:`, `chore:`, `ci:` commits).

## Pull Requests

1. Fork the repo and create a feature branch (`git checkout -b feat/my-feature`)
2. Follow commit message format (`type: description`) — CI enforces this on PRs
3. If your change affects the shipped app, include a version bump (see above)
4. `make analyze` and `make test` must pass
5. All new code must have tests (80% coverage minimum, 100% target)
6. One logical change per PR
7. Open a Pull Request — fill in the template

## CI/CD Pipeline

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push to `main`, PRs | Analyze, test (with coverage), outdated deps, commit-lint |
| `sonarcloud.yml` | After CI succeeds (`workflow_run`) | Code quality + coverage analysis (separate from CI) |
| `build.yml` | Tag `v*` push, manual | Preflight (waits for CI + SonarCloud + OSV-Scanner), builds all platforms, creates GitHub Release |
| `dependabot-release.yml` | Dependabot PR merged | Auto patch-bump + tag + release for pub dependency updates |
| `osv-scanner.yml` | pubspec changes, weekly | Dependency CVE scanning |

**Dependabot auto-releases:** when Dependabot merges a Dart dependency update (`pub` ecosystem), the pipeline automatically bumps the patch version, creates a tag, and triggers a full build + release. GitHub Actions updates are auto-merged but do not trigger a release (they don't affect the shipped app).

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
