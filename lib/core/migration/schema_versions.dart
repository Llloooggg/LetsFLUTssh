/// Canonical current version for every migrate-able artefact.
///
/// Single source of truth for "what version should this artefact be
/// after we are fully up to date". The migration runner compares
/// each artefact's on-disk version against the constant here and runs
/// the chain of migrations needed to reach it.
///
/// **Rules:**
/// - Bump only when shipping a new [Migration] that targets the new
///   version. CI guard rejects a bump without a matching migration
///   registered in `registry.dart`.
/// - Never reuse a previous version number. Versions are monotonic.
/// - Version 0 = "unversioned legacy" (no envelope header). The
///   v0_to_v1 migration for an artefact reads the legacy structure
///   and rewrites it under [VersionedBlob] envelope.
///
/// Initial state (Phase A1): all binary artefacts at version 0
/// (legacy). Drift DB and KDF stay at their existing internal
/// versions — they already track schema themselves.
class SchemaVersions {
  /// `config.json` payload format. v1 = post-3-tier collapse
  /// (drops `keychainWithPassword`, folds into modifiers).
  /// Bumped to 2 in Phase G when the v1→v2 migration lands.
  static const int config = 1;

  /// `credentials.kdf` (Argon2id params). Already self-versioned via
  /// `KdfParams` magic; tracked here so the migration framework knows
  /// it exists and can route future format bumps through itself.
  static const int kdf = 1;

  /// Drift DB schema. Already migrated via Drift's `MigrationStrategy`;
  /// tracked here so the framework reports its presence.
  static const int db = 2;

  /// `security_pass_hash.bin` — keychain password gate. Phase A1: still
  /// raw JSON (version 0). Phase G migration bumps to 1 (envelope).
  static const int passGate = 0;

  /// `hardware_vault_*.bin` — per-platform hw vault blob. Phase A1:
  /// legacy formats (version 0). Phase D/J migrations bump to 1.
  static const int hwVaultAndroid = 0;
  static const int hwVaultApple = 0;
  static const int hwVaultWindows = 0;
  static const int hwVaultLinux = 0;

  /// `hardware_vault_salt.bin` — raw 32-byte salt. Phase A1: legacy
  /// (version 0). Phase D migration wraps in envelope (version 1).
  static const int hwSalt = 0;

  /// `.lfs` archive schema carried in `manifest.json`. Phase A3 drops
  /// pre-v1 back-compat (legacy headerless PBKDF2, v2 PBKDF2 header,
  /// missing manifest) and establishes v1 as the permanent floor —
  /// future breaking format changes ship a proper archive-side
  /// `Migration` registered in `archive_registry.dart`.
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
