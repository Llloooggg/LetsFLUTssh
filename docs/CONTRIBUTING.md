# Contributing to LetsFLUTssh

## Build from Source

**Prerequisites:**

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **≥ 3.41.0** (ships Dart ≥ 3.11.3)
- Platform-specific toolchain (see below)

### Linux (Debian/Ubuntu)

```bash
# System dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev lld

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
sudo dnf install clang cmake ninja-build gtk3-devel libsecret-devel lld pkg-config
```

### Linux (Arch)

```bash
sudo pacman -S clang cmake ninja gtk3 libsecret lld pkg-config
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

**Release signing:** Local builds use the debug keystore by default. CI release builds use a persistent keystore from GitHub Secrets — see [Release signing setup](#release-signing-setup) below.

#### Release signing setup

The Android release builds in CI need a stable signing key — without it, every build is signed with a different debug key, so users cannot update the app (Android rejects the upgrade as a "package conflict").

**One-time keystore generation (do this once, store securely):**

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias letsflutssh
```

Set passwords and remember them. Back up `release.jks` somewhere safe — losing it means future updates can't be signed with the same key, breaking app updates for all users.

**GitHub Secrets to add to the repo:**

- `ANDROID_KEYSTORE_BASE64` — output of `base64 -w0 release.jks`
- `ANDROID_KEY_PROPERTIES` — content of a `key.properties` file:
  ```
  storePassword=YOUR_STORE_PASSWORD
  keyPassword=YOUR_KEY_PASSWORD
  keyAlias=letsflutssh
  storeFile=app/release.jks
  ```

The CI workflow (`build-release.yml`) decodes the keystore and writes `android/key.properties` before building the APK.

For local release builds, drop the same `release.jks` into `android/app/` and create `android/key.properties` with the same content. Both files are gitignored.

### iOS

Requires Xcode on macOS.

```bash
make build-ios
```

## Development

```bash
make hooks          # One-time: install git pre-commit (runs make check)
make run            # Run in debug mode
make test           # Run all tests (with coverage)
make analyze        # Run Dart analyzer (--fatal-infos)
make check          # Analyzer + tests
make gen            # Code generation (freezed, json_serializable)
make clean          # Remove build artifacts
make help           # Show all available targets
```

> **First clone:** run `make hooks` once. After that, every `git commit`
> invokes `make check` (analyzer + full test suite) before the commit
> is recorded. To bypass for an emergency commit, prefix with
> `SKIP_PRECOMMIT=1`.

**New contributors:** start with [ADDING_A_FEATURE.md](ADDING_A_FEATURE.md) — a hands-on walkthrough of the project's layers, conventions, and tooling using a small example feature.

For detailed technical documentation see [ARCHITECTURE.md](ARCHITECTURE.md) — module structure, data models, API references, state management, data flows, and design decisions.

## Coding Conventions

- **Reuse first** — before adding a new widget, helper, mixin, style constant, or store, search `lib/widgets/`, `lib/theme/`, and `lib/core/**` for an existing equivalent and extend it (add a parameter) instead of forking. Full rule and canonical primitives: [§1 Reuse principle](ARCHITECTURE.md#1-high-level-overview)
- **End-user runs zero manual setup** — never introduce a feature that hard-requires the user to install something themselves. If a feature needs an OS capability, prefer (1) bundling it with the app (e.g. `sqlite3` via build hooks, native QR scanner), then (2) a built-in fallback (e.g. master password if no keychain), and only as a last resort (3) an *optional* OS dep with graceful degradation in-UI + a README install snippet per platform. Full rule: [§1 Self-contained-binary principle](ARCHITECTURE.md#1-high-level-overview)
- **Logging** — `AppLogger.instance.log(message, name: 'Tag')`, never `print()`/`debugPrint()` — [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference)
- **State** — shared / app-wide state via Riverpod providers (no global mutable state). Widget-local state (dialog / pane / panel) via `ChangeNotifier` + `AnimatedBuilder` — see `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`. Use `.select()` on broad Riverpod providers to avoid unnecessary rebuilds — [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod)
- **Models** — immutable with `copyWith`, `==`, `hashCode`, `toJson`/`fromJson` — [§10 Data Models](ARCHITECTURE.md#10-data-models)
- **Theme** — OneDark, semantic color constants, no hardcoded `Colors` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Font sizes** — use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (platform-aware), never hardcode `fontSize` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Border radius** — use `AppTheme.radiusSm`/`radiusMd`/`radiusLg`, never hardcode `BorderRadius.circular(N)` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Buttons** — `AppIconButton` for icon buttons, `HoverRegion` for custom hover. Never use bare `IconButton` or `InkWell` — [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference)
- **Security** — three-level encryption (plaintext/keychain/master password), all stores use `AesGcm` utility, `flutter_secure_storage` optional (requires `libsecret-1-dev` on Linux) — [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity)
- **Testing** — one test file per source file, DI hooks for testability — [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks)

## Commit Messages

Format: `type: short description`

| Prefix      | Use for                         | Appears in release notes? |
|-------------|---------------------------------|---------------------------|
| `feat:`     | New features                    | Yes — under **Features**  |
| `fix:`      | Bug fixes                       | Yes — under **Fixes**     |
| `refactor:` | Code improvements (no new behavior) | Yes — under **Improvements** |
| `perf:`     | Performance improvements        | Yes — under **Improvements** |
| `security:` | Hardening / vulnerability fix   | Yes — under **Security**  |
| `build:`    | Build system, dependencies      | No                        |
| `test:`     | Test changes only               | No                        |
| `docs:`     | Documentation only              | No                        |
| `chore:`    | Config, tooling                 | No                        |
| `chore(deps):` | Dependency updates (auto-generated) | Yes — under **Dependencies** |
| `ci:`       | CI/CD workflow changes          | No                        |
| `i18n:`     | Translation / l10n string changes | No                      |
| `style:`    | Formatting, whitespace          | No                        |
| `revert:`   | Revert a previous commit        | No                        |

**Prefer a scope in parentheses** when the change is localized to one module (e.g. `feat(snippets):`, `fix(import):`, `test(known-hosts):`) — lowercase, alphanumeric + dashes. Drop the scope only when the change is genuinely cross-cutting and no single module name fits (e.g. plain `docs:`, `chore:`, `ci:`).

**Examples:**

```
feat(port-forward): add port forwarding support
fix(sftp): handle SSH disconnect during file transfer
refactor(dialogs): extract shared dialog logic into ConfirmDialog widget
test(credentials): add tests for credential store encryption
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
| `fix:`, `refactor:`, `perf:`, `build:`, `security:`, Dependabot `Bump ...` | **patch** |
| `feat:`                                 | **minor** |
| `BREAKING CHANGE` or `feat!:`           | **major** |
| `docs:`, `test:`, `ci:`, `chore:`, `i18n:`, `style:`, `revert:` | **no bump** |

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

See [SECURITY.md](../.github/SECURITY.md) for reporting vulnerabilities.
