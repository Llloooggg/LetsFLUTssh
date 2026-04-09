# Contributing to LetsFLUTssh

## Build from Source

**Prerequisites:**

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **≥ 3.41.0** (ships Dart ≥ 3.11.3)
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

For detailed technical documentation see [ARCHITECTURE.md](ARCHITECTURE.md) — module structure, data models, API references, state management, data flows, and design decisions.

## Coding Conventions

- **Logging** — `AppLogger.instance.log(message, name: 'Tag')`, never `print()`/`debugPrint()` — [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference)
- **State** — all state via Riverpod providers, no global mutable state. Use `.select()` on broad providers to avoid unnecessary rebuilds — [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod)
- **Models** — immutable with `copyWith`, `==`, `hashCode`, `toJson`/`fromJson` — [§10 Data Models](ARCHITECTURE.md#10-data-models)
- **Theme** — OneDark, semantic color constants, no hardcoded `Colors` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Font sizes** — use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (platform-aware), never hardcode `fontSize` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Border radius** — use `AppTheme.radiusSm`/`radiusMd`/`radiusLg`, never hardcode `BorderRadius.circular(N)` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Buttons** — `AppIconButton` for icon buttons, `HoverRegion` for custom hover. Never use bare `IconButton` or `InkWell` — [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference)
- **Credentials** — `CredentialStore` (AES-256-GCM), never plain JSON — [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity)
- **Testing** — one test file per source file, DI hooks for testability — [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks)

## Commit Messages

Format: `type: short description`

| Prefix      | Use for                         | Appears in release notes? |
|-------------|---------------------------------|---------------------------|
| `feat:`     | New features                    | Yes — under **Features**  |
| `fix:`      | Bug fixes                       | Yes — under **Fixes**     |
| `refactor:` | Code improvements (no new behavior) | Yes — under **Improvements** |
| `perf:`     | Performance improvements        | Yes — under **Improvements** |
| `build:`    | Build system, dependencies      | No                        |
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

Version bumps are **fully automated**. The bump script (`scripts/bump-version.sh`) parses conventional commit prefixes since the last tag and bumps `pubspec.yaml`. It runs on `dev` before creating a PR to `main`; for Dependabot PRs, CI runs it automatically.

| Commit prefix                           | Bump      |
|-----------------------------------------|-----------|
| `fix:`, `chore:`, `refactor:`, `perf:`, `build:`, Dependabot `Bump ...` | **patch** |
| `feat:`                                 | **minor** |
| `BREAKING CHANGE` or `feat!:`           | **major** |
| `docs:`, `test:`, `ci:`                 | **no bump** |

**Do not bump the version manually** — just use the correct conventional commit prefix. The `version:` field in `pubspec.yaml` remains the single source of truth (`package_info_plus` reads it at runtime).

## Pull Requests

1. Fork the repo and create a feature branch (`git checkout -b feat/my-feature`)
2. Target the **`dev`** branch — never `main` directly
3. Follow commit message format (`type: description`) — CI enforces this on PRs
4. Use correct conventional commit prefixes — version bumps are automated before PR merge
5. `make analyze` and `make test` must pass
6. All new code must have tests (80% coverage minimum, 100% target)
7. One logical change per PR
8. Open a Pull Request — fill in the template

All checks must pass before merge: CI (analyze + test), OSV-Scanner, Semgrep, and CodeQL.

## CI/CD Pipeline

Every push and PR is checked by multiple pipelines. For the full workflow graph and detailed descriptions see [§15 CI/CD Pipeline](ARCHITECTURE.md#15-cicd-pipeline).

| Workflow | Purpose | Required on PR? |
|----------|---------|-----------------|
| `ci.yml` | Analyze, test, coverage, commit-lint, dependency review | Yes |
| `ci-sonarcloud.yml` | Code quality + coverage (after CI succeeds) | No (fork PRs have no token) |
| `osv.yml` | Dependency CVE scanning (`pubspec.lock`) | Yes |
| `semgrep.yml` | SAST scan — static security analysis of Dart code | Yes |
| `codeql.yml` | GitHub Actions security analysis | Yes |
| `scorecard.yml` | OpenSSF supply chain assessment | No (main only) |
| `build-release.yml` | Build all platforms + GitHub Release (on tag) | — |

**Dependabot auto-releases:** when Dependabot opens a Dart dependency update PR (`pub` ecosystem), `dependabot-auto.yml` runs `scripts/bump-version.sh` in the PR branch to bump the patch version, then auto-merges. CI runs on `main` after merge; if it passes, `ci-auto-tag.yml` creates a tag and triggers the full build + release pipeline. If CI fails — no tag, no release. GitHub Actions updates are auto-merged but do not trigger a version bump (they don't affect the shipped app).

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
