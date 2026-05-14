//! FRB adapter for `lfs_core::sessions` pure helpers (search,
//! filter, future per-list utilities).
//!
//! Kept separate from `db.rs` because nothing here touches the
//! DAOs — these helpers operate on caller-projected lists, so the
//! shim can stay sync. The store-actor work lands later under its
//! own `RegistryActor` shim once the broader session_store retire
//! reaches the actor stage.

use lfs_core::sessions::{self, AuthType as CoreAuthType, SessionKind as CoreSessionKind};

/// FRB-visible mirror of [`lfs_core::sessions::AuthType`]. Carries
/// the four app-side authentication methods across the boundary as
/// a typed enum; Dart consumers pattern-match directly rather than
/// round-tripping the wire-string through a `.fromWire` helper.
///
/// FRB codegen lowers each variant to camelCase Dart
/// (`password` / `key` / `keyWithPassword` / `agent`), matching the
/// wire grammar `AuthType::wire_name` round-trips byte-identically.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DbAuthType {
    Password,
    Key,
    KeyWithPassword,
    Agent,
}

impl From<CoreAuthType> for DbAuthType {
    fn from(value: CoreAuthType) -> Self {
        match value {
            CoreAuthType::Password => DbAuthType::Password,
            CoreAuthType::Key => DbAuthType::Key,
            CoreAuthType::KeyWithPassword => DbAuthType::KeyWithPassword,
            CoreAuthType::Agent => DbAuthType::Agent,
        }
    }
}

impl From<DbAuthType> for CoreAuthType {
    fn from(value: DbAuthType) -> Self {
        match value {
            DbAuthType::Password => CoreAuthType::Password,
            DbAuthType::Key => CoreAuthType::Key,
            DbAuthType::KeyWithPassword => CoreAuthType::KeyWithPassword,
            DbAuthType::Agent => CoreAuthType::Agent,
        }
    }
}

/// FRB-visible mirror of [`lfs_core::sessions::SessionKind`]. One
/// enum value per supported transport — the Dart consumer switches
/// on this directly instead of comparing wire strings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DbSessionKind {
    Ssh,
    Webdav,
    S3,
}

impl From<CoreSessionKind> for DbSessionKind {
    fn from(value: CoreSessionKind) -> Self {
        match value {
            CoreSessionKind::Ssh => DbSessionKind::Ssh,
            CoreSessionKind::Webdav => DbSessionKind::Webdav,
            CoreSessionKind::S3 => DbSessionKind::S3,
        }
    }
}

impl From<DbSessionKind> for CoreSessionKind {
    fn from(value: DbSessionKind) -> Self {
        match value {
            DbSessionKind::Ssh => CoreSessionKind::Ssh,
            DbSessionKind::Webdav => CoreSessionKind::Webdav,
            DbSessionKind::S3 => CoreSessionKind::S3,
        }
    }
}

/// Parse a stored `auth_type` wire-string into the typed enum. The
/// FRB sync shim around [`AuthType::from_wire_name`] — used by the
/// DB-row mapper Dart-side after a `sessions.auth_type` column
/// read. Unknown / empty strings fold to [`DbAuthType::Password`]
/// so a future variant added to a newer build cannot brick a
/// legacy row.
#[flutter_rust_bridge::frb(sync)]
pub fn auth_type_from_wire(value: String) -> DbAuthType {
    CoreAuthType::from_wire_name(&value).into()
}

/// Parse a stored `kind` wire-string into the typed enum. The FRB
/// sync shim around [`SessionKind::from_wire_name`] — used by the
/// DB-row mapper Dart-side after a `sessions.kind` column read.
/// Empty / unknown tags fold to [`DbSessionKind::Ssh`] for the same
/// forward-compatibility reason that the parser itself follows.
#[flutter_rust_bridge::frb(sync)]
pub fn session_kind_from_wire(value: String) -> DbSessionKind {
    let opt = if value.is_empty() {
        None
    } else {
        Some(value.as_str())
    };
    CoreSessionKind::from_wire_name(opt).into()
}

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

impl From<DbSessionViaOverride> for lfs_core::session_json::SessionJsonViaOverride {
    fn from(d: DbSessionViaOverride) -> Self {
        Self {
            host: d.host,
            port: d.port,
            user: d.user,
        }
    }
}

