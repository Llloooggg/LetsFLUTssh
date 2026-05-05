import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/migration.dart' as rust_migration;

export '../../src/rust/api/migration.dart'
    show DbMigrationReport, DbMigrationStep, DbUnsupportedFutureVersion;

/// Convenience helpers on top of the FRB-generated
/// [rust_migration.DbMigrationReport] so callers read the shape they
/// used to read on the old Dart-side `MigrationReport`. Mirrors the
/// Rust-side `Report::no_op` / `has_failures` / `migrated_count`.
extension DbMigrationReportHelpers on rust_migration.DbMigrationReport {
  /// True when the runner is entirely satisfied — every artefact is
  /// already at its target version, nothing was migrated, no errors.
  bool get noOp =>
      steps.isEmpty && futureVersions.isEmpty && fatalError == null;

  /// True when the runner encountered any kind of failure — fatal
  /// throw, a future-version artefact, or a non-succeeded step.
  bool get hasFailures =>
      fatalError != null ||
      futureVersions.isNotEmpty ||
      steps.any((s) => !s.succeeded);

  /// Count of successful migrations; useful for the post-run toast.
  int get migratedCount => steps.where((s) => s.succeeded).length;
}

/// Run the startup migration framework Rust-side. Resolves the
/// platform's app-support directory through `path_provider` and hands
/// the path off to `lfs_core::migration::run_on_startup`. Idempotent —
/// running twice in a row on a healthy install returns a no-op
/// [rust_migration.DbMigrationReport].
Future<rust_migration.DbMigrationReport> runStartupMigrations() async {
  final dir = await getApplicationSupportDirectory();
  return rust_migration.migrationRunOnStartup(supportDir: dir.path);
}

/// Target version this build supports for `config.json`. Reads
/// `lfs_core::migration::SchemaVersions::CONFIG` through FRB so the
/// constant lives one place across the workspace.
int currentConfigSchemaVersion() =>
    rust_migration.migrationConfigTargetVersion();

/// Read the `config.json` schema version from disk. Returns `-1`
/// when the file is absent. Throws [Exception] when the file is
/// present but corrupt — the caller surfaces the failure as a fatal
/// startup error.
Future<int> readConfigSchemaVersion() async {
  final dir = await getApplicationSupportDirectory();
  return rust_migration.migrationConfigVersionOnDisk(supportDir: dir.path);
}
