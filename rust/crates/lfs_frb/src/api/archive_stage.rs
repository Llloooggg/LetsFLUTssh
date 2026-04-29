//! FRB adapter for `lfs_core::archive_stage`.
//!
//! Sync — each helper is a `serde_json` build over a small in-memory
//! `Vec` (typical import has tens of sessions / a handful of keys),
//! sub-millisecond per call. The Dart caller composes its
//! `DbStagedImport` envelope from the returned JSON-strings then
//! hands the envelope to `db_import_stage` for the actual sqlite-
//! transactional apply.

use lfs_core::archive_stage::{
    self, StagedKeyImport, StagedSessionImport, StagedSnippetImport, StagedTagImport,
};

/// FRB mirror of `archive_stage::StagedSessionImport`.
///
/// Field names + ordering match the Rust side exactly so the
/// FRB-generated Dart DTO drops straight into the
/// `_stageFromResult` call site.
#[derive(Debug, Clone)]
pub struct DbStagedSessionImport {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub passphrase: String,
    pub key_id: Option<String>,
    pub extras_json: String,
    pub via_session_id: Option<String>,
    pub via_override_host: Option<String>,
    pub via_override_port: Option<i64>,
    pub via_override_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<DbStagedSessionImport> for StagedSessionImport {
    fn from(d: DbStagedSessionImport) -> Self {
        Self {
            id: d.id,
            label: d.label,
            folder: d.folder,
            host: d.host,
            port: d.port,
            user: d.user,
            auth_type: d.auth_type,
            password: d.password,
            key_path: d.key_path,
            key_data: d.key_data,
            passphrase: d.passphrase,
            key_id: d.key_id,
            extras_json: d.extras_json,
            via_session_id: d.via_session_id,
            via_override_host: d.via_override_host,
            via_override_port: d.via_override_port,
            via_override_user: d.via_override_user,
            created_at_ms: d.created_at_ms,
            updated_at_ms: d.updated_at_ms,
        }
    }
}

/// FRB mirror of `archive_stage::StagedKeyImport`.
#[derive(Debug, Clone)]
pub struct DbStagedKeyImport {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
}

impl From<DbStagedKeyImport> for StagedKeyImport {
    fn from(d: DbStagedKeyImport) -> Self {
        Self {
            id: d.id,
            label: d.label,
            private_key: d.private_key,
            public_key: d.public_key,
            key_type: d.key_type,
            is_generated: d.is_generated,
            created_at_ms: d.created_at_ms,
        }
    }
}

/// FRB mirror of `archive_stage::StagedTagImport`.
#[derive(Debug, Clone)]
pub struct DbStagedTagImport {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at_ms: i64,
}

impl From<DbStagedTagImport> for StagedTagImport {
    fn from(d: DbStagedTagImport) -> Self {
        Self {
            id: d.id,
            name: d.name,
            color: d.color,
            created_at_ms: d.created_at_ms,
        }
    }
}

/// FRB mirror of `archive_stage::StagedSnippetImport`.
#[derive(Debug, Clone)]
pub struct DbStagedSnippetImport {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<DbStagedSnippetImport> for StagedSnippetImport {
    fn from(d: DbStagedSnippetImport) -> Self {
        Self {
            id: d.id,
            title: d.title,
            command: d.command,
            description: d.description,
            created_at_ms: d.created_at_ms,
            updated_at_ms: d.updated_at_ms,
        }
    }
}

/// Serialise a session list to the JSON-string envelope the apply
/// driver consumes (`DbStagedImport.sessions_json`). Empty input
/// returns `None` so the caller can pass it straight through.
#[flutter_rust_bridge::frb(sync)]
pub fn archive_stage_sessions_to_json(rows: Vec<DbStagedSessionImport>) -> Option<String> {
    let typed: Vec<StagedSessionImport> = rows.into_iter().map(Into::into).collect();
    archive_stage::stage_sessions_to_json(&typed)
}

/// Same shape for manager keys (`DbStagedImport.keys_json`).
#[flutter_rust_bridge::frb(sync)]
pub fn archive_stage_keys_to_json(rows: Vec<DbStagedKeyImport>) -> Option<String> {
    let typed: Vec<StagedKeyImport> = rows.into_iter().map(Into::into).collect();
    archive_stage::stage_keys_to_json(&typed)
}

/// Same shape for tags (`DbStagedImport.tags_json`).
#[flutter_rust_bridge::frb(sync)]
pub fn archive_stage_tags_to_json(rows: Vec<DbStagedTagImport>) -> Option<String> {
    let typed: Vec<StagedTagImport> = rows.into_iter().map(Into::into).collect();
    archive_stage::stage_tags_to_json(&typed)
}

/// Same shape for snippets (`DbStagedImport.snippets_json`).
#[flutter_rust_bridge::frb(sync)]
pub fn archive_stage_snippets_to_json(rows: Vec<DbStagedSnippetImport>) -> Option<String> {
    let typed: Vec<StagedSnippetImport> = rows.into_iter().map(Into::into).collect();
    archive_stage::stage_snippets_to_json(&typed)
}
