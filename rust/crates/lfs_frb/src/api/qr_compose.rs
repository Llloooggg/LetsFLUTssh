//! FRB adapter for `lfs_core::qr_compose` — typed QR-payload
//! composer that the `unified_export_controller` live size
//! estimator routes through (Decision 6 / E2 in
//! `docs/RUST_MIGRATION_REMAINING.md`).
//!
//! Sync — composition is a few hundred clones + a deflate pass,
//! sub-millisecond on realistic export selections (≤100 sessions
//! with optional config + tags + snippets). The controller calls
//! the size estimator on every checkbox toggle from synchronous
//! Riverpod-driven UI rebuilds, so the no-async-hop overhead is
//! load-bearing for the live "fits in QR" gauge.

use lfs_core::qr_compose;

use crate::api::archive::DbQrExportOptions;

/// FRB mirror of `qr_compose::QrSessionInput`. Folder paths,
/// passwords, key bytes, key-id refs are all pre-resolved by the
/// Dart caller (matches the in-memory composition the controller
/// already does for the dummy-session estimator path).
#[derive(Debug, Clone)]
pub struct DbQrSessionInput {
    pub id: String,
    pub label: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_id: Option<String>,
    pub key_data: String,
    pub folder_path: String,
}

impl From<DbQrSessionInput> for qr_compose::QrSessionInput {
    fn from(d: DbQrSessionInput) -> Self {
        Self {
            id: d.id,
            label: d.label,
            host: d.host,
            port: d.port,
            user: d.user,
            auth_type: d.auth_type,
            password: d.password,
            key_id: d.key_id,
            key_data: d.key_data,
            folder_path: d.folder_path,
        }
    }
}

/// FRB mirror of `qr_compose::QrTagInput`.
#[derive(Debug, Clone)]
pub struct DbQrTagInput {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
}

impl From<DbQrTagInput> for qr_compose::QrTagInput {
    fn from(d: DbQrTagInput) -> Self {
        Self {
            id: d.id,
            name: d.name,
            color: d.color,
        }
    }
}

/// FRB mirror of `qr_compose::QrSnippetInput`.
#[derive(Debug, Clone)]
pub struct DbQrSnippetInput {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
}

impl From<DbQrSnippetInput> for qr_compose::QrSnippetInput {
    fn from(d: DbQrSnippetInput) -> Self {
        Self {
            id: d.id,
            title: d.title,
            command: d.command,
            description: d.description,
        }
    }
}

/// FRB mirror of `qr_compose::QrManagerKeyEntry`.
#[derive(Debug, Clone)]
pub struct DbQrManagerKeyEntry {
    pub id: String,
    pub label: String,
    pub key_type: String,
    pub public_key: String,
    pub private_key: String,
}

impl From<DbQrManagerKeyEntry> for qr_compose::QrManagerKeyEntry {
    fn from(d: DbQrManagerKeyEntry) -> Self {
        Self {
            id: d.id,
            label: d.label,
            key_type: d.key_type,
            public_key: d.public_key,
            private_key: d.private_key,
        }
    }
}

/// FRB mirror of `qr_compose::QrSessionTagLink`.
#[derive(Debug, Clone)]
pub struct DbQrSessionTagLink {
    pub session_id: String,
    pub tag_id: String,
}

impl From<DbQrSessionTagLink> for qr_compose::QrSessionTagLink {
    fn from(d: DbQrSessionTagLink) -> Self {
        Self {
            session_id: d.session_id,
            tag_id: d.tag_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrFolderTagLink`.
#[derive(Debug, Clone)]
pub struct DbQrFolderTagLink {
    pub folder_path: String,
    pub tag_id: String,
}

impl From<DbQrFolderTagLink> for qr_compose::QrFolderTagLink {
    fn from(d: DbQrFolderTagLink) -> Self {
        Self {
            folder_path: d.folder_path,
            tag_id: d.tag_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrSessionSnippetLink`.
#[derive(Debug, Clone)]
pub struct DbQrSessionSnippetLink {
    pub session_id: String,
    pub snippet_id: String,
}

impl From<DbQrSessionSnippetLink> for qr_compose::QrSessionSnippetLink {
    fn from(d: DbQrSessionSnippetLink) -> Self {
        Self {
            session_id: d.session_id,
            snippet_id: d.snippet_id,
        }
    }
}

/// FRB mirror of `qr_compose::QrPayloadInput`. Crosses the
/// boundary as a flat struct so the Dart caller can build it
/// inline from the export-dialog selections.
#[derive(Debug, Clone)]
pub struct DbQrPayloadInput {
    pub options: DbQrExportOptions,
    pub sessions: Vec<DbQrSessionInput>,
    pub empty_folders: Vec<String>,
    pub config_json: Option<String>,
    pub known_hosts: String,
    pub tags: Vec<DbQrTagInput>,
    pub session_tags: Vec<DbQrSessionTagLink>,
    pub folder_tags: Vec<DbQrFolderTagLink>,
    pub snippets: Vec<DbQrSnippetInput>,
    pub session_snippets: Vec<DbQrSessionSnippetLink>,
    pub manager_key_entries: Vec<DbQrManagerKeyEntry>,
}

impl From<DbQrPayloadInput> for qr_compose::QrPayloadInput {
    fn from(d: DbQrPayloadInput) -> Self {
        Self {
            options: lfs_core::archive::QrExportOptions {
                include_sessions: d.options.include_sessions,
                include_config: d.options.include_config,
                include_known_hosts: d.options.include_known_hosts,
                include_passwords: d.options.include_passwords,
                include_embedded_keys: d.options.include_embedded_keys,
                include_manager_keys: d.options.include_manager_keys,
                include_all_manager_keys: d.options.include_all_manager_keys,
                include_tags: d.options.include_tags,
                include_snippets: d.options.include_snippets,
            },
            sessions: d.sessions.into_iter().map(Into::into).collect(),
            empty_folders: d.empty_folders,
            config_json: d.config_json,
            known_hosts: d.known_hosts,
            tags: d.tags.into_iter().map(Into::into).collect(),
            session_tags: d.session_tags.into_iter().map(Into::into).collect(),
            folder_tags: d.folder_tags.into_iter().map(Into::into).collect(),
            snippets: d.snippets.into_iter().map(Into::into).collect(),
            session_snippets: d.session_snippets.into_iter().map(Into::into).collect(),
            manager_key_entries: d.manager_key_entries.into_iter().map(Into::into).collect(),
        }
    }
}

/// Compose the v4 payload + deflate + base64url and return the
/// byte count. Same wire shape + alphabet as
/// `db_export_qr_payload` (production export); both producers
/// route through `lfs_core::qr_compose::compose_qr_payload`.
///
/// Used by the Dart `unified_export_controller` for the live
/// "fits in QR" gauge — single sync FRB call replaces the
/// per-toggle Dart-side JSON build + Rust deflate round-trip.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_estimate_export_size(input: DbQrPayloadInput) -> u32 {
    qr_compose::compose_and_size(&input.into())
}
