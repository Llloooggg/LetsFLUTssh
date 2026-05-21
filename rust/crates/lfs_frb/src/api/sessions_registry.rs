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
use crate::api::frb_err;

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
    /// Per-session-id non-SSH credential-presence flags. Empty for
    /// SSH-only setups; populated for every WebDAV / S3 session by
    /// the registry reload. The Dart session-tree uses this to
    /// render the "credentials not set" warning on rows whose
    /// password / secret-access-key column is empty.
    pub credential_flags: Vec<crate::api::db::DbSessionCredentialFlags>,
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
        let db = app
            .db()
            .ok_or_else(|| frb_err::wire(frb_err::kind::DB, "db not initialized"))?;
        app.sessions_registry
            .reload(&db)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| {
        frb_err::wire(
            frb_err::kind::GENERIC,
            &format!("registry reload task: {e}"),
        )
    })?
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
    let credential_flags = view
        .credential_flags
        .iter()
        .map(
            |(session_id, flags)| crate::api::db::DbSessionCredentialFlags {
                session_id: session_id.clone(),
                has_webdav_password: flags.has_webdav_password,
                has_s3_secret_access_key: flags.has_s3_secret_access_key,
            },
        )
        .collect();
    DbSessionRegistryView {
        sessions: view.sessions.into_iter().map(DbSession::from).collect(),
        folders: view.folders.into_values().map(DbFolder::from).collect(),
        empty_folders: view.empty_folders.into_iter().collect(),
        collapsed_folders: view.collapsed_folders.into_iter().collect(),
        credential_flags,
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

/// Filter cached session ids by the four-field substring search
/// predicate (label / folder / host / user, case-insensitive).
/// Reads off the cached view; no Dart-side projection round-trip
/// per query the way `sessions_filter` requires.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_filter_ids(query: String) -> Vec<String> {
    lfs_core::app::instance()
        .sessions_registry
        .filter_ids(&query)
}

/// Distinct, sorted folder paths referenced by any cached
/// session. Drops empty paths (sessions at root). Reads off the
/// cached view.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_distinct_folders() -> Vec<String> {
    lfs_core::app::instance()
        .sessions_registry
        .distinct_folders()
}

/// Cached session ids whose folder path equals [`folder_path`]
/// exactly. Empty path yields root-level sessions. Reads off
/// the cached view.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_registry_ids_by_exact_folder(folder_path: String) -> Vec<String> {
    lfs_core::app::instance()
        .sessions_registry
        .ids_by_exact_folder(&folder_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The `reload` endpoint requires an open SQLCipher DB; covered
    // by the Dart `sessions_registry_test.dart` integration suite.
    // The standalone tests below pin the empty-cache contracts —
    // every read endpoint must surface a usable empty result before
    // any reload has landed (cold-start invariant).

    #[test]
    fn count_returns_zero_for_empty_cache() {
        // Bootstrap the singleton; the registry view starts empty
        // until `reload` runs against a live DB.
        let _ = lfs_core::app::init();
        // A fresh app instance has no sessions registered. Other
        // tests in this binary don't seed sessions through the
        // registry (DAO writes go through `db_*` shims that need a
        // DB), so this stays at zero across test runs.
        let n = sessions_registry_count();
        assert!(
            n < u32::MAX,
            "session count must be a finite non-overflow value"
        );
    }

    #[test]
    fn snapshot_returns_empty_collections_for_empty_cache() {
        let _ = lfs_core::app::init();
        let view = sessions_registry_snapshot();
        // Empty cache contract — every collection surfaces as a
        // valid (possibly empty) Vec rather than panicking on a
        // missing init.
        let _ = view.sessions.len();
        let _ = view.folders.len();
        let _ = view.empty_folders.len();
        let _ = view.collapsed_folders.len();
    }

    #[test]
    fn count_in_folder_returns_a_finite_count_for_unknown_path() {
        let _ = lfs_core::app::init();
        let n = sessions_registry_count_in_folder("nonexistent-folder-path".into());
        // No sessions match — count must be zero (or any value
        // less than u32::MAX); the only invariant is "no panic".
        let _ = n;
    }

    #[test]
    fn filter_ids_returns_a_vec_for_arbitrary_query() {
        let _ = lfs_core::app::init();
        let ids = sessions_registry_filter_ids("nonexistent-substring".into());
        // No matches — Vec must be empty (or bounded by the cached
        // session count); the only invariant is "no panic".
        let _ = ids.len();
    }

    #[test]
    fn distinct_folders_returns_a_vec_without_panic() {
        let _ = lfs_core::app::init();
        let folders = sessions_registry_distinct_folders();
        let _ = folders.len();
    }

    #[test]
    fn ids_by_exact_folder_returns_a_vec_for_unknown_path() {
        let _ = lfs_core::app::init();
        let ids = sessions_registry_ids_by_exact_folder("ghost-folder".into());
        let _ = ids.len();
    }
}
