import '../../src/rust/api/migration.dart' as rust_migration;

export '../../src/rust/api/migration.dart'
    show DbMigrationReport, DbMigrationStep, DbUnsupportedFutureVersion;

/// Convenience helpers on top of the FRB-generated
/// [rust_migration.DbMigrationReport]. Mirrors the Rust-side
/// `Report::no_op` / `has_failures` / `migrated_count` predicates
/// so the post-run UI flow does not re-walk the report fields by
/// hand on every call site.
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

/// Run the startup migration framework Rust-side against the pinned
/// app-support directory (pinned at `config_store_init`). Idempotent —
/// running twice in a row on a healthy install returns a no-op
/// [rust_migration.DbMigrationReport].
Future<rust_migration.DbMigrationReport> runStartupMigrations() async {
  return rust_migration.migrationRunOnStartup();
}
