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

/// Validate a session's storable-field set: host non-empty, port in
/// 1..=65535, user non-empty. Returns the user-facing error message
/// or `None` when the session is storable. Same grammar as
/// `Session.validate` Dart-side.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_validate_fields(host: String, port: u16, user: String) -> Option<String> {
    sessions::validate_session_fields(&host, port, &user)
}

/// Count session folders matching [`folder_path`] exactly or sitting
/// under `{folder_path}/`. Empty path counts root-level sessions.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_count_in_folder(session_folders: Vec<String>, folder_path: String) -> u32 {
    sessions::count_in_folder(&session_folders, &folder_path) as u32
}

/// Return a label that does not collide with any entry in
/// [`taken`]. Identity for free `base`; otherwise appends
/// `(copy)`, `(copy 2)`, `(copy 3)`, … until a free slot is found.
/// Empty `base` passes through unchanged.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_unique_label(base: String, taken: Vec<String>) -> String {
    let set: std::collections::HashSet<String> = taken.into_iter().collect();
    sessions::unique_label(&base, &set)
}

/// Distinct, sorted folder names referenced by [`session_folders`].
/// Drops empty paths (root-level sessions). Used by the live
/// folder-list accessor + folder-picker autocomplete.
#[flutter_rust_bridge::frb(sync)]
pub fn sessions_distinct_folders(session_folders: Vec<String>) -> Vec<String> {
    sessions::distinct_folders(&session_folders)
}
