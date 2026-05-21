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
/// the post-migration version probe in `SecurityInitController`
/// to detect configs below the current schema floor without
/// duplicating the `SchemaVersions::CONFIG` literal Dart-side.
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
/// error. Used by the post-migration version probe in
/// `SecurityInitController` to detect a config below the current
/// schema floor *after* the migration runner has already walked
/// every chain it knows about.
///
/// Async + `spawn_blocking` — the read touches the filesystem and
/// must not stall the FRB worker thread. The earlier sync shape
/// happened to work because Dart only calls this once at startup,
/// but a future test that drives the path from inside an event
/// loop would block.
pub async fn migration_config_version_on_disk() -> Result<i32, String> {
    let support_dir = lfs_core::security::master_password::try_pinned_support_dir()
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    tokio::task::spawn_blocking(move || {
        use lfs_core::migration::artefacts::ConfigArtefact;
        use lfs_core::migration::Artefact;
        ConfigArtefact.read_version(support_dir)
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
pub async fn migration_run_on_startup() -> DbMigrationReport {
    let support_dir = match lfs_core::security::master_password::try_pinned_support_dir() {
        Ok(dir) => dir,
        Err(e) => {
            return DbMigrationReport {
                steps: Vec::new(),
                future_versions: Vec::new(),
                fatal_error: Some(crate::api::frb_err::from_core(&e)),
            };
        }
    };
    tokio::task::spawn_blocking(move || {
        let registry = lfs_core::migration::build_app_registry();
        let report = lfs_core::migration::run_on_startup(support_dir, &registry);
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
        // exactly — a divergence here would let the post-migration
        // version probe fall out of sync with the registry's
        // actual chain.
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
        // Floors are always positive; the post-migration version
        // probe in `SecurityInitController` reads `>= 1` to decide
        // whether the build supports any version of the artefact.
        assert!(migration_config_target_version() >= 1);
        assert!(migration_archive_target_version() >= 1);
    }

    // The path-specific behaviours (missing config -> -1, empty dir ->
    // no-op report) are covered against the explicit `&Path` API in
    // `lfs_core::migration` + `lfs_core::migration::artefacts`. These
    // FRB wrappers only resolve the pinned support dir and delegate, so
    // they carry no path-specific tests of their own.
}
