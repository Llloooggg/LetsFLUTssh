# Contributing to LetsFLUTssh

## Build from Source

**Prerequisites:**

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **≥ 3.44.0** (ships Dart ≥ 3.12.0)
- [Rust toolchain](https://rustup.rs/) — required for the `lfs_core` / `lfs_frb` workspace under `rust/` (security + transport core)
- **GNU `make`** — every documented build / test / lint command in this repo runs through `make`. Pre-installed on Linux + macOS; Windows hosts get it through MSYS2 (`pacman -S make`), Git Bash (already bundled with `make.exe`), or `choco install make` / `winget install GnuWin32.Make`. Direct `flutter` / `cargo` invocations work but skip the cross-language gates `make` orchestrates.
- Platform-specific toolchain (see below)

The encrypted-DB engine (SQLCipher 4.x) is bundled inside the
`rusqlite` crate via its `bundled-sqlcipher-vendored-openssl`
Cargo feature — both SQLCipher AND the OpenSSL it needs are
statically vendored, so no system OpenSSL is required on any
target. No git submodule, no native build hook, no prebuilt
download. A fresh clone is enough; `cargo build` compiles
SQLCipher + OpenSSL in-tree along with the rest of the Rust
workspace. The first build pays ~40s extra for the OpenSSL
source compile; subsequent builds reuse the cached `target/`.

```bash
git clone https://github.com/Llloooggg/LetsFLUTssh.git
```

### Linux (Debian/Ubuntu)

```bash
# System dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev lld

# If using LLVM-based clang (e.g. clang-19), install matching lld:
sudo apt-get install lld-19

# Clone, install deps, build
git clone --recurse-submodules https://github.com/Llloooggg/LetsFLUTssh.git
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

git clone --recurse-submodules https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
flutter pub get
flutter build windows --release
```

Build output: `build\windows\x64\runner\Release\`

### macOS

Requires Xcode command line tools.

```bash
xcode-select --install

git clone --recurse-submodules https://github.com/Llloooggg/LetsFLUTssh.git
cd LetsFLUTssh
make deps
make build-macos
```

Build output: `build/macos/Build/Products/Release/`

### Android

Requires Android SDK (via Android Studio or standalone SDK).

```bash
make build-apk    # APK (per-ABI: arm64, arm32, x64)
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

### Rust core (security/transport)

The SSH/crypto/persistence core lives in the Rust workspace at `rust/`. End-users install nothing — the native blob is bundled per platform alongside the Flutter binary. Contributors building from source need the Rust toolchain; the Flutter build invokes `cargokit` automatically, so any edit under `rust/` is picked up by the next `make run` / `make build-*`.

See [`ARCHITECTURE.md` §3.14](ARCHITECTURE.md#314-rust-securitytransport-core-rust) for the workspace layout, FRB boundary, and dependency invariant.

**Install Rust toolchain** (once per machine):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

`rust/rust-toolchain.toml` pins the channel — rustup auto-fetches the right version on first `cargo` invocation.

**Install FRB codegen CLI** (once per machine, version-locked to the runtime crate):

```bash
cargo install flutter_rust_bridge_codegen --version 2.12.0
```

**Rust-only targets:**

```bash
make rust-build          # cargo build --release --workspace --locked
make rust-test           # cargo test --workspace (unit + integration + doc), --locked
make rust-format         # cargo fmt --all
make rust-lint           # cargo clippy -D warnings (host + Android + Windows-GNU; Apple targets on macOS hosts)
make rust-lint-host      # host-only clippy for fast iteration when only host-target code changed
make rust-codegen        # regenerate Dart bindings after editing rust/crates/lfs_frb/src/api/*.rs
make rust-machete        # detect unused dependencies (requires `make setup-rust-tools`)
make rust-coverage       # cargo llvm-cov → rust-lcov.info (SonarCloud feed)
make rust-clean          # cargo clean
```

After editing any FFI-facing function under `rust/crates/lfs_frb/src/api/`, run `make rust-codegen` and stage the regenerated `lib/src/rust/` alongside the Rust change.

**Cross-target lint — what the umbrella covers.**

Host-only clippy sees nothing inside `#[cfg(target_os = "android")]` / `#[cfg(target_os = "windows")]` / `#[cfg(any(target_os = "macos", target_os = "ios"))]` blocks — the FFI shims under `lfs_os_security::android::*` (AndroidKeyStore), `lfs_os_security::windows::*` (CNG / Credential Manager / WebAuthn), `apple_se_ssh` (Secure Enclave), `fido2_broker::platform_impl` (Apple WebAuthN), etc. compile to nothing on the host run. To stop lint regressions in those modules slipping past local commits, `make rust-lint` runs every cross-target whose stdlib ships with `rustup` automatically:

```
make rust-lint
├── rust-lint-host         (cargo clippy --workspace, host target)
├── rust-lint-android      (cargo clippy -p lfs_os_security, aarch64-linux-android)
├── rust-lint-windows-gnu  (cargo clippy -p lfs_os_security, x86_64-pc-windows-gnu)
└── on macOS hosts only:
    ├── rust-lint-ios       (aarch64-apple-ios)
    └── rust-lint-macos-arm (aarch64-apple-darwin)
```

Why the macOS-only branch: rustup ships hosted stdlibs for Android and Windows-GNU on every host, so clippy can type-check the cfg-gated bodies without an SDK. Apple `std` / `core` is only distributed for macOS hosts; on Linux / Windows the link step would fail (rustc short-circuits before link so the type-check still runs — but only when the stdlib is installable in the first place).

Install the cross-targets once per machine:

```bash
# every host
rustup target add aarch64-linux-android x86_64-pc-windows-gnu

# macOS hosts only
rustup target add aarch64-apple-ios aarch64-apple-darwin
```

Per-target Makefile entry points stay available for fast ad-hoc iteration when touching one specific module:

```bash
make rust-lint-android      # cargo clippy -p lfs_os_security --target aarch64-linux-android
make rust-lint-windows-gnu  # cargo clippy -p lfs_os_security --target x86_64-pc-windows-gnu
make rust-lint-ios          # cargo clippy -p lfs_os_security --target aarch64-apple-ios
make rust-lint-macos-arm    # cargo clippy -p lfs_os_security --target aarch64-apple-darwin
```

CI runs the full cross-target matrix (including the Apple-native runner) on every PR that touches `rust/**`, but the local gate now catches the Android + Windows classes before push.

**Optional hardware-backed integration tests.**

A handful of Rust integration tests reach real OS-level cryptographic services (SoftHSM v2 for PKCS#11, `swtpm` for the Linux TPM 2.0 SSH path, BiometricPrompt for Android Hardware Keystore, etc.). They are all `#[ignore]`-gated so the default `make rust-test` does not require any of these dependencies — only the hardware-bound modules' own unit-test slices run by default.

When you want to exercise the full PKCS#11 round-trip against a real Cryptoki implementation, install SoftHSM v2 once per machine:

```bash
# Debian / Ubuntu
sudo apt-get install -y softhsm2

# macOS
brew install softhsm
```

Then provision a per-user tokenstore so the integration test never touches `/var/lib/softhsm/` (system-wide state owned by the `softhsm` group):

```bash
mkdir -p ~/.softhsm/tokens
cat > ~/.softhsm/softhsm2.conf <<'EOF'
directories.tokendir = ~/.softhsm/tokens
objectstore.backend = file
log.level = ERROR
EOF
SOFTHSM2_CONF=~/.softhsm/softhsm2.conf \
  softhsm2-util --init-token --slot 0 --label "Test Token" --pin 1234 --so-pin 4321
```

Run the gated tests via the dedicated Makefile target:

```bash
SOFTHSM2_CONF=~/.softhsm/softhsm2.conf make rust-test-pkcs11
```

The target re-runs only the SoftHSM-gated tests; it never touches `make rust-test`'s default surface, so a missing SoftHSM never blocks the umbrella suite.

**Building with an Apple Developer Program account (macOS / iOS).**

Two app surfaces ship Apple-only entitlements that the OS activates only when the bundle is signed by a member of the Apple Developer Program:

| Surface | Source files | Entitlement | What unlocks |
|---|---|---|---|
| Secure Enclave SSH keys (T-5) | `lfs_os_security::apple_se_ssh` | `keychain-access-groups = $(TeamIdentifierPrefix)com.poddeo3.letsflutssh` (only required once `app-sandbox` flips to `true`; today the macOS bundle runs unsandboxed and reaches the user-default keychain without the entitlement) | `SecKeyCreateRandomKey(kSecAttrTokenIDSecureEnclave, …)` stops returning `errSecMissingEntitlement (-34018)` on a sandboxed build |
| System FIDO2 broker (T-8) | `lfs_os_security::fido2_broker::apple` + `macos/Runner/SecurityKeyBroker.swift` + `ios/Runner/SecurityKeyBroker.swift` | `com.apple.developer.web-browser.public-key-credential = true` | `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` fires the system security-key dialog for `sk-*` SSH userauth |

Self-build users without a paid Developer Program account fall back gracefully:

- macOS Secure Enclave: the `codesign -s - --identifier com.poddeo3.letsflutssh --entitlements macos/Runner/Release.entitlements ...` snippet in `docs/USER_GUIDE.md` ad-hoc-signs the bundle. Ad-hoc with a stable identifier clears `-34018` in practice; the keychain bind works for the running install but cannot move to another Mac.
- macOS FIDO2 broker: the entitlement is ignored on ad-hoc-signed builds; the dispatcher in `lfs_core::fido2::brokers` automatically falls through to direct USB HID (`ctap-hid-fido2`) — the broker label hides itself in `Settings → Hardware security keys` and the direct-HID path becomes the only one.
- iOS Secure Enclave + FIDO2 broker: both paths require a real signed build. Ad-hoc / personal-team builds give the entitlement but the App Store / TestFlight install gate is what activates it.

**Build steps when you have an Apple Developer Program membership:**

1. Add your Apple ID under Xcode → Settings → Accounts. Pull "Manage Certificates…" → "+" → "Apple Distribution".
2. In Xcode, open `macos/Runner.xcodeproj` (or `ios/Runner.xcodeproj`). Select the `Runner` target → Signing & Capabilities tab:
   - Team: pick your Developer Program team (the `$(TeamIdentifierPrefix)` placeholder in `Release.entitlements` resolves automatically).
   - Provisioning Profile: leave on "Automatically manage signing".
   - Capabilities: add **Apple WebAuthn** (this surfaces the `com.apple.developer.web-browser.public-key-credential` entitlement). On macOS also confirm **App Sandbox** is OFF and **Hardened Runtime** is ON for Release; the `Release.entitlements` file already lists `com.apple.security.network.client/server` so SSH local / remote port forwards keep working after Hardened Runtime activates.
3. Replace the `com.poddeo3.letsflutssh` bundle identifier with one you own (`com.<your-domain>.letsflutssh`) in:
   - `macos/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`)
   - `ios/Runner.xcodeproj/project.pbxproj` (same key)
   - `macos/Runner/Release.entitlements` (the inline `$(TeamIdentifierPrefix)com.poddeo3.letsflutssh` comment block)
   - any matching references in `lfs_os_security::apple_se_ssh` (today the `letsflutssh.ssh.<uuid>` `kSecAttrApplicationTag` prefix is opaque — no rename needed).
4. Build:
   ```bash
   # macOS
   flutter build macos --release
   open build/macos/Build/Products/Release/

   # iOS — runs through Xcode's signing pipeline
   flutter build ipa --release
   # then Xcode → Window → Organizer → Distribute App
   ```
5. Verify the entitlement actually attached:
   ```bash
   codesign -d --entitlements - build/macos/Build/Products/Release/LetsFLUTssh.app
   # Look for `com.apple.developer.web-browser.public-key-credential` in the output.
   ```

If your CI signs the build outside Xcode, the `xcodebuild -exportArchive` step picks up the team ID from your `ExportOptions.plist` — set `signingStyle = automatic` + `teamID = <your team ID>` and the entitlements file is wired automatically.

> The two Swift glue files (`macos/Runner/SecurityKeyBroker.swift` + `ios/Runner/SecurityKeyBroker.swift`) ship in the repo and need to be added to the Xcode target's "Compile Sources" build phase once per fork. Newer Xcode versions auto-detect Swift files under `Runner/`; older versions need the manual drag-and-drop. The repo's `dev/scripts/setup-xcode-broker.sh` automates this for both targets — run once after cloning if Xcode hasn't already picked the files up.

## Development

Top-level umbrella targets run both Dart and Rust. Per-language
specifics use the `dart-*` / `rust-*` prefix when only one side is
in scope.

```bash
make setup          # One-time post-clone bootstrap: pub deps + git hooks + cargo plugins
make hooks          # Install git hooks (pre-commit: check-static; pre-push: check-static; commit-msg: lint + plan-id; post-commit: target GC)
make run            # Run in debug mode
make test           # Run all tests (Dart + Rust)
make lint           # Static analysis (Dart analyzer + Rust clippy)
make format         # Auto-format Dart + Rust sources
make format-check   # Verify formatting without rewriting files
make check-static   # Static gate without tests (format + lint + workflow/hardening lint + unused-deps)
make check          # Full gate: check-static + the test suite
make gen            # Code generation (l10n, FRB bridge)
make clean          # Remove build artifacts
make help           # Show all available targets
```

Need only one side?

```bash
make dart-test           # Dart tests only (requires rust-build for FRB-loaded tests)
make dart-lint           # Dart analyzer only
make dart-format         # Format Dart only
make dart-format-check   # Verify Dart formatting
```

> **First clone:** run `make setup` once. It installs pub deps, git
> hooks, and pinned cargo plugins (`cargo-machete`, `cargo-llvm-cov`)
> used by `make check` / `make rust-coverage`.
>
> The hooks split the gate across the commit/push lifecycle so day-to-day
> commits stay fast, while CI re-runs everything as the real enforcement
> boundary (local hooks are opt-in and bypassable, so they never stand
> alone for a load-bearing rule):
>
> - **pre-commit** runs `make check-static` — format, lint, workflow and
>   release-hardening lint, unused-deps; no tests. Skipped for doc-only
>   staged diffs. Bypass with `SKIP_PRECOMMIT=1`.
> - **pre-push** runs `make check-static` as a local backstop — it
>   catches a format / lint slip from an amend or a `SKIP_PRECOMMIT`
>   commit before it burns a CI round. The test suite is **not** run
>   locally: it is slow and redundant with CI, which runs the full
>   suite on every PR to `main` / `dev` (the real gate before a
>   release-bearing merge). Bypass with `SKIP_PREPUSH=1`.
> - **commit-msg** checks the conventional-commit subject format on every
>   commit (the same `dev/scripts/conventional-commit-check.sh` that CI's
>   `commit-lint` job runs, so the two can't drift) and runs the agent
>   plan-ID gate on agent commits.
>
> A `post-commit` hook keeps the Rust build cache from growing
> unbounded. cargo never garbage-collects `rust/target`, and
> flutter_rust_bridge codegen and `cargo-mutants` each spawn many
> distinct builds whose artifacts accumulate there. After each commit
> it measures `rust/target` in the background and, if it exceeds
> `CARGO_TARGET_MAX_GB` (default 35, room for ~2 builds), runs
> `make rust-sweep` — `cargo sweep --maxsize` drops the **oldest**
> artifacts until the directory is back under the cap, leaving the hot
> cache intact (a single build is already ~16G, so a full `cargo clean`
> would force a cold rebuild). It never blocks or fails the commit;
> output goes to `.git/target-gc.log`. Needs `cargo-sweep` (installed by
> `make setup-rust-tools`); if it is missing the hook logs and skips
> rather than wiping. Tune with `export CARGO_TARGET_MAX_GB=50` or skip
> a single commit's check with `SKIP_TARGET_GC=1`.

**New contributors:** start with [ADDING_A_FEATURE.md](ADDING_A_FEATURE.md) — a hands-on walkthrough of the project's layers, conventions, and tooling using a small example feature.

For detailed technical documentation see [ARCHITECTURE.md](ARCHITECTURE.md) — module structure, data models, API references, state management, data flows, and design decisions.

### Local test backends (S3 / WebDAV / SSH)

For manual QA of the `lfs_core::{s3, webdav, ssh, sftp}` transports against real servers without renting cloud accounts, the repo ships a Docker Compose stack under [`dev/compose/`](../dev/compose/README.md). It brings up MinIO, Apache mod_dav with Basic and Digest auth, a Nextcloud (for Bearer tokens), and `linuxserver/openssh-server`, all bound to `127.0.0.1` with hard-coded dev credentials. See `dev/compose/README.md` for endpoint URLs and the per-session settings to plug into the app.

## Coding Conventions

- **Reuse first** — before adding a new widget, helper, mixin, style constant, or store, search `lib/widgets/`, `lib/theme/`, and `lib/core/**` for an existing equivalent and extend it (add a parameter) instead of forking. Full rule and canonical primitives: [§1 Reuse principle](ARCHITECTURE.md#reuse-principle)
- **End-user runs zero manual setup** — never introduce a feature that hard-requires the user to install something themselves. If a feature needs an OS capability, prefer (1) bundling it with the app (e.g. `sqlite3` via build hooks, native QR scanner), then (2) a built-in fallback (e.g. master password if no keychain), and only as a last resort (3) an *optional* OS dep with graceful degradation in-UI + a README install snippet per platform. Full rule: [§1 Self-contained-binary principle](ARCHITECTURE.md#self-contained-binary-principle)
- **Logging** — `AppLogger.instance.log(message, name: 'Tag')`, never `print()`/`debugPrint()`/`dart:developer` directly. Every message is auto-sanitized (PEM keys, IPv4/IPv6, `user@host`, `host:port`, Unix/Windows home paths are redacted); free-form user labels (session names, key labels, tag titles) the regex cannot catch — log the marker `<label>` not the value. Err on more logs not fewer — the file sink is opt-in off by default, so generous logging at every disk/DB/network/subprocess/native-plugin boundary and every caught-and-continued `try/catch` branch costs nothing for users who never opt in, and pays off for the ones who do. Crash paths use `AppLogger.instance.logCritical(...)` which bypasses the opt-out gate — [§17 Error Handling → Logging conventions](ARCHITECTURE.md#logging-conventions-when-to-log-what-to-write)
- **State** — shared / app-wide state via Riverpod providers (no global mutable state). Widget-local state (dialog / pane / panel) via `ChangeNotifier` + `AnimatedBuilder` — see `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`. Use `.select()` on broad Riverpod providers to avoid unnecessary rebuilds — [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod)
- **Models** — immutable with `copyWith`, `==`, `hashCode`, `toJson`/`fromJson` — [§10 Data Models](ARCHITECTURE.md#10-data-models)
- **Theme** — OneDark, semantic color constants, no hardcoded `Colors` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Font sizes** — use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (platform-aware), never hardcode `fontSize` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Border radius** — use `AppTheme.radiusSm`/`radiusMd`/`radiusLg`, never hardcode `BorderRadius.circular(N)` — [§8 Theme](ARCHITECTURE.md#8-theme-system)
- **Buttons** — `AppIconButton` for icon buttons, `HoverRegion` for custom hover. Never use bare `IconButton` or `InkWell` — [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference)
- **Security** — four-tier model (T0 plaintext / T1 keychain / T2 hardware / Paranoid Argon2id) + orthogonal modifiers (master-password, biometric). All cryptography lives in Rust (`lfs_core::crypto` — RustCrypto family); OS keychains reached directly per platform via `lfs_os_security::secure_key_storage` (no third-party plugin in the call chain). Linux libsecret backend needs `libsecret-1-dev` at build time; Linux native TPM2 backend needs `libtss2-dev`. — [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity)
- **Testing** — one test file per source file, DI hooks for testability — [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks)

## Commit Messages

Format: `type: short description`

| Prefix      | Use for                         | Appears in release notes? |
|-------------|---------------------------------|---------------------------|
| `feat:`     | New features                    | Yes — under **Features**  |
| `fix:`      | Bug fixes                       | Yes — under **Fixes**     |
| `refactor:` | Code improvements (no new behavior) | Yes — under **Improvements** |
| `perf:`     | Performance improvements        | Yes — under **Improvements** |
| `security:` | Hardening / vulnerability fix   | Yes — pinned **Security** callout at top of notes |
| `i18n:`     | Translation / l10n string changes | Yes — under **Localization** |
| `l10n:`     | Locale data / non-string l10n   | Yes — under **Localization** |
| `revert:`   | Revert a previous commit        | Yes — under **Reverts**   |
| `chore(deps):` | Dependency updates (auto-generated) | Yes — under **Dependencies** |
| `build:`    | Build system, dependencies      | No                        |
| `test:`     | Test changes only               | No                        |
| `docs:`     | Documentation only              | No                        |
| `chore:`    | Config, tooling                 | No                        |
| `ci:`       | CI/CD workflow changes          | No                        |
| `style:`    | Formatting, whitespace          | No                        |

**Append `!` after the type or scope to mark a breaking change** (e.g. `feat(api)!: drop legacy session format`) — the entry renders with a leading **BREAKING** badge and also triggers a major version bump.

Ordering in release notes: Security (pinned callout) → Features → Reverts → Improvements → Fixes → Localization → Dependencies. Empty sections are omitted.

**Prefer a scope in parentheses** when the change is localized to one module (e.g. `feat(snippets):`, `fix(import):`, `test(known-hosts):`, `fix(session_manager):`, `refactor(keys+tags):`, `fix(dev/scripts/macos-resign):`) — lowercase, alphanumeric plus `_ + - /`. Drop the scope only when the change is genuinely cross-cutting and no single module name fits (e.g. plain `docs:`, `chore:`, `ci:`).

**Examples:**

```
feat(port-forward): add port forwarding support
fix(sftp): handle SSH disconnect during file transfer
refactor(dialogs): extract shared dialog logic into ConfirmDialog widget
test(credentials): add tests for credential store encryption
docs: update README with mobile screenshots
chore: upgrade russh to 0.59.0
ci: add commit message linting for PRs
```

**Important:**

- Commit messages are **auto-generated into release notes** — keep them clear and user-readable.
- Start with a lowercase verb — no period at the end.
- If a commit includes both app changes and docs, the prefix describes the **app change** (docs ride along).
- CI validates commit message format on pull requests — commits that don't match the pattern will fail the check.

## Version Bumps

Version bumps are **fully automated**. The bump script (`dev/scripts/bump-version.sh`) parses conventional commit prefixes since the last tag and bumps `pubspec.yaml`. It runs on `dev` before creating a PR to `main`; for Dependabot PRs, CI runs it automatically.

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
5. `make check` must pass (covers `make lint` + `make test` for both Dart and Rust, plus workflow lint + release hardening + unused-deps)
6. All new code must have tests (80% coverage minimum, 100% target)
7. One logical change per PR
8. Open a Pull Request — fill in the template

All checks must pass before merge: CI (`make check` + Rust cross-target compile), OSV-Scanner, Semgrep, and CodeQL.

## CI/CD Pipeline

Every push and PR is checked by multiple pipelines. For the full workflow graph and detailed descriptions see [§15 CI/CD Pipeline](ARCHITECTURE.md#15-cicd-pipeline).

| Workflow | Purpose | Required on PR? |
|----------|---------|-----------------|
| `ci.yml` | Analyze, test, coverage, commit-lint, dependency review (Dart + Rust under one `make check`) | Yes |
| `ci-sonarcloud.yml` | Code quality + coverage feed (after `ci.yml` succeeds) | No (fork PRs have no token) |
| `osv.yml` | Dependency CVE scanning (`pubspec.lock` + `Cargo.lock`) | Yes |
| `semgrep.yml` | SAST scan — static security analysis of Dart code | Yes |
| `codeql.yml` | GitHub Actions security analysis | Yes |
| `scorecard.yml` | OpenSSF supply chain assessment | No (main + weekly only) |
| `cfl-fuzz.yml` | ClusterFuzzLite — coverage-guided fuzzing for Dart standalone harnesses (300 s per target) | No (push main + PRs to main only) |
| `ci-auto-tag.yml` | Reads `pubspec.yaml`, creates a fresh `vX.Y.Z` tag when CI passes on `main` | — (post-merge automation) |
| `dependabot-auto.yml` | Bumps version on a Dependabot PR's branch then auto-merges patch / minor updates | — (PR automation) |
| `build-release.yml` | Build all platforms + sign manifest + GitHub Release (on tag) | — |
| `reproducibility-check.yml` | Nightly cron: builds the Linux artefacts twice on the same SHA + diffs sha256 to verify the `SOURCE_DATE_EPOCH`-pinned reproducibility claim | No |
| `pages.yml` | Publishes the project landing site to GitHub Pages | No (main only) |

**Dependabot auto-releases:** when Dependabot opens a Dart dependency update PR (`pub` ecosystem), `dependabot-auto.yml` runs `dev/scripts/bump-version.sh` in the PR branch to bump the patch version, then auto-merges. CI runs on `main` after merge; if it passes, `ci-auto-tag.yml` creates a tag and triggers the full build + release pipeline. If CI fails — no tag, no release. GitHub Actions updates are auto-merged but do not trigger a version bump (they don't affect the shipped app).

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.
