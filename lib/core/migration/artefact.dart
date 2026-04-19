/// A single migrate-able piece of on-disk state.
///
/// Implementations are thin wrappers around an existing storage class
/// (config store, vault file, KDF params, …). The migration runner
/// uses them only to discover the artefact's current version on disk;
/// all read/write of the actual payload happens inside concrete
/// [Migration] subclasses.
///
/// `targetVersion` is the value the runner is trying to reach for
/// this artefact (read from `SchemaVersions`). The plan of migrations
/// is computed as the chain whose `fromVersion`/`toVersion` pairs walk
/// from `readVersion()` up to `targetVersion`.
abstract class Artefact {
  /// Stable string id used in the migration history log + error
  /// messages. Use the same name as the file under app-support
  /// (e.g. `'config.json'`, `'hardware_vault_linux.bin'`).
  String get id;

  /// Canonical target version for this artefact in the current build.
  /// Read straight from a `SchemaVersions` constant — never inline a
  /// number here so the constant stays the single source of truth.
  int get targetVersion;

  /// Inspect the on-disk state and return its current version.
  ///
  /// Conventions:
  /// - `-1` → artefact does not exist on disk yet (clean install for
  ///   this artefact). Runner skips migrations for it.
  /// - `0` → artefact present but unversioned (legacy format from
  ///   before the framework existed). Runner will look for a
  ///   `v0_to_v1` migration.
  /// - `>=1` → artefact present, header-versioned. Runner looks for
  ///   the next-step migration.
  Future<int> readVersion();
}
