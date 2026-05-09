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

#[cfg(test)]
mod tests {
    use super::*;

    fn s(id: &str, label: &str, folder: &str, host: &str, user: &str) -> DbSearchableSession {
        DbSearchableSession {
            id: id.into(),
            label: label.into(),
            folder: folder.into(),
            host: host.into(),
            user: user.into(),
        }
    }

    #[test]
    fn sessions_filter_returns_every_id_for_empty_query() {
        let ids = sessions_filter(
            vec![
                s("a", "Alpha", "prod", "alpha.example.com", "deploy"),
                s("b", "Bravo", "stage", "bravo.example.com", "deploy"),
            ],
            String::new(),
        );
        assert_eq!(ids, vec!["a", "b"]);
    }

    #[test]
    fn sessions_filter_matches_label_case_insensitively() {
        let ids = sessions_filter(
            vec![
                s("a", "Production Edge", "prod", "h1", "u1"),
                s("b", "Staging Edge", "stage", "h2", "u2"),
            ],
            "PRODUCTION".into(),
        );
        assert_eq!(ids, vec!["a"]);
    }

    #[test]
    fn sessions_filter_matches_host_field() {
        let ids = sessions_filter(
            vec![s("only", "x", "f", "edge.example.com", "u")],
            "example".into(),
        );
        assert_eq!(ids, vec!["only"]);
    }

    #[test]
    fn validate_fields_returns_none_for_well_formed() {
        assert!(sessions_validate_fields("h.example.com".into(), 22, "deploy".into()).is_none());
    }

    #[test]
    fn validate_fields_rejects_blank_host() {
        assert!(sessions_validate_fields(String::new(), 22, "deploy".into()).is_some());
    }

    #[test]
    fn validate_fields_rejects_zero_port() {
        assert!(sessions_validate_fields("h".into(), 0, "u".into()).is_some());
    }

    #[test]
    fn validate_fields_rejects_blank_user() {
        assert!(sessions_validate_fields("h".into(), 22, String::new()).is_some());
    }

    #[test]
    fn count_in_folder_matches_exact_and_descendants() {
        let folders = vec![
            "production".to_string(),
            "production/edge".to_string(),
            "staging".to_string(),
        ];
        assert_eq!(sessions_count_in_folder(folders, "production".into()), 2);
    }

    #[test]
    fn count_in_folder_with_empty_path_counts_root_level() {
        let folders = vec![String::new(), String::new(), "production".to_string()];
        assert_eq!(sessions_count_in_folder(folders, String::new()), 2);
    }
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

/// FRB mirror of Dart `ProxyJumpOverride` — used inside
/// [`DbSessionJsonInput`] to carry an optional via-override.
#[derive(Debug, Clone)]
pub struct DbSessionViaOverride {
    pub host: String,
    pub port: u32,
    pub user: String,
}

/// Session-shaped input for the canonical JSON encoder. Mirrors
/// the field set Dart `Session.toJson` (and
/// `toJsonWithCredentials`) emits, including the conditional-omit
/// invariants (`key_id` empty → omit, `extras_json` empty → omit,
/// `notes` empty → omit, `sort_order == 0` → omit, optional fields
/// → omit when None).
///
/// `extras_json` carries the JSON-encoded `extras` map verbatim;
/// the encoder re-parses it once so the output `extras` value is
/// the raw object, matching Dart's `'extras': extras` insertion.
#[derive(Debug, Clone)]
pub struct DbSessionJsonInput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    pub auth_type: String,
    pub key_id: String,
    pub key_path: String,
    pub created_at_iso: String,
    pub updated_at_iso: String,
    pub extras_json: String,
    pub via_session_id: Option<String>,
    pub via_override: Option<DbSessionViaOverride>,
    pub notes: String,
    pub sort_order: i32,
    pub last_connected_at_ms: Option<i64>,
    pub include_credentials: bool,
    pub password: String,
    pub key_data: String,
    pub passphrase: String,
}

/// Canonical JSON encoder for a Session. Emits the exact field
/// set + conditional-omit rules Dart `Session.toJson` /
/// `toJsonWithCredentials` produce. Single source of truth for
/// the wire shape; the Dart `session_json_drift_test` round-trips
/// a fixture through both encoders and asserts logical equality
/// to catch a future field-add on one side but not the other.
///
/// Sync because the work is one `serde_json::Map` build + one
/// `to_string` — sub-microsecond per call.
#[flutter_rust_bridge::frb(sync)]
pub fn session_canonical_json(input: DbSessionJsonInput) -> Result<String, String> {
    use serde_json::{json, Map, Value};
    let mut obj = Map::new();
    obj.insert("id".into(), json!(input.id));
    obj.insert("label".into(), json!(input.label));
    obj.insert("folder".into(), json!(input.folder));
    obj.insert("host".into(), json!(input.host));
    obj.insert("port".into(), json!(input.port));
    obj.insert("user".into(), json!(input.user));
    obj.insert("auth_type".into(), json!(input.auth_type));
    if !input.key_id.is_empty() {
        obj.insert("key_id".into(), json!(input.key_id));
    }
    obj.insert("key_path".into(), json!(input.key_path));
    obj.insert("created_at".into(), json!(input.created_at_iso));
    obj.insert("updated_at".into(), json!(input.updated_at_iso));
    if !input.extras_json.is_empty() {
        let parsed: Value = serde_json::from_str(&input.extras_json)
            .map_err(|e| format!("extras_json parse: {e}"))?;
        if let Some(map) = parsed.as_object() {
            if !map.is_empty() {
                obj.insert("extras".into(), parsed);
            }
        }
    }
    if let Some(via) = input.via_session_id.as_deref() {
        if !via.is_empty() {
            obj.insert("via_session_id".into(), json!(via));
        }
    }
    if let Some(over) = &input.via_override {
        obj.insert(
            "via_override".into(),
            json!({"host": over.host, "port": over.port, "user": over.user}),
        );
    }
    if !input.notes.is_empty() {
        obj.insert("notes".into(), json!(input.notes));
    }
    if input.sort_order != 0 {
        obj.insert("sort_order".into(), json!(input.sort_order));
    }
    if let Some(ms) = input.last_connected_at_ms {
        obj.insert("last_connected_at_ms".into(), json!(ms));
    }
    if input.include_credentials {
        obj.insert("password".into(), json!(input.password));
        obj.insert("key_data".into(), json!(input.key_data));
        obj.insert("passphrase".into(), json!(input.passphrase));
    }
    serde_json::to_string(&Value::Object(obj))
        .map_err(|e| format!("session_canonical_json serialise: {e}"))
}
