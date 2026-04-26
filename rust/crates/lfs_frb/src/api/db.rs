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
    run_db(move |c| lfs_core::db::folders::upsert(c, &row)).await
}

pub async fn db_folders_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::folders::delete(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::folders::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_toggle_collapsed(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::folders::toggle_collapsed(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_update_name_parent(
    id: String,
    name: String,
    parent_id: Option<String>,
) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::folders::update_name_parent(c, &id, &name, parent_id.as_deref()))
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_delete_recursive(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::folders::delete_recursive(c, &id))
        .await
        .map(|n| n as u32)
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
    run_db(move |c| lfs_core::db::sessions::upsert(c, &row)).await
}

pub async fn db_sessions_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::sessions::delete(c, &id))
        .await
        .map(|n| n as u32)
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

pub async fn db_sessions_delete_multiple(ids: Vec<String>) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::sessions::delete_multiple(c, &ids))
        .await
        .map(|n| n as u32)
}

pub async fn db_sessions_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::sessions::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_sessions_move_to_folder(
    session_id: String,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    run_db(move |c| {
        lfs_core::db::sessions::move_to_folder(c, &session_id, folder_id.as_deref(), updated_at_ms)
    })
    .await
    .map(|n| n as u32)
}

pub async fn db_sessions_move_multiple(
    ids: Vec<String>,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    run_db(move |c| {
        lfs_core::db::sessions::move_multiple(c, &ids, folder_id.as_deref(), updated_at_ms)
    })
    .await
    .map(|n| n as u32)
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
    run_db(move |c| {
        lfs_core::db::known_hosts::upsert_by_host_port(
            c,
            &host,
            port,
            &key_type,
            &key_base64,
            added_at_ms,
        )
    })
    .await
}

pub async fn db_known_hosts_delete_by_host_port(host: String, port: i64) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::known_hosts::delete_by_host_port(c, &host, port))
        .await
        .map(|n| n as u32)
}

pub async fn db_known_hosts_clear_all() -> Result<u32, String> {
    run_db(lfs_core::db::known_hosts::clear_all)
        .await
        .map(|n| n as u32)
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
