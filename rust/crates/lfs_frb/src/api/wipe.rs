//! FRB adapter for `lfs_core::security::wipe`.
//!
//! Two pure-stat helpers exposed sync (`has_pending_wipe`,
//! `has_any_state` — both run early during the unlock-controller
//! bootstrap, so an async hop here would needlessly defer the gate).
//! `sweep_files` is async because the worst-case run deletes a
//! couple dozen files plus the `logs/` tree on a busy disk. All three
//! operate on the app-support directory pinned at `config_store_init`.
//!
//! The Dart shim still owns the per-session credential cache evict
//! and the orchestration of the keychain purge (`wipe_keychain_run`,
//! which itself routes through
//! `lfs_os_security::secure_key_storage` per platform). Hardware-
//! vault clear is owned by `lfs_os_security::hardware_tier_vault`
//! via FRB. This module is the file half only. Path-specific
//! behaviour is covered against the explicit `&Path` API in
//! `lfs_core::security::wipe`.

use lfs_core::security::master_password;
use lfs_core::security::wipe;

#[flutter_rust_bridge::frb(sync)]
pub fn wipe_has_pending() -> bool {
    match master_password::try_pinned_support_dir() {
        Ok(dir) => wipe::has_pending_wipe(dir),
        Err(_) => false,
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn wipe_has_any_state() -> bool {
    match master_password::try_pinned_support_dir() {
        Ok(dir) => wipe::has_any_state(dir),
        Err(_) => false,
    }
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
/// worst-case touches the DB sidecars + the whole logs tree. An
/// empty report is returned when the support dir is unpinned or the
/// runtime is shutting down rather than panicking the FRB worker.
pub async fn wipe_sweep_files() -> DbFileSweepReport {
    let Ok(support_dir) = master_password::try_pinned_support_dir() else {
        return DbFileSweepReport {
            deleted_files: Vec::new(),
            failed_files: Vec::new(),
        };
    };
    tokio::task::spawn_blocking(move || wipe::sweep_files(support_dir))
        .await
        .map(DbFileSweepReport::from)
        .unwrap_or(DbFileSweepReport {
            deleted_files: Vec::new(),
            failed_files: Vec::new(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_sweep_report_clone_round_trip() {
        let r = DbFileSweepReport {
            deleted_files: vec!["credentials.kdf".into()],
            failed_files: vec!["letsflutssh.db-wal".into()],
        };
        let c = r.clone();
        assert_eq!(c.deleted_files, vec!["credentials.kdf".to_string()]);
        assert_eq!(c.failed_files, vec!["letsflutssh.db-wal".to_string()]);
    }
}
