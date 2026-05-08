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

/// Target version this build supports for `config.json`. Used by
/// the legacy-state probe in `SecurityInitController` to detect
/// configs below the current schema floor without duplicating the
/// `SchemaVersions::CONFIG` literal Dart-side.
#[flutter_rust_bridge::frb(sync)]
pub fn migration_config_target_version() -> i32 {
    lfs_core::migration::SchemaVersions::CONFIG
}

/// Target `schema_version` this build stamps into `.lfs` archive
/// manifests and accepts on import. Reads
/// `lfs_core::migration::SchemaVersions::ARCHIVE` so the constant
/// lives one place across the workspace.
#[flutter_rust_bridge::frb(sync)]
pub fn migration_archive_target_version() -> i32 {
    lfs_core::migration::SchemaVersions::ARCHIVE
}

/// Read the on-disk `config.json` schema version. Returns `-1`
/// when the file is absent. Returns `Err` when the file is present
/// but corrupt (missing `config_schema_version`, malformed JSON,
/// etc.) — Dart caller surfaces the failure as a fatal startup
/// error. Used by the legacy-state probe in
/// `SecurityInitController` to detect a config below the current
/// schema floor *after* the migration runner has already walked
/// every chain it knows about.
///
/// Async + `spawn_blocking` — the read touches the filesystem and
/// must not stall the FRB worker thread. The earlier sync shape
/// happened to work because Dart only calls this once at startup,
/// but a future test that drives the path from inside an event
/// loop would block.
pub async fn migration_config_version_on_disk(support_dir: String) -> Result<i32, String> {
    tokio::task::spawn_blocking(move || {
        use lfs_core::migration::artefacts::ConfigArtefact;
        use lfs_core::migration::Artefact;
        ConfigArtefact.read_version(std::path::Path::new(&support_dir))
    })
    .await
    .map_err(|e| format!("config-version task: {e}"))?
}

/// Run every registered artefact's migration chain against the
/// app-support directory at `support_dir`. Idempotent — running
/// twice in a row on a healthy install returns a no-op
/// [`DbMigrationReport`]. The Dart caller surfaces any non-no-op
/// failure via the corrupt-data dialog and refuses to start the
/// unlock flow.
///
/// Async + `spawn_blocking` — the runner walks every artefact's
/// on-disk chain (read + parse + maybe-rewrite per artefact);
/// keeping it sync would block the FRB worker thread for the
/// duration. Today the chain is short on healthy installs (every
/// artefact is at the current version, no work to do), but a
/// migration that touches several artefacts could run for tens
/// of milliseconds and that is unbounded enough to deserve the
/// spawn_blocking wrapper.
pub async fn migration_run_on_startup(support_dir: String) -> DbMigrationReport {
    tokio::task::spawn_blocking(move || {
        let registry = lfs_core::migration::build_app_registry();
        let report =
            lfs_core::migration::run_on_startup(std::path::Path::new(&support_dir), &registry);
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
    })
    .await
    // The closure above is panic-free (lfs_core::migration::run_on_startup
    // already swallows per-artefact panics into report.fatal_error). On
    // the unlikely off-chance that spawn_blocking itself surfaces a
    // JoinError, return a synthetic fatal-error report rather than
    // bubbling the panic across FRB.
    .unwrap_or_else(|e| DbMigrationReport {
        steps: Vec::new(),
        future_versions: Vec::new(),
        fatal_error: Some(format!("migration runner task: {e}")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_target_version_matches_lfs_core_constant() {
        // The FRB shim must round-trip the workspace constant
        // exactly — a drift here would let the legacy-state probe
        // fall out of sync with the registry's actual chain.
        assert_eq!(
            migration_config_target_version(),
            lfs_core::migration::SchemaVersions::CONFIG
        );
    }

    #[test]
    fn archive_target_version_matches_lfs_core_constant() {
        assert_eq!(
            migration_archive_target_version(),
            lfs_core::migration::SchemaVersions::ARCHIVE
        );
    }

    #[test]
    fn config_target_version_is_at_or_above_v1() {
        // Floors are always positive; the legacy-state probe in
        // `SecurityInitController` reads `>= 1` to decide whether
        // the build supports any version of the artefact.
        assert!(migration_config_target_version() >= 1);
        assert!(migration_archive_target_version() >= 1);
    }

    #[tokio::test]
    async fn config_version_on_disk_returns_minus_one_for_missing_dir() {
        // No `config.json` under `/nonexistent/...` — the probe
        // must collapse to `-1` rather than `Err`. Same shape Dart
        // expects for a fresh install.
        let v = migration_config_version_on_disk("/nonexistent/scan/path-7c8f".into())
            .await
            .expect("missing path must collapse to -1, not Err");
        assert_eq!(v, -1);
    }

    #[tokio::test]
    async fn run_on_startup_against_empty_dir_yields_no_steps_no_fatal() {
        // A fresh app-support directory has no artefacts to walk;
        // the runner must return an empty report (no steps, no
        // future-versions, no fatal-error) so the Dart caller's
        // happy-path branch fires.
        let tmp = tempfile::tempdir().expect("tmp dir");
        let path = tmp.path().to_str().expect("utf-8 tmp path").to_string();
        let report = migration_run_on_startup(path).await;
        assert!(report.steps.is_empty());
        assert!(report.future_versions.is_empty());
        assert!(report.fatal_error.is_none());
    }
}
