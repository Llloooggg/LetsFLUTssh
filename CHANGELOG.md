# Changelog

## Unreleased — Rust core cutover (breaking)

### Breaking

* **Database engine swap.** The encrypted SQLite store now runs on
  SQLCipher 4.x (AES-256-CBC + HMAC-SHA512), bundled in-tree via the
  `rusqlite` crate's `bundled-sqlcipher` Cargo feature. The previous
  `drift` + `SQLite3MultipleCiphers` (ChaCha20-Poly1305) stack is
  gone, along with the `third_party/SQLite3MultipleCiphers` git
  submodule and its custom `pubspec.yaml` build hooks.

  The two cipher families are wire-incompatible — a database written
  under MC cannot be opened under SQLCipher and vice versa. **Any
  install upgrading from a pre-cutover build will see an empty
  sidebar after the upgrade**: the old `letsflutssh.db` file is left
  on disk untouched but is unreachable to the new build.

  **Upgrade path:**
  1. On the *old* build, open Settings → Export and save a `.lfs`
     archive somewhere outside the app-support directory.
  2. Install the new build.
  3. On the new build, open Settings → Import and pick the saved
     `.lfs` archive — sessions, folders, SSH keys, known_hosts,
     tags, snippets and bookmarks restore from there.

  Plain-tier (T0) installs that have no security-bound data and use
  the app for ad-hoc connections only can skip the export-import
  dance — the new build creates a fresh empty DB on first launch
  with no behavioural difference.

* **Android minimum SDK is now API 28 (Android 9.0).** The hardware
  vault (T2) requires StrongBox + reliable `setInvalidatedByBiometric
  Enrollment`, both gated on API 28+. Pre-API-28 devices were
  already greyed out of the wizard but could still install the
  package; the floor is now enforced at install time via
  `android/app/build.gradle.kts::minSdk`. The `pubspec.yaml`
  `flutter_launcher_icons.min_sdk_android` is bumped to match.

### Cleanup

The Rust core port retired three packages, fourteen native plugin
files, three Dart prompt-listener classes, three Rust prompt-registry
modules, and three bus event variants — every keychain / biometric /
clipboard / session-lock / backup-exclusion / Apple+Android hardware-
vault path now lives Rust-side under `lfs_os_security`. Only Windows
L3 (CNG / Platform Crypto Provider) and Android EXTRA_IS_SENSITIVE
clipboard remain on MethodChannel by intent.

### Fixed

* `config.json` from a pre-cutover install no longer triggers a reset
  dialog. The migration framework now treats a missing
  `config_schema_version` field on a parseable JSON object as
  implicit v1 instead of corrupt.
* `bootstrap_schema()` writes `PRAGMA user_version = 1` on every
  open so future schema migrations have a real anchor to read off.
