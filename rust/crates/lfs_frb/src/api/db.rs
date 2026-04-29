//! FRB adapter for `lfs_core::db` DAOs.
//!
//! Each DAO is exposed as `db_<table>_<verb>` async fns. The
//! adapter resolves the running `Db` handle off `AppState`,
//! marshals the row shape across the FRB boundary, and runs the
//! actual rusqlite call inside `tokio::task::spawn_blocking` so
//! the FRB worker thread isn't pinned by disk I/O.

fn require_db() -> Result<std::sync::Arc<lfs_core::db::Db>, String> {
    lfs_core::app::instance()
        .db()
        .ok_or_else(|| "db not initialized".to_string())
}

/// Run a sync DAO closure inside `spawn_blocking` against the
/// running `Db` connection. Centralises the boilerplate so each
/// DAO function below is one short call site.
async fn run_db<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
{
    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn(f).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db task: {e}"))?
}

// ---- ssh_keys ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSshKey {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::ssh_keys::SshKeyRow> for DbSshKey {
    fn from(r: lfs_core::db::ssh_keys::SshKeyRow) -> Self {
        Self {
            id: r.id,
            label: r.label,
            private_key: r.private_key,
            public_key: r.public_key,
            key_type: r.key_type,
            is_generated: r.is_generated,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbSshKey> for lfs_core::db::ssh_keys::SshKeyRow {
    fn from(r: DbSshKey) -> Self {
        Self {
            id: r.id,
            label: r.label,
            private_key: r.private_key,
            public_key: r.public_key,
            key_type: r.key_type,
            is_generated: r.is_generated,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_ssh_keys_list_all() -> Result<Vec<DbSshKey>, String> {
    run_db(lfs_core::db::ssh_keys::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSshKey::from).collect())
}

pub async fn db_ssh_keys_get(id: String) -> Result<Option<DbSshKey>, String> {
    run_db(move |c| lfs_core::db::ssh_keys::get(c, &id))
        .await
        .map(|opt| opt.map(DbSshKey::from))
}

pub async fn db_ssh_keys_upsert(row: DbSshKey) -> Result<(), String> {
    let row: lfs_core::db::ssh_keys::SshKeyRow = row.into();
    run_db(move |c| lfs_core::db::ssh_keys::upsert(c, &row)).await
}

pub async fn db_ssh_keys_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::ssh_keys::delete(c, &id))
        .await
        .map(|n| n as u32)
}

/// Stage the stored key's private PEM bytes into the SecretStore
/// under `key.priv.<id>`. Returns `true` when bytes landed in the
/// store, `false` when the row is missing or the column is empty.
/// Plaintext does not cross the FRB boundary — Dart only sees the
/// boolean.
pub async fn db_ssh_keys_stage_secret(key_id: String) -> Result<bool, String> {
    run_db(move |c| lfs_core::db::ssh_keys::stage_secret_into_store(c, &key_id)).await
}

/// Listing-only view of `ssh_keys` for UIs that don't need the PEM
/// bytes — key manager listing, import dedup, export-selection
/// pickers. The SHA-256 fingerprints are computed inside Rust so
/// callers can compare against scanned keys without pulling
/// plaintext through the FRB boundary.
#[derive(Debug, Clone)]
pub struct DbSshKeyMetadata {
    pub id: String,
    pub label: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
    pub private_fingerprint: String,
    pub public_fingerprint: String,
}

impl From<lfs_core::db::ssh_keys::SshKeyMetadata> for DbSshKeyMetadata {
    fn from(m: lfs_core::db::ssh_keys::SshKeyMetadata) -> Self {
        DbSshKeyMetadata {
            id: m.id,
            label: m.label,
            public_key: m.public_key,
            key_type: m.key_type,
            is_generated: m.is_generated,
            created_at_ms: m.created_at_ms,
            private_fingerprint: m.private_fingerprint,
            public_fingerprint: m.public_fingerprint,
        }
    }
}

pub async fn db_ssh_keys_list_metadata() -> Result<Vec<DbSshKeyMetadata>, String> {
    run_db(lfs_core::db::ssh_keys::list_metadata)
        .await
        .map(|rows| rows.into_iter().map(DbSshKeyMetadata::from).collect())
}

// ---- folders -----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbFolder {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub sort_order: i64,
    pub collapsed: bool,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::folders::FolderRow> for DbFolder {
    fn from(r: lfs_core::db::folders::FolderRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            parent_id: r.parent_id,
            sort_order: r.sort_order,
            collapsed: r.collapsed,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbFolder> for lfs_core::db::folders::FolderRow {
    fn from(r: DbFolder) -> Self {
        Self {
            id: r.id,
            name: r.name,
            parent_id: r.parent_id,
            sort_order: r.sort_order,
            collapsed: r.collapsed,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_folders_list_all() -> Result<Vec<DbFolder>, String> {
    run_db(lfs_core::db::folders::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbFolder::from).collect())
}

pub async fn db_folders_upsert(row: DbFolder) -> Result<(), String> {
    let row: lfs_core::db::folders::FolderRow = row.into();
    let res = run_db(move |c| lfs_core::db::folders::upsert(c, &row)).await;
    notify_sessions_on_ok(&res);
    res
}

pub async fn db_folders_delete(id: String) -> Result<u32, String> {
    let res = run_db(move |c| lfs_core::db::folders::delete(c, &id))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_folders_delete_all() -> Result<u32, String> {
    let res = run_db(lfs_core::db::folders::delete_all)
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_folders_toggle_collapsed(id: String) -> Result<u32, String> {
    let res = run_db(move |c| lfs_core::db::folders::toggle_collapsed(c, &id))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_folders_update_name_parent(
    id: String,
    name: String,
    parent_id: Option<String>,
) -> Result<u32, String> {
    let res = run_db(move |c| {
        lfs_core::db::folders::update_name_parent(c, &id, &name, parent_id.as_deref())
    })
    .await
    .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

/// Composite folder rename / move — Rust resolves the existing
/// folder by `old_path`, computes the new leaf name + new parent
/// path, ensures the new parent exists, then updates the row in
/// one transaction.
///
/// Replaces the Dart `SessionStore.renameFolder` + `moveFolder`
/// two-step (which carried a stale `parent_id` from the row
/// cache and silently failed to re-parent on cross-tree moves).
///
/// Returns 1 on success, 0 when `old_path` resolves to nothing.
/// `Err` for cycle moves (folder under its own descendant).
pub async fn db_folders_rename_path_cascade(
    old_path: String,
    new_path: String,
    now_ms: i64,
) -> Result<u32, String> {
    let res = tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn_mut(|c| {
            lfs_core::db::folders::rename_path_cascade(c, &old_path, &new_path, now_ms)
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db task: {e}"))?
    .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_folders_delete_recursive(id: String) -> Result<u32, String> {
    let res = run_db(move |c| lfs_core::db::folders::delete_recursive(c, &id))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

/// Publish [`SessionsChanged`] when the wrapped DAO result is `Ok(_)`.
/// No-op on `Err` so a failed write doesn't trigger a downstream
/// re-fetch storm against state that didn't actually change.
///
/// Also rebuilds the Rust-side `sessions::Registry` view so future
/// callers reading off the snapshot see the post-write state
/// without round-tripping through the Dart store. Best-effort —
/// a reload failure is logged via the Registry's own contract
/// (preserves the prior view) and the bus event still fires so
/// the Dart cache reloads.
fn notify_sessions_on_ok<T>(res: &Result<T, String>) {
    if res.is_ok() {
        let app = lfs_core::app::instance();
        if let Some(db) = app.db() {
            let _ = app.sessions_registry.reload(&db);
        }
        lfs_core::sessions::notify_changed(&app);
    }
}

fn notify_sessions_on_ok_when<T>(res: &Result<T, String>, when: impl Fn(&T) -> bool) {
    if let Ok(v) = res {
        if when(v) {
            let app = lfs_core::app::instance();
            if let Some(db) = app.db() {
                let _ = app.sessions_registry.reload(&db);
            }
            lfs_core::sessions::notify_changed(&app);
        }
    }
}

// ---- sessions ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSession {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<lfs_core::db::sessions::SessionRow> for DbSession {
    fn from(r: lfs_core::db::sessions::SessionRow) -> Self {
        Self {
            id: r.id,
            label: r.label,
            folder_id: r.folder_id,
            host: r.host,
            port: r.port,
            user: r.user,
            auth_type: r.auth_type,
            password: r.password,
            key_path: r.key_path,
            key_data: r.key_data,
            key_id: r.key_id,
            passphrase: r.passphrase,
            sort_order: r.sort_order,
            notes: r.notes,
            last_connected_at_ms: r.last_connected_at_ms,
            extras: r.extras,
            via_session_id: r.via_session_id,
            via_host: r.via_host,
            via_port: r.via_port,
            via_user: r.via_user,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

impl From<DbSession> for lfs_core::db::sessions::SessionRow {
    fn from(r: DbSession) -> Self {
        Self {
            id: r.id,
            label: r.label,
            folder_id: r.folder_id,
            host: r.host,
            port: r.port,
            user: r.user,
            auth_type: r.auth_type,
            password: r.password,
            key_path: r.key_path,
            key_data: r.key_data,
            key_id: r.key_id,
            passphrase: r.passphrase,
            sort_order: r.sort_order,
            notes: r.notes,
            last_connected_at_ms: r.last_connected_at_ms,
            extras: r.extras,
            via_session_id: r.via_session_id,
            via_host: r.via_host,
            via_port: r.via_port,
            via_user: r.via_user,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

pub async fn db_sessions_list_all() -> Result<Vec<DbSession>, String> {
    run_db(lfs_core::db::sessions::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSession::from).collect())
}

pub async fn db_sessions_get(id: String) -> Result<Option<DbSession>, String> {
    run_db(move |c| lfs_core::db::sessions::get(c, &id))
        .await
        .map(|opt| opt.map(DbSession::from))
}

pub async fn db_sessions_upsert(row: DbSession) -> Result<(), String> {
    let row: lfs_core::db::sessions::SessionRow = row.into();
    let res = run_db(move |c| lfs_core::db::sessions::upsert(c, &row)).await;
    notify_sessions_on_ok(&res);
    res
}

pub async fn db_sessions_delete(id: String) -> Result<u32, String> {
    let res = run_db(move |c| lfs_core::db::sessions::delete(c, &id))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

/// Mirror of [`lfs_core::db::sessions::StagedSecrets`] crossing FRB.
#[derive(Debug, Clone)]
pub struct DbStagedSecrets {
    pub auth_type: String,
    pub has_password: bool,
    pub has_key_data: bool,
    pub has_passphrase: bool,
}

impl From<lfs_core::db::sessions::StagedSecrets> for DbStagedSecrets {
    fn from(r: lfs_core::db::sessions::StagedSecrets) -> Self {
        Self {
            auth_type: r.auth_type,
            has_password: r.has_password,
            has_key_data: r.has_key_data,
            has_passphrase: r.has_passphrase,
        }
    }
}

/// Read the credential columns for [`session_id`] and push every
/// non-empty value straight into the process-singleton SecretStore
/// under the canonical `sess.<slot>.<id>` ids — bytes never cross
/// back to Dart. Returns metadata describing which slots were staged
/// so the caller can dispatch to the matching connect variant. Null
/// when the row no longer exists.
pub async fn db_sessions_stage_secrets(
    session_id: String,
) -> Result<Option<DbStagedSecrets>, String> {
    run_db(move |c| lfs_core::db::sessions::stage_secrets_into_store(c, &session_id))
        .await
        .map(|opt| opt.map(DbStagedSecrets::from))
}

/// Mirror of [`lfs_core::db::sessions::SessionMetadata`] crossing
/// FRB. Carries every column except the credential triplet so the
/// edit dialog can save metadata without reading old secret bytes
/// back onto the Dart heap.
#[derive(Debug, Clone)]
pub struct DbSessionMetadata {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub key_path: String,
    pub key_id: Option<String>,
    pub sort_order: i64,
    pub notes: String,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub updated_at_ms: i64,
}

impl From<DbSessionMetadata> for lfs_core::db::sessions::SessionMetadata {
    fn from(m: DbSessionMetadata) -> Self {
        Self {
            id: m.id,
            label: m.label,
            folder_id: m.folder_id,
            host: m.host,
            port: m.port,
            user: m.user,
            auth_type: m.auth_type,
            key_path: m.key_path,
            key_id: m.key_id,
            sort_order: m.sort_order,
            notes: m.notes,
            extras: m.extras,
            via_session_id: m.via_session_id,
            via_host: m.via_host,
            via_port: m.via_port,
            via_user: m.via_user,
            updated_at_ms: m.updated_at_ms,
        }
    }
}

/// Update non-credential metadata on a session row without touching
/// the `password` / `key_data` / `passphrase` columns. Lets the
/// edit dialog save a label / host / proxy change without first
/// reading the existing secret bytes back onto the Dart heap.
pub async fn db_sessions_update_metadata(metadata: DbSessionMetadata) -> Result<u32, String> {
    let m: lfs_core::db::sessions::SessionMetadata = metadata.into();
    let res = run_db(move |c| lfs_core::db::sessions::update_metadata(c, &m))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

/// Replace one credential column (`"password"` / `"key_data"` /
/// `"passphrase"`) on a session. Crosses FRB plaintext one direction
/// only (Dart → Rust → DB); pairs with `db_sessions_stage_secrets`
/// for the read direction. Empty `value` clears the slot.
pub async fn db_sessions_set_secret(
    id: String,
    slot: String,
    value: String,
    updated_at_ms: i64,
) -> Result<u32, String> {
    let res = run_db(move |c| {
        lfs_core::db::sessions::set_secret_column(c, &id, &slot, &value, updated_at_ms)
    })
    .await
    .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

/// Copy a saved session row to a new id + label, optionally
/// re-parented under [`target_folder_id`]. Credentials flow column-
/// to-column inside SQLite and never cross the FRB boundary, so the
/// duplicate path no longer carries plaintext on the Dart heap.
pub async fn db_sessions_duplicate(
    src_id: String,
    new_id: String,
    new_label: String,
    target_folder_id: Option<String>,
    now_ms: i64,
) -> Result<(), String> {
    let res = run_db(move |c| {
        lfs_core::db::sessions::duplicate_session(
            c,
            &src_id,
            &new_id,
            &new_label,
            target_folder_id.as_deref(),
            now_ms,
        )
    })
    .await;
    notify_sessions_on_ok(&res);
    res
}

/// FRB mirror of `lfs_core::db::sessions::RestoreSessionInput`.
/// Same field set as `DbSession` but carries `folder_path`
/// instead of `folder_id` — the snapshot caller (undo history)
/// only knows the path, and the post-restore folder tree is
/// re-minted inside the same transaction so any prior id is
/// stale anyway.
#[derive(Debug, Clone)]
pub struct DbRestoreSessionInput {
    pub id: String,
    pub label: String,
    pub folder_path: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<DbRestoreSessionInput> for lfs_core::db::sessions::RestoreSessionInput {
    fn from(d: DbRestoreSessionInput) -> Self {
        Self {
            id: d.id,
            label: d.label,
            folder_path: d.folder_path,
            host: d.host,
            port: d.port,
            user: d.user,
            auth_type: d.auth_type,
            password: d.password,
            key_path: d.key_path,
            key_data: d.key_data,
            key_id: d.key_id,
            passphrase: d.passphrase,
            sort_order: d.sort_order,
            notes: d.notes,
            last_connected_at_ms: d.last_connected_at_ms,
            extras: d.extras,
            via_session_id: d.via_session_id,
            via_host: d.via_host,
            via_port: d.via_port,
            via_user: d.via_user,
            created_at_ms: d.created_at_ms,
            updated_at_ms: d.updated_at_ms,
        }
    }
}

/// Atomic restore from an undo-history snapshot. Wipes live
/// sessions + folders, rebuilds the folder tree from session
/// paths + the bare empty-folder list, re-inserts every session
/// under the freshly-resolved folder id. One transaction.
///
/// Replaces the Dart `SessionStore.restoreSnapshot` orchestration
/// (delete-all sessions + delete-all folders + N× resolveFolderPath
/// + N× upsert + M× resolveFolderPath) with a single FRB call.
pub async fn db_sessions_restore_snapshot(
    sessions: Vec<DbRestoreSessionInput>,
    empty_folder_paths: Vec<String>,
    now_ms: i64,
) -> Result<(), String> {
    let res = tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        let typed: Vec<lfs_core::db::sessions::RestoreSessionInput> =
            sessions.into_iter().map(Into::into).collect();
        db.with_conn_mut(|c| {
            lfs_core::db::sessions::restore_snapshot(c, typed, empty_folder_paths, now_ms)
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db task: {e}"))?;
    notify_sessions_on_ok(&res);
    res
}

/// Composite duplicate — Rust composes label-uniqueness +
/// folder-path resolution + duplicate-insert in one transaction.
/// Returns the new session id. Replaces the multi-step Dart
/// `SessionStore.duplicateSession` orchestration; callers that only
/// know the source id + a target folder path now pay one FRB call
/// instead of three.
pub async fn db_sessions_duplicate_with_path(
    src_id: String,
    target_folder_path: String,
    now_ms: i64,
) -> Result<String, String> {
    let res = tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn_mut(|c| {
            lfs_core::db::sessions::duplicate_with_path(c, &src_id, &target_folder_path, now_ms)
        })
        .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("db task: {e}"))?;
    notify_sessions_on_ok(&res);
    res
}

pub async fn db_sessions_delete_multiple(ids: Vec<String>) -> Result<u32, String> {
    let res = run_db(move |c| lfs_core::db::sessions::delete_multiple(c, &ids))
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_sessions_delete_all() -> Result<u32, String> {
    let res = run_db(lfs_core::db::sessions::delete_all)
        .await
        .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_sessions_move_to_folder(
    session_id: String,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    let res = run_db(move |c| {
        lfs_core::db::sessions::move_to_folder(c, &session_id, folder_id.as_deref(), updated_at_ms)
    })
    .await
    .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

pub async fn db_sessions_move_multiple(
    ids: Vec<String>,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    let res = run_db(move |c| {
        lfs_core::db::sessions::move_multiple(c, &ids, folder_id.as_deref(), updated_at_ms)
    })
    .await
    .map(|n| n as u32);
    notify_sessions_on_ok_when(&res, |n| *n > 0);
    res
}

// ---- known_hosts -------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbKnownHost {
    pub id: i64,
    pub host: String,
    pub port: i64,
    pub key_type: String,
    pub key_base64: String,
    pub added_at_ms: i64,
}

impl From<lfs_core::db::known_hosts::KnownHostRow> for DbKnownHost {
    fn from(r: lfs_core::db::known_hosts::KnownHostRow) -> Self {
        Self {
            id: r.id,
            host: r.host,
            port: r.port,
            key_type: r.key_type,
            key_base64: r.key_base64,
            added_at_ms: r.added_at_ms,
        }
    }
}

pub async fn db_known_hosts_list_all() -> Result<Vec<DbKnownHost>, String> {
    run_db(lfs_core::db::known_hosts::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbKnownHost::from).collect())
}

pub async fn db_known_hosts_get_by_host_port(
    host: String,
    port: i64,
) -> Result<Option<DbKnownHost>, String> {
    run_db(move |c| lfs_core::db::known_hosts::get_by_host_port(c, &host, port))
        .await
        .map(|opt| opt.map(DbKnownHost::from))
}

pub async fn db_known_hosts_upsert_by_host_port(
    host: String,
    port: i64,
    key_type: String,
    key_base64: String,
    added_at_ms: i64,
) -> Result<i64, String> {
    let row_id = run_db(move |c| {
        lfs_core::db::known_hosts::upsert_by_host_port(
            c,
            &host,
            port,
            &key_type,
            &key_base64,
            added_at_ms,
        )
    })
    .await?;
    lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    Ok(row_id)
}

pub async fn db_known_hosts_delete_by_host_port(host: String, port: i64) -> Result<u32, String> {
    let n = run_db(move |c| lfs_core::db::known_hosts::delete_by_host_port(c, &host, port))
        .await
        .map(|n| n as u32)?;
    if n > 0 {
        lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    }
    Ok(n)
}

pub async fn db_known_hosts_clear_all() -> Result<u32, String> {
    let n = run_db(lfs_core::db::known_hosts::clear_all)
        .await
        .map(|n| n as u32)?;
    if n > 0 {
        lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    }
    Ok(n)
}

/// FRB mirror of `lfs_core::known_hosts::ImportSummary`.
#[derive(Debug, Clone)]
pub struct DbKnownHostsImportSummary {
    pub added: i64,
    pub skipped_existing: i64,
    pub skipped_hashed: i64,
}

impl From<lfs_core::known_hosts::ImportSummary> for DbKnownHostsImportSummary {
    fn from(s: lfs_core::known_hosts::ImportSummary) -> Self {
        Self {
            added: s.added,
            skipped_existing: s.skipped_existing,
            skipped_hashed: s.skipped_hashed,
        }
    }
}

/// Bulk-import `content` (LetsFLUTssh + OpenSSH known_hosts wire
/// formats — see `lfs_core::known_hosts_parser::parse_line`)
/// against the running DB. Existing host:port entries are
/// preserved; only fresh rows insert. Emits a single
/// `KnownHostsChanged` bus event when at least one row landed.
pub async fn db_known_hosts_import_from_string(
    content: String,
    now_ms: i64,
) -> Result<DbKnownHostsImportSummary, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        lfs_core::known_hosts::import_from_string(&db, &app.bus, &content, now_ms)
            .map(DbKnownHostsImportSummary::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("known-hosts import task: {e}"))?
}

/// Render every known-hosts row to the LetsFLUTssh wire format
/// (`host:port keytype base64key` per line). Used by `.lfs`
/// archive export.
pub async fn db_known_hosts_export_to_string() -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        lfs_core::known_hosts::export_to_string(&db).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("known-hosts export task: {e}"))?
}

// ---- app_configs -------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbAppConfig {
    pub data: String,
    pub updated_at_ms: i64,
    pub auto_lock_minutes: i64,
}

impl From<lfs_core::db::app_configs::AppConfigRow> for DbAppConfig {
    fn from(r: lfs_core::db::app_configs::AppConfigRow) -> Self {
        Self {
            data: r.data,
            updated_at_ms: r.updated_at_ms,
            auto_lock_minutes: r.auto_lock_minutes,
        }
    }
}

impl From<DbAppConfig> for lfs_core::db::app_configs::AppConfigRow {
    fn from(r: DbAppConfig) -> Self {
        Self {
            data: r.data,
            updated_at_ms: r.updated_at_ms,
            auto_lock_minutes: r.auto_lock_minutes,
        }
    }
}

pub async fn db_app_configs_get() -> Result<Option<DbAppConfig>, String> {
    run_db(lfs_core::db::app_configs::get)
        .await
        .map(|opt| opt.map(DbAppConfig::from))
}

pub async fn db_app_configs_upsert(row: DbAppConfig) -> Result<(), String> {
    let row: lfs_core::db::app_configs::AppConfigRow = row.into();
    run_db(move |c| lfs_core::db::app_configs::upsert(c, &row)).await
}

// ---- snippets ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSnippet {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<lfs_core::db::snippets::SnippetRow> for DbSnippet {
    fn from(r: lfs_core::db::snippets::SnippetRow) -> Self {
        Self {
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

impl From<DbSnippet> for lfs_core::db::snippets::SnippetRow {
    fn from(r: DbSnippet) -> Self {
        Self {
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

pub async fn db_snippets_list_all() -> Result<Vec<DbSnippet>, String> {
    run_db(lfs_core::db::snippets::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSnippet::from).collect())
}

pub async fn db_snippets_upsert(row: DbSnippet) -> Result<(), String> {
    let row: lfs_core::db::snippets::SnippetRow = row.into();
    run_db(move |c| lfs_core::db::snippets::upsert(c, &row)).await
}

pub async fn db_snippets_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::snippets::delete(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_snippets_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::snippets::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_snippets_list_for_session(session_id: String) -> Result<Vec<DbSnippet>, String> {
    run_db(move |c| lfs_core::db::snippets::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbSnippet::from).collect())
}

pub async fn db_session_snippets_link(
    session_id: String,
    snippet_id: String,
) -> Result<(), String> {
    run_db(move |c| lfs_core::db::snippets::link_session_snippet(c, &session_id, &snippet_id)).await
}

pub async fn db_session_snippets_unlink(
    session_id: String,
    snippet_id: String,
) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::snippets::unlink_session_snippet(c, &session_id, &snippet_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_session_snippets_list_ids(session_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::snippets::list_session_snippet_ids(c, &session_id)).await
}

// ---- port_forwards -----------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbPortForwardRule {
    pub id: String,
    pub session_id: String,
    pub kind: String,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub description: String,
    pub enabled: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::port_forwards::PortForwardRuleRow> for DbPortForwardRule {
    fn from(r: lfs_core::db::port_forwards::PortForwardRuleRow) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            kind: r.kind,
            bind_host: r.bind_host,
            bind_port: r.bind_port,
            remote_host: r.remote_host,
            remote_port: r.remote_port,
            description: r.description,
            enabled: r.enabled,
            sort_order: r.sort_order,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbPortForwardRule> for lfs_core::db::port_forwards::PortForwardRuleRow {
    fn from(r: DbPortForwardRule) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            kind: r.kind,
            bind_host: r.bind_host,
            bind_port: r.bind_port,
            remote_host: r.remote_host,
            remote_port: r.remote_port,
            description: r.description,
            enabled: r.enabled,
            sort_order: r.sort_order,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_port_forwards_list_for_session(
    session_id: String,
) -> Result<Vec<DbPortForwardRule>, String> {
    run_db(move |c| lfs_core::db::port_forwards::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbPortForwardRule::from).collect())
}

pub async fn db_port_forwards_upsert(row: DbPortForwardRule) -> Result<(), String> {
    let row: lfs_core::db::port_forwards::PortForwardRuleRow = row.into();
    run_db(move |c| lfs_core::db::port_forwards::upsert(c, &row)).await
}

pub async fn db_port_forwards_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::port_forwards::delete(c, &id))
        .await
        .map(|n| n as u32)
}

// ---- sftp_bookmarks ----------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSftpBookmark {
    pub id: String,
    pub session_id: String,
    pub remote_path: String,
    pub label: String,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::sftp_bookmarks::SftpBookmarkRow> for DbSftpBookmark {
    fn from(r: lfs_core::db::sftp_bookmarks::SftpBookmarkRow) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            remote_path: r.remote_path,
            label: r.label,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbSftpBookmark> for lfs_core::db::sftp_bookmarks::SftpBookmarkRow {
    fn from(r: DbSftpBookmark) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            remote_path: r.remote_path,
            label: r.label,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_sftp_bookmarks_list_for_session(
    session_id: String,
) -> Result<Vec<DbSftpBookmark>, String> {
    run_db(move |c| lfs_core::db::sftp_bookmarks::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbSftpBookmark::from).collect())
}

pub async fn db_sftp_bookmarks_upsert(row: DbSftpBookmark) -> Result<(), String> {
    let row: lfs_core::db::sftp_bookmarks::SftpBookmarkRow = row.into();
    run_db(move |c| lfs_core::db::sftp_bookmarks::upsert(c, &row)).await
}

pub async fn db_sftp_bookmarks_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::sftp_bookmarks::delete(c, &id))
        .await
        .map(|n| n as u32)
}

// ---- tags + M2M --------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbTag {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::tags::TagRow> for DbTag {
    fn from(r: lfs_core::db::tags::TagRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            color: r.color,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbTag> for lfs_core::db::tags::TagRow {
    fn from(r: DbTag) -> Self {
        Self {
            id: r.id,
            name: r.name,
            color: r.color,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_tags_list_all() -> Result<Vec<DbTag>, String> {
    run_db(lfs_core::db::tags::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_tags_upsert(row: DbTag) -> Result<(), String> {
    let row: lfs_core::db::tags::TagRow = row.into();
    run_db(move |c| lfs_core::db::tags::upsert(c, &row)).await
}

pub async fn db_tags_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::delete(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_tags_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::tags::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_tags_list_for_session(session_id: String) -> Result<Vec<DbTag>, String> {
    run_db(move |c| lfs_core::db::tags::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_tags_list_for_folder(folder_id: String) -> Result<Vec<DbTag>, String> {
    run_db(move |c| lfs_core::db::tags::list_for_folder(c, &folder_id))
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_session_tags_link(session_id: String, tag_id: String) -> Result<(), String> {
    run_db(move |c| lfs_core::db::tags::link_session_tag(c, &session_id, &tag_id)).await
}

pub async fn db_session_tags_unlink(session_id: String, tag_id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::unlink_session_tag(c, &session_id, &tag_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_session_tags_list_ids(session_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::tags::list_session_tag_ids(c, &session_id)).await
}

pub async fn db_folder_tags_link(folder_id: String, tag_id: String) -> Result<(), String> {
    run_db(move |c| lfs_core::db::tags::link_folder_tag(c, &folder_id, &tag_id)).await
}

pub async fn db_folder_tags_unlink(folder_id: String, tag_id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::unlink_folder_tag(c, &folder_id, &tag_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_folder_tags_list_ids(folder_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::tags::list_folder_tag_ids(c, &folder_id)).await
}
