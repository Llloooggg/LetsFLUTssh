//! FRB adapter for `lfs_core::security::wipe`.
//!
//! Two pure-stat helpers exposed sync (`has_pending_wipe`,
//! `has_any_state` — both run at startup before any provider graph
//! is up, so an async hop here would needlessly defer the gate).
//! `sweep_files` is async because the worst-case run deletes a
//! couple dozen files plus the `logs/` tree on a busy disk.
//!
//! The Dart shim still owns the keychain (`flutter_secure_storage`)
//! purge, the `com.letsflutssh/hardware_vault` `MethodChannel`
//! invocations, and the per-session credential cache evict. Those
//! ride on platform plugins that have no equivalent in `lfs_core`;
//! this module is the file half only.

use std::path::Path;

use lfs_core::security::wipe;

#[flutter_rust_bridge::frb(sync)]
pub fn wipe_has_pending(support_dir: String) -> bool {
    wipe::has_pending_wipe(Path::new(&support_dir))
}

#[flutter_rust_bridge::frb(sync)]
pub fn wipe_has_any_state(support_dir: String) -> bool {
    wipe::has_any_state(Path::new(&support_dir))
}

/// Per-file outcome of a [`wipe_sweep_files`] run. The Dart caller
/// merges this with the keychain / native-vault / overlay results
/// before surfacing the final `WipeReport` to the UI.
#[derive(Debug, Clone)]
pub struct DbFileSweepReport {
    pub deleted_files: Vec<String>,
    pub failed_files: Vec<String>,
}

impl From<wipe::FileSweepReport> for DbFileSweepReport {
    fn from(r: wipe::FileSweepReport) -> Self {
        DbFileSweepReport {
            deleted_files: r.deleted_files,
            failed_files: r.failed_files,
        }
    }
}

/// Walk every managed file + the logs directory; clear the
/// `.wipe-pending` marker last so a mid-sweep crash leaves a trace
/// the next launch can detect. Async + on the blocking pool —
/// worst-case touches the DB sidecars + the whole logs tree.
pub async fn wipe_sweep_files(support_dir: String) -> DbFileSweepReport {
    tokio::task::spawn_blocking(move || wipe::sweep_files(Path::new(&support_dir)))
        .await
        .map(DbFileSweepReport::from)
        // Spawn-blocking only fails when the runtime is shutting down
        // — surface an empty report rather than panicking the FRB
        // worker. The Dart caller logs the wipe outcome regardless;
        // an empty deleted/failed pair is the safest "nothing happened"
        // signal in that edge case.
        .unwrap_or(DbFileSweepReport {
            deleted_files: Vec::new(),
            failed_files: Vec::new(),
        })
}
