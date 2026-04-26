//! FRB adapter for `lfs_core::migration`.
//!
//! Surfaces a single endpoint — [`migration_run_on_startup`] — that
//! Dart calls once during boot, before the security-init / unlock
//! path opens any artefact. Returns a flat [`DbMigrationReport`] with
//! every detail the Dart caller needs to render its log line + decide
//! whether to route through the corrupt-data dialog.
//!
//! The runner itself + the artefact registry live entirely in
//! `lfs_core::migration` — this adapter just marshals types over FRB.

/// FRB mirror of [`lfs_core::migration::Step`].
pub struct DbMigrationStep {
    pub artefact_id: String,
    pub from_version: i32,
    pub to_version: i32,
    pub succeeded: bool,
    pub error: Option<String>,
}

/// FRB mirror of [`lfs_core::migration::UnsupportedFutureVersion`].
pub struct DbUnsupportedFutureVersion {
    pub artefact_id: String,
    pub on_disk_version: i32,
    pub known_target_version: i32,
}

/// FRB mirror of [`lfs_core::migration::Report`].
pub struct DbMigrationReport {
    pub steps: Vec<DbMigrationStep>,
    pub future_versions: Vec<DbUnsupportedFutureVersion>,
    pub fatal_error: Option<String>,
}

/// Read the on-disk `config.json` schema version. Returns `-1`
/// when the file is absent. Returns `Err` when the file is present
/// but corrupt (missing `config_schema_version`, malformed JSON,
/// etc.) — Dart caller surfaces the failure as a fatal startup
/// error. Used by the legacy-state probe in
/// `SecurityInitController` to detect a config below the current
/// schema floor *after* the migration runner has already walked
/// every chain it knows about.
pub fn migration_config_version_on_disk(support_dir: String) -> Result<i32, String> {
    use lfs_core::migration::artefacts::ConfigArtefact;
    use lfs_core::migration::Artefact;
    ConfigArtefact.read_version(std::path::Path::new(&support_dir))
}

/// Run every registered artefact's migration chain against the
/// app-support directory at `support_dir`. Idempotent — running
/// twice in a row on a healthy install returns a no-op
/// [`DbMigrationReport`]. The Dart caller surfaces any non-no-op
/// failure via the corrupt-data dialog and refuses to start the
/// unlock flow.
pub fn migration_run_on_startup(support_dir: String) -> DbMigrationReport {
    let registry = lfs_core::migration::build_app_registry();
    let report = lfs_core::migration::run_on_startup(std::path::Path::new(&support_dir), &registry);
    DbMigrationReport {
        steps: report
            .steps
            .into_iter()
            .map(|s| DbMigrationStep {
                artefact_id: s.artefact_id,
                from_version: s.from_version,
                to_version: s.to_version,
                succeeded: s.succeeded,
                error: s.error,
            })
            .collect(),
        future_versions: report
            .future_versions
            .into_iter()
            .map(|f| DbUnsupportedFutureVersion {
                artefact_id: f.artefact_id,
                on_disk_version: f.on_disk_version,
                known_target_version: f.known_target_version,
            })
            .collect(),
        fatal_error: report.fatal_error,
    }
}
