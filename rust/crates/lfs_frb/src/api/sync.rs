//! FRB adapter for [`lfs_core::sync`].
//!
//! Three verbs the Dart Settings → Sync panel calls:
//!
//! - [`sync_status`] — synchronous snapshot. Reads through the
//!   config store actor; cheap enough that the panel can pull it
//!   on every `build()` without a state cache.
//! - [`sync_push`] — async. Pushes the encrypted `.lfs` archive
//!   to the configured WebDAV endpoint. The Dart side renders
//!   a typed [`DbSyncResult`] (or a typed error envelope via
//!   [`crate::api::frb_err`]).
//! - [`sync_pull`] — async. Pulls + merges. Same return contract.
//!
//! ## Error wire-shape
//!
//! Maps [`lfs_core::sync::SyncError`] to the canonical
//! [`crate::api::frb_err`] kinds:
//!
//! | Variant | Kind |
//! |---|---|
//! | `Disabled` | `generic` (the UI tooltip renders the localized "sync disabled" text) |
//! | `ConfigInvalid(_)` | `generic` |
//! | `Network(_)` | `webdav` |
//! | `EtagMismatch` | `webdav` (detail = `"etag mismatch"`) |
//! | `Unauthorized` | `webdav` (detail = `"authentication failed"`) |
//! | `ArchiveFutureVersion {..}` | `archive_future_version` |
//!
//! The detail strings are stable wire markers — Dart switches on
//! them when the panel needs to distinguish "pull first" from a
//! generic transport drop.

use lfs_core::sync::{SyncError, SyncResult};

/// Mirror of [`SyncResult`]. The variant tag rides in `kind` so
/// the Dart side reads `result.kind == 'pushed'` without parsing
/// the localized summary.
#[derive(Debug, Clone)]
pub struct DbSyncResult {
    /// One of `pushed` / `pull_applied` / `up_to_date` / `skipped`.
    pub kind: String,
    pub bytes: u64,
    pub sha256: String,
    pub sessions_merged: u32,
    pub keys_merged: u32,
    pub tags_merged: u32,
    pub snippets_merged: u32,
    pub bookmarks_merged: u32,
    pub reason: String,
}

impl From<SyncResult> for DbSyncResult {
    fn from(r: SyncResult) -> Self {
        match r {
            SyncResult::Pushed { bytes, sha256 } => DbSyncResult {
                kind: "pushed".into(),
                bytes,
                sha256,
                sessions_merged: 0,
                keys_merged: 0,
                tags_merged: 0,
                snippets_merged: 0,
                bookmarks_merged: 0,
                reason: String::new(),
            },
            SyncResult::PullApplied {
                sessions_merged,
                keys_merged,
                tags_merged,
                snippets_merged,
                bookmarks_merged,
            } => DbSyncResult {
                kind: "pull_applied".into(),
                bytes: 0,
                sha256: String::new(),
                sessions_merged,
                keys_merged,
                tags_merged,
                snippets_merged,
                bookmarks_merged,
                reason: String::new(),
            },
            SyncResult::UpToDate => DbSyncResult {
                kind: "up_to_date".into(),
                bytes: 0,
                sha256: String::new(),
                sessions_merged: 0,
                keys_merged: 0,
                tags_merged: 0,
                snippets_merged: 0,
                bookmarks_merged: 0,
                reason: String::new(),
            },
            SyncResult::Skipped { reason } => DbSyncResult {
                kind: "skipped".into(),
                bytes: 0,
                sha256: String::new(),
                sessions_merged: 0,
                keys_merged: 0,
                tags_merged: 0,
                snippets_merged: 0,
                bookmarks_merged: 0,
                reason,
            },
        }
    }
}

/// Mirror of [`lfs_core::sync::SyncStatus`].
#[derive(Debug, Clone, Default)]
pub struct DbSyncStatus {
    pub enabled: bool,
    pub last_pushed_at_ms: i64,
    pub last_pulled_at_ms: i64,
    pub last_error: Option<String>,
}

/// Synchronous snapshot — see [`lfs_core::sync::status`] for the
/// state read. Cheap (no I/O, no DB hit), safe to call from a
/// Riverpod `build()`.
#[flutter_rust_bridge::frb(sync)]
pub fn sync_status() -> DbSyncStatus {
    let s = lfs_core::sync::status();
    DbSyncStatus {
        enabled: s.enabled,
        last_pushed_at_ms: s.last_pushed_at_ms,
        last_pulled_at_ms: s.last_pulled_at_ms,
        last_error: s.last_error,
    }
}

/// Push the encrypted `.lfs` archive to the configured WebDAV
/// remote. See [`lfs_core::sync::push`] for the full flow.
pub async fn sync_push() -> Result<DbSyncResult, String> {
    lfs_core::sync::push()
        .await
        .map(DbSyncResult::from)
        .map_err(sync_err_to_wire)
}

/// Pull the latest `.lfs` from the remote and merge it into the
/// local DB. See [`lfs_core::sync::pull`].
///
/// Pull mutates `sessions` / `ssh_keys` / `tags` / `snippets` /
/// `bookmarks` (per the merge driver); publish on every store
/// topic so each Dart-side stream re-fetches the canonical
/// post-merge snapshot. Skipped / up-to-date results don't fan
/// out events — nothing changed.
pub async fn sync_pull() -> Result<DbSyncResult, String> {
    let res = lfs_core::sync::pull()
        .await
        .map(DbSyncResult::from)
        .map_err(sync_err_to_wire);
    if let Ok(r) = &res {
        let touched = r.sessions_merged > 0
            || r.keys_merged > 0
            || r.tags_merged > 0
            || r.snippets_merged > 0
            || r.bookmarks_merged > 0;
        if touched {
            let app = lfs_core::app::instance();
            lfs_core::sessions::reload_and_notify(&app);
            lfs_core::keys::notify_changed(&app);
            lfs_core::known_hosts::notify_changed(&app);
        }
    }
    res
}

