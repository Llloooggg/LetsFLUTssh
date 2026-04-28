//! FRB adapter for `lfs_core::sessions` pure helpers (search,
//! filter, future per-list utilities).
//!
//! Kept separate from `db.rs` because nothing here touches the
//! DAOs — these helpers operate on caller-projected lists, so the
//! shim can stay sync. The store-actor work lands later under its
//! own `RegistryActor` shim once the broader session_store retire
//! reaches the actor stage.

use lfs_core::sessions;

/// Searchable Session projection — id + the four fields the UI
/// search bar matches against. The Dart caller projects its
/// domain `Session` list once and feeds it here, avoiding a
/// credential round-trip across FFI.
#[derive(Debug, Clone)]
pub struct DbSearchableSession {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub user: String,
}

impl From<DbSearchableSession> for sessions::SearchableSession {
    fn from(d: DbSearchableSession) -> Self {
        Self {
            id: d.id,
            label: d.label,
            folder: d.folder,
            host: d.host,
            user: d.user,
        }
    }
}

/// Case-insensitive substring search across [`label`, `folder`,
/// `host`, `user`]. Returns matched ids in input order.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_filter(items: Vec<DbSearchableSession>, query: String) -> Vec<String> {
    let projected: Vec<sessions::SearchableSession> = items.into_iter().map(Into::into).collect();
    sessions::filter_sessions(&projected, &query)
}
