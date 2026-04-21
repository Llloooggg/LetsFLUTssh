import 'migration.dart';

/// Registry for `.lfs` archive-format migrations.
///
/// The archive lives inside a user-supplied `.zip` container and is
/// opened per-import (not at app startup), so it has a different
/// lifecycle from the on-disk `MigrationRegistry`. Both share the
/// `Migration` interface so future archive format bumps read like any
/// other migration.
///
/// v1 is the permanent floor; no migrations are registered today — every
/// supported archive is at v1 by definition. Archives whose
/// `schema_version` does not match the current [SchemaVersions.archive]
/// (missing manifest, older, or newer) are rejected with
/// `UnsupportedLfsVersionException` inside
/// `ExportImport._decryptWithPassword` / `_parseManifest`.
///
/// When bumping archive schema_version to 2:
/// 1. Add a new `Migration` subclass in `lib/core/migration/migrations/
///    archive_v1_to_v2.dart` that rewrites archive contents in memory
///    (add a field, rename a key, adjust structure).
/// 2. Register it here via `archiveMigrationRegistry.register(...)`.
/// 3. Bump `SchemaVersions.archive` to 2.
/// 4. The import path walks this list and applies matching migrations
///    before entries are parsed.
class ArchiveMigrationRegistry {
  ArchiveMigrationRegistry({List<Migration>? migrations})
    : _migrations = [...?migrations];

  final List<Migration> _migrations;

  List<Migration> get migrations => List.unmodifiable(_migrations);

  void register(Migration migration) {
    final dup = _migrations.any((m) => m.fromVersion == migration.fromVersion);
    if (dup) {
      throw StateError(
        'Duplicate archive migration from ${migration.fromVersion}',
      );
    }
    _migrations.add(migration);
  }

  /// Return the chain of migrations needed to walk [fromVersion] →
  /// [toVersion]. Empty list = already at target. Throws
  /// `StateError` when a step is missing — caller surfaces it as a
  /// user-facing error so data is not silently corrupted.
  List<Migration> chain(int fromVersion, int toVersion) {
    final out = <Migration>[];
    var cursor = fromVersion;
    while (cursor < toVersion) {
      final step = _migrations.firstWhere(
        (m) => m.fromVersion == cursor,
        orElse: () => throw StateError(
          'No archive migration from $cursor (target=$toVersion)',
        ),
      );
      out.add(step);
      cursor = step.toVersion;
    }
    return out;
  }
}

/// Singleton registry for archive format migrations. Empty today
/// (v1 is the baseline); future migrations register here.
final ArchiveMigrationRegistry archiveMigrationRegistry =
    ArchiveMigrationRegistry();