fn sync_err_to_wire(e: SyncError) -> String {
    use crate::api::frb_err::{kind, wire};
    match e {
        SyncError::Disabled => wire(kind::GENERIC, "sync disabled"),
        SyncError::ConfigInvalid(s) => wire(kind::GENERIC, &format!("config invalid: {s}")),
        SyncError::Network(s) => wire(kind::WEBDAV, &s),
        SyncError::EtagMismatch => wire(kind::WEBDAV, "etag mismatch"),
        SyncError::Unauthorized => wire(kind::WEBDAV, "authentication failed"),
        SyncError::ArchiveFutureVersion { found, supported } => wire(
            kind::ARCHIVE_FUTURE_VERSION,
            &format!("found={found},supported={supported}"),
        ),
    }
}

/// Read the live [`lfs_core::config::SyncConfig`] off the config
/// store actor so the Settings UI can render the fields without
/// hand-decoding the canonical JSON. Wire shape mirrors
/// `SyncConfig` field-for-field plus the secret-id pointers; the
/// actual secrets live in [`lfs_core::secrets::SecretStore`] and
/// never cross the FRB boundary.
#[derive(Debug, Clone, Default)]
pub struct DbSyncConfig {
    pub enabled: bool,
    pub webdav_url: String,
    pub webdav_username: String,
    pub webdav_password_ref: String,
    pub webdav_auth_method: String,
    pub passphrase_ref: String,
    pub remote_path: String,
    pub last_pushed_at_ms: i64,
    pub last_pulled_at_ms: i64,
    pub last_pushed_sha256: String,
    pub last_pushed_etag: String,
    pub last_pulled_etag: String,
    pub last_pulled_sha256: String,
}

impl From<lfs_core::config::SyncConfig> for DbSyncConfig {
    fn from(c: lfs_core::config::SyncConfig) -> Self {
        Self {
            enabled: c.enabled,
            webdav_url: c.webdav_url,
            webdav_username: c.webdav_username,
            webdav_password_ref: c.webdav_password_ref,
            webdav_auth_method: c.webdav_auth_method,
            passphrase_ref: c.passphrase_ref,
            remote_path: c.remote_path,
            last_pushed_at_ms: c.last_pushed_at_ms,
            last_pulled_at_ms: c.last_pulled_at_ms,
            last_pushed_sha256: c.last_pushed_sha256,
            last_pushed_etag: c.last_pushed_etag,
            last_pulled_etag: c.last_pulled_etag,
            last_pulled_sha256: c.last_pulled_sha256,
        }
    }
}

impl From<DbSyncConfig> for lfs_core::config::SyncConfig {
    fn from(c: DbSyncConfig) -> Self {
        Self {
            enabled: c.enabled,
            webdav_url: c.webdav_url,
            webdav_username: c.webdav_username,
            webdav_password_ref: c.webdav_password_ref,
            webdav_auth_method: c.webdav_auth_method,
            passphrase_ref: c.passphrase_ref,
            remote_path: c.remote_path,
            last_pushed_at_ms: c.last_pushed_at_ms,
            last_pulled_at_ms: c.last_pulled_at_ms,
            last_pushed_sha256: c.last_pushed_sha256,
            last_pushed_etag: c.last_pushed_etag,
            last_pulled_etag: c.last_pulled_etag,
            last_pulled_sha256: c.last_pulled_sha256,
        }
    }
}

/// Snapshot the persisted [`SyncConfig`]. Sync — reads from the
/// config store actor; cheap enough to call from a Riverpod
/// `build()`. Returns the default shape (`enabled = false`) when
/// the store is not yet initialised.
#[flutter_rust_bridge::frb(sync)]
pub fn sync_config_get() -> DbSyncConfig {
    lfs_core::config_store::instance()
        .get_app_config()
        .map(|c| c.sync.into())
        .unwrap_or_default()
}

/// Persist a new [`SyncConfig`] through the config store actor.
/// Returns `Err` when the store has not been initialised yet
/// (cold-start window). The disk write is debounced to match
/// the rest of the actor's writes (slider drag / fast typing
/// collapses to one I/O).
pub fn sync_config_set(value: DbSyncConfig) -> Result<(), String> {
    lfs_core::config_store::instance()
        .update_sync(value.into())
        .map_err(|e| crate::api::frb_err::wire(crate::api::frb_err::kind::GENERIC, &e))
}

/// Stage `bytes` into the [`lfs_core::secrets::SecretStore`]
/// under `id`. The Settings UI uses this to push the WebDAV
/// password / sync passphrase into the SecretStore so the
/// orchestrator can read them by id without the plaintext
/// crossing the FRB boundary a second time.
pub fn sync_secret_put(id: String, bytes: Vec<u8>) -> Result<(), String> {
    lfs_core::app::instance().secrets.put(&id, &bytes);
    Ok(())
}

/// True when a secret has been staged under `id`. The Settings
/// UI uses this to render the "configured" / "not configured"
/// hint without reading the secret bytes.
#[flutter_rust_bridge::frb(sync)]
pub fn sync_secret_has(id: String) -> bool {
    lfs_core::app::instance().secrets.has(&id)
}

/// Drop the secret under `id`. Idempotent — calling on a
/// missing id is a no-op. Used when the user clears the
/// "WebDAV password" / "Sync passphrase" field in Settings.
pub fn sync_secret_drop(id: String) -> Result<(), String> {
    lfs_core::app::instance().secrets.drop_id(&id);
    Ok(())
}
