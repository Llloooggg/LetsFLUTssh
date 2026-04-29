//! FRB adapter for `lfs_core::sessions::Registry`.
//!
//! Exposes the read-side view (sessions list + folder map +
//! derived empty / collapsed paths) as a sync snapshot. Async
//! reload endpoint forces a re-hydration from the live DB —
//! Dart calls it on first load and the FRB DAO write paths
//! call it automatically (see `notify_sessions_on_ok`).
//!
//! Today the Dart `SessionStore` still runs its own DAO walk;
//! this surface lets a future slice swap that walk for a
//! `sessions_registry_snapshot()` read against the same view
//! the Rust write paths kept current. Both halves coexist
//! during the migration window.
//!
//! Wire-shape note: the snapshot mirror keeps the same struct
//! shapes the existing `db_sessions_list_all` / `db_folders_list_all`
//! returns, so the Dart caller's `dbSessionToSession` mapper
//! reuses unchanged.

use crate::api::db::{DbFolder, DbSession};

/// Snapshot of the Rust-side sessions / folders cache view.
/// Mirrors `lfs_core::sessions::RegistryView` across the FRB
/// boundary using the same `DbSession` / `DbFolder` types the
/// DAO endpoints already expose.
#[derive(Debug, Clone)]
pub struct DbSessionRegistryView {
    pub sessions: Vec<DbSession>,
    pub folders: Vec<DbFolder>,
    pub empty_folders: Vec<String>,
    pub collapsed_folders: Vec<String>,
}

/// Force a re-hydration of the Rust-side registry view from the
/// live DB. Async because `db.with_conn` runs blocking SQL —
/// schedule on `tokio::task::spawn_blocking` so the FRB worker
/// thread isn't pinned. Idempotent: a reload after a no-op
/// state still produces the same view.
///
/// Errors when no DB is initialised — the Dart caller surfaces
/// the misuse instead of silently seeing an empty view.
pub async fn sessions_registry_reload() -> Result<(), String> {
    tokio::task::spawn_blocking(|| {
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        app.sessions_registry.reload(&db).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("registry reload task: {e}"))?
}

/// Cheap sync read of the cached view. Returns the snapshot the
/// FRB DAO writers + the explicit `sessions_registry_reload`
/// keep current.
///
/// Sync because the snapshot is a single owned `clone` of the
/// `RegistryView` — bounded by the session count (≤1k entries
/// in practice → microseconds). The lock is read-only so
/// concurrent snapshots don't block each other.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_snapshot() -> DbSessionRegistryView {
    let app = lfs_core::app::instance();
    let view = app.sessions_registry.snapshot();
    DbSessionRegistryView {
        sessions: view.sessions.into_iter().map(DbSession::from).collect(),
        folders: view.folders.into_values().map(DbFolder::from).collect(),
        empty_folders: view.empty_folders.into_iter().collect(),
        collapsed_folders: view.collapsed_folders.into_iter().collect(),
    }
}

/// Cached session count. Cheap — one read-lock + a length
/// integer; no clone. Used by the future Riverpod count badge
/// without touching the snapshot path.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_count() -> u32 {
    lfs_core::app::instance().sessions_registry.session_count() as u32
}

/// Count cached sessions whose folder path equals [`folder_path`]
/// or sits under `{folder_path}/`. Reads off the cached view —
/// no DB round-trip; the FRB writers keep the view current.
/// Empty path counts root-level sessions.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_count_in_folder(folder_path: String) -> u32 {
    lfs_core::app::instance()
        .sessions_registry
        .count_in_folder(&folder_path) as u32
}
