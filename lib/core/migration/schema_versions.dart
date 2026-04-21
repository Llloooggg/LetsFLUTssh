/// Canonical current version for every migrate-able artefact.
///
/// Single source of truth for "what version should this artefact be
/// after we are fully up to date". The migration runner compares
/// each artefact's on-disk version against the constant here and runs
/// the chain of migrations needed to reach it.
///
/// **Rules:**
/// - v1 is the permanent floor. Any on-disk state reporting a version
///   below 1 (pre-framework legacy layouts, unrecognised formats) is
///   treated as corrupt and routed through the reset path — never
///   migrated.
/// - Bump only when shipping a new [Migration] that targets the new
///   version. A bump without the matching migration registered in
///   `registry.dart` is caught by the registry-completeness unit test.
/// - Never reuse a previous version number. Versions are monotonic.
class SchemaVersions {
  /// `config.json` payload format. `config_schema_version` is stamped
  /// by `ConfigStore.save` on every write; a missing / mismatched field
  /// on read = corrupt.
  static const int config = 1;

  /// `credentials.kdf` (Argon2id params + salt). Self-versioned inside
  /// the file via `'LFKD'` magic + version byte; tracked here so the
  /// framework can route future format bumps through itself.
  static const int kdf = 1;

  /// Drift DB schema. Migrated intra-DB via drift's `MigrationStrategy`;
  /// presence-only in the framework.
  static const int db = 1;

  /// `security_pass_hash.bin` — keychain password gate.
  static const int passGate = 1;

  /// `hardware_vault_*.bin` — per-platform hw vault blob.
  static const int hwVaultAndroid = 1;
  static const int hwVaultApple = 1;
  static const int hwVaultWindows = 1;
  static const int hwVaultLinux = 1;

  /// `hardware_vault_salt.bin` — raw 32-byte salt.
  static const int hwSalt = 1;

  /// `.lfs` archive schema carried in `manifest.json`.
  static const int archive = 1;
}

/// Stable 1-byte ids written into the [VersionedBlob] header. Never
/// reuse a value. Adding a new artefact picks the next free id.
class ArtefactIds {
  static const int passGate = 0x01;
  static const int hwVaultAndroid = 0x02;
  static const int hwVaultApple = 0x03;
  static const int hwVaultWindows = 0x04;
  static const int hwVaultLinux = 0x05;
  static const int hwSalt = 0x06;
  static const int config = 0x07;
  static const int kdf = 0x08;
  static const int db = 0x09;
  static const int archive = 0x0A;
}