impl From<lfs_core::session_json::SessionJsonViaOverride> for DbSessionViaOverride {
    fn from(d: lfs_core::session_json::SessionJsonViaOverride) -> Self {
        Self {
            host: d.host,
            port: d.port,
            user: d.user,
        }
    }
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
///
/// `kind` defaults to `"ssh"` and is omitted on the wire to keep
/// pre-WebDAV importers reading the same payload unchanged.
#[derive(Debug, Clone)]
pub struct DbSessionJsonInput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    /// Typed transport tag — mirrors [`CoreSessionKind`]. The
    /// underlying wire string lives one layer deeper in
    /// `session_json::SessionJsonInput`, so the codec's
    /// conditional-omit grammar stays a single source of truth.
    pub kind: DbSessionKind,
    /// Typed authentication tag — mirrors [`CoreAuthType`]. Same
    /// rationale as `kind` for the typed-vs-wire split.
    pub auth_type: DbAuthType,
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

impl From<DbSessionJsonInput> for lfs_core::session_json::SessionJsonInput {
    fn from(d: DbSessionJsonInput) -> Self {
        Self {
            id: d.id,
            label: d.label,
            folder: d.folder,
            host: d.host,
            port: d.port,
            user: d.user,
            kind: CoreSessionKind::from(d.kind).wire_name().to_string(),
            auth_type: CoreAuthType::from(d.auth_type).wire_name().to_string(),
            key_id: d.key_id,
            key_path: d.key_path,
            created_at_iso: d.created_at_iso,
            updated_at_iso: d.updated_at_iso,
            extras_json: d.extras_json,
            via_session_id: d.via_session_id,
            via_override: d.via_override.map(Into::into),
            notes: d.notes,
            sort_order: d.sort_order,
            last_connected_at_ms: d.last_connected_at_ms,
            include_credentials: d.include_credentials,
            password: d.password,
            key_data: d.key_data,
            passphrase: d.passphrase,
        }
    }
}

/// Tagged-union mirror of `serde_json::Value` for the typed `extras`
/// payload Dart consumes. Fully recursive: nested arrays / objects
/// carry their typed children so a probe at any depth never has to
/// re-parse JSON text. Mirrors
/// [`lfs_core::session_json::SessionJsonValue`].
#[derive(Debug, Clone)]
pub enum DbSessionJsonValue {
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    Text(String),
    Array(Vec<DbSessionJsonValue>),
    Object(Vec<DbSessionJsonExtra>),
}

impl From<lfs_core::session_json::SessionJsonValue> for DbSessionJsonValue {
    fn from(v: lfs_core::session_json::SessionJsonValue) -> Self {
        use lfs_core::session_json::SessionJsonValue as V;
        match v {
            V::Null => DbSessionJsonValue::Null,
            V::Bool(b) => DbSessionJsonValue::Bool(b),
            V::Int(i) => DbSessionJsonValue::Int(i),
            V::Double(d) => DbSessionJsonValue::Double(d),
            V::Text(s) => DbSessionJsonValue::Text(s),
            V::Array(items) => {
                DbSessionJsonValue::Array(items.into_iter().map(Into::into).collect())
            }
            V::Object(pairs) => DbSessionJsonValue::Object(
                pairs
                    .into_iter()
                    .map(|(key, value)| DbSessionJsonExtra {
                        key,
                        value: value.into(),
                    })
                    .collect(),
            ),
        }
    }
}

/// One entry of the decoded `extras` map. FRB does not support
/// `HashMap<String, EnumVariant>` directly across the bridge, so the
/// map is carried as a `Vec<DbSessionJsonExtra>` the Dart consumer
/// re-keys into a `Map<String, ...>` after the call. The same struct
/// doubles as the nested-object carrier inside [`DbSessionJsonValue`].
#[derive(Debug, Clone)]
pub struct DbSessionJsonExtra {
    pub key: String,
    pub value: DbSessionJsonValue,
}

/// Session-shaped decoder output. Field set is the inverse of
/// [`DbSessionJsonInput`]; the Dart `Session.fromJson` factory now
/// rehydrates straight from this struct rather than walking the raw
/// JSON map field-by-field.
///
/// `extras` is a list of `{key, value}` pairs (see
/// [`DbSessionJsonExtra`] for the FRB-shape rationale).
/// `password` / `key_data` / `passphrase` are always present;
/// they hold the empty string when the source payload omitted them.
#[derive(Debug, Clone)]
pub struct DbSessionJsonOutput {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: u32,
    pub user: String,
    /// Typed transport tag — see [`DbSessionJsonInput::kind`] for
    /// the rationale; `Ssh` covers the legacy missing-key case
    /// because [`CoreSessionKind::from_wire_name`] folds unknown
    /// tags onto it.
    pub kind: DbSessionKind,
    /// Typed authentication tag — same shape as
    /// [`DbSessionJsonInput::auth_type`].
    pub auth_type: DbAuthType,
    pub key_id: String,
    pub key_path: String,
    pub created_at_iso: String,
    pub updated_at_iso: String,
    pub extras: Vec<DbSessionJsonExtra>,
    pub via_session_id: Option<String>,
    pub via_override: Option<DbSessionViaOverride>,
    pub notes: String,
    pub sort_order: i32,
    pub last_connected_at_ms: Option<i64>,
    pub password: String,
    pub key_data: String,
    pub passphrase: String,
}

impl From<lfs_core::session_json::SessionJsonOutput> for DbSessionJsonOutput {
    fn from(d: lfs_core::session_json::SessionJsonOutput) -> Self {
        let extras = d
            .extras
            .into_iter()
            .map(|(key, value)| DbSessionJsonExtra {
                key,
                value: value.into(),
            })
            .collect();
        Self {
            id: d.id,
            label: d.label,
            folder: d.folder,
            host: d.host,
            port: d.port,
            user: d.user,
            kind: CoreSessionKind::from_wire_name(Some(d.kind.as_str())).into(),
            auth_type: CoreAuthType::from_wire_name(&d.auth_type).into(),
            key_id: d.key_id,
            key_path: d.key_path,
            created_at_iso: d.created_at_iso,
            updated_at_iso: d.updated_at_iso,
            extras,
            via_session_id: d.via_session_id,
            via_override: d.via_override.map(Into::into),
            notes: d.notes,
            sort_order: d.sort_order,
            last_connected_at_ms: d.last_connected_at_ms,
            password: d.password,
            key_data: d.key_data,
            passphrase: d.passphrase,
        }
    }
}

/// Canonical JSON encoder for a Session. Thin FRB shim around
/// [`lfs_core::session_json::encode_canonical_json`]; the wire-shape
/// invariants live there.
///
/// Sync because the work is one `serde_json::Map` build + one
/// `to_string` — sub-microsecond per call.
#[flutter_rust_bridge::frb(sync)]
pub fn session_canonical_json(input: DbSessionJsonInput) -> Result<String, String> {
    lfs_core::session_json::encode_canonical_json(&input.into())
}

/// Canonical JSON decoder for a Session. Inverse of
/// [`session_canonical_json`]; routes through
/// [`lfs_core::session_json::decode_canonical_json`].
///
/// The Dart `Session.fromJson` factory consumes the
/// [`DbSessionJsonOutput`] shape directly, replacing the retired
/// hand-rolled JSON walk.
#[flutter_rust_bridge::frb(sync)]
pub fn session_decode_from_json(json: String) -> Result<DbSessionJsonOutput, String> {
    lfs_core::session_json::decode_canonical_json(&json).map(Into::into)
}

/// Decode an undo-history snapshot blob — JSON array of canonical
/// session payloads — into the typed list shape. Used by the
/// `SessionHistory._decode` Dart helper.
#[flutter_rust_bridge::frb(sync)]
pub fn session_history_decode_snapshot(json: String) -> Result<Vec<DbSessionJsonOutput>, String> {
    lfs_core::session_json::decode_session_array(&json)
        .map(|v| v.into_iter().map(Into::into).collect())
}

/// Encode an undo-history snapshot blob — JSON array of canonical
/// session payloads — from a list of `DbSessionJsonInput`. Used by
/// the `SessionHistory._encode` Dart helper.
#[flutter_rust_bridge::frb(sync)]
pub fn session_history_encode_snapshot(
    sessions: Vec<DbSessionJsonInput>,
) -> Result<String, String> {
    let typed: Vec<lfs_core::session_json::SessionJsonInput> =
        sessions.into_iter().map(Into::into).collect();
    lfs_core::session_json::encode_session_array(&typed)
}

/// Decode the on-disk `Sessions.extras` JSON column into the typed
/// `{key, value}` list shape. Mapper-side consumer drops its
/// jsonDecode call when this lands; corrupt blobs fold to empty so
/// a session never fails to load on a malformed extras column.
#[flutter_rust_bridge::frb(sync)]
pub fn session_extras_decode(json: String) -> Vec<DbSessionJsonExtra> {
    lfs_core::session_json::decode_extras_string(&json)
        .into_iter()
        .map(|(key, value)| DbSessionJsonExtra {
            key,
            value: value.into(),
        })
        .collect()
}
