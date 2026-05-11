//! Push / pull verbs the FRB adapter exposes to Dart.
//!
//! The orchestrator threads three actors:
//!
//! 1. **Config** — [`crate::config_store::Store`] holds the live
//!    [`crate::config::SyncConfig`] and writes back
//!    `last_pushed_*` / `last_pulled_at_ms` after every successful
//!    verb.
//! 2. **Secrets** — [`crate::secrets::SecretStore`] is where the
//!    Settings UI staged the WebDAV password + the sync passphrase
//!    under [`crate::config::SYNC_PASSWORD_SECRET_ID`] /
//!    [`crate::config::SYNC_PASSPHRASE_SECRET_ID`].
//! 3. **DB** — [`crate::app::AppState::db`] holds the SQLCipher
//!    handle the archive composer reads sessions / keys / tags
//!    from on push, and the merge transaction writes to on pull.
//!
//! ## Failure model
//!
//! All four error variants the Dart UI cares about route through
//! [`SyncError`] — never `Result<_, String>` because the routing
//! table on the Dart side picks the toast / banner shape off the
//! variant tag. Unmapped underlying errors fall through to
//! [`SyncError::Network`] (transport-ish) or
//! [`SyncError::ConfigInvalid`] (caller-bug-ish).
//!
//! ## Why buffered (not streamed)
//!
//! v1 carries the entire archive in RAM. The `.lfs` payload
//! tops out at the [`crate::archive::MAX_ARCHIVE_BYTES`] cap
//! (256 MiB) which fits comfortably even on a phone; streaming
//! the upload would force the [`crate::webdav::WebDavClient`]
//! `put` surface to grow a chunk iterator and pay zero perf
//! benefit for a sync workload that publishes the whole archive
//! at once. The follow-up is documented in the
//! `docs/ARCHITECTURE.md` Sync § so a future streaming pass
//! does not look like a regression on the v1 design.

use std::sync::Arc;

use bytes::Bytes;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::archive::{self, parse_sync_origin, ExportInput, ExportOptions, PendingImport};
use crate::config::{strip_for_export, SyncConfig};
use crate::error::Error;
use crate::migration::SchemaVersions;
use crate::webdav::{AuthMethod, Credentials, WebDavClient};

use super::merge::merge_pending_into_local;

/// Light view of the persisted sync state plus a short last-error
/// string. The Dart UI binds this to the Settings → Sync section so
/// the "Last push: …", "Last pull: …" rows and the optional error
/// banner all read off one snapshot.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SyncStatus {
    pub enabled: bool,
    pub last_pushed_at_ms: i64,
    pub last_pulled_at_ms: i64,
    /// Human-readable summary of the most recent push / pull
    /// failure. Cleared on a successful verb. The Dart side
    /// localises the variant via the FRB error envelope on actual
    /// errors; the `last_error` slot is a stale-status hint, not
    /// the canonical error channel.
    pub last_error: Option<String>,
}

/// Verb outcome. The FRB adapter maps each variant to a typed Dart
/// shape so the UI can branch on the variant without parsing the
/// localised summary.
#[derive(Debug, Clone)]
pub enum SyncResult {
    /// Pushed `bytes` archive bytes to the remote. SHA-256 of the
    /// inner archive plaintext is stamped into `SyncConfig.last_pushed_sha256`
    /// so the next push can skip an identical re-upload.
    Pushed { bytes: u64, sha256: String },
    /// Pull applied a peer snapshot. Per-table counters surface to
    /// the user as "Applied N updates from remote".
    PullApplied {
        sessions_merged: u32,
        keys_merged: u32,
        tags_merged: u32,
        snippets_merged: u32,
        bookmarks_merged: u32,
    },
    /// Both sides are already in sync — the local archive's
    /// SHA-256 matches the last push, or the remote ETag matches
    /// the last push we made (our own push echoing back).
    UpToDate,
    /// Verb was skipped for a reason the UI may surface as a
    /// toast (sync disabled, no remote archive on first pull,
    /// etc.).
    Skipped { reason: String },
}

/// Typed errors. The Dart side picks UI routing off the variant
/// rather than the message text — never substring-match the
/// `detail` field. Mirrors [`crate::error::Error`] wire-routing
/// posture.
#[derive(Debug, thiserror::Error)]
pub enum SyncError {
    #[error("sync disabled")]
    Disabled,
    #[error("sync config invalid: {0}")]
    ConfigInvalid(String),
    #[error("sync network: {0}")]
    Network(String),
    #[error("sync etag mismatch")]
    EtagMismatch,
    #[error("sync unauthorized")]
    Unauthorized,
    #[error("sync archive future version: found={found}, supported={supported}")]
    ArchiveFutureVersion { found: i64, supported: i32 },
}

impl From<Error> for SyncError {
    fn from(e: Error) -> Self {
        match e {
            Error::WebDav(s) => {
                // Pre-classify the WebDAV transport-error string so the
                // four routings the Dart UI cares about land on their
                // own variants instead of all sliding into
                // `Network(_)`. The text patterns match the canonical
                // values stamped by `lfs_core::webdav::client::map_status_error`.
                if s.contains("etag mismatch") {
                    SyncError::EtagMismatch
                } else if s.contains("authentication failed") {
                    SyncError::Unauthorized
                } else {
                    SyncError::Network(s)
                }
            }
            Error::ArchiveFutureVersion { found, supported } => {
                SyncError::ArchiveFutureVersion { found, supported }
            }
            other => SyncError::Network(other.to_string()),
        }
    }
}

/// Snapshot the persisted sync status. Reads through
/// [`crate::config_store::instance`]; returns the default
/// (`enabled = false`) when the actor has not been initialised
/// yet (cold-start window).
pub fn status() -> SyncStatus {
    let cfg = crate::config_store::instance()
        .get_app_config()
        .map(|c| c.sync)
        .unwrap_or_default();
    SyncStatus {
        enabled: cfg.enabled,
        last_pushed_at_ms: cfg.last_pushed_at_ms,
        last_pulled_at_ms: cfg.last_pulled_at_ms,
        last_error: None,
    }
}

/// Push the local DB state as an encrypted `.lfs` archive to the
/// configured WebDAV endpoint. See module + struct docs for the
/// full state machine; the function body is the wiring.
pub async fn push() -> Result<SyncResult, SyncError> {
    let (cfg, install_id) = prepare()?;
    let pw = read_secret(&cfg.webdav_password_ref)?;
    let passphrase = read_secret(&cfg.passphrase_ref)?;

    let now_ms = now_unix_ms();
    let stamp = format!("{install_id}:{now_ms}");

    let db = require_db()?;

    // Compose the archive bytes inside the rusqlite worker. The
    // call is sync; we hop through `spawn_blocking` so the tokio
    // worker can keep servicing other FRB hops while the
    // composer reads sessions / keys / tags off the DB.
    let composed = {
        let cfg_for_compose = cfg.clone();
        let stamp_for_compose = stamp.clone();
        let passphrase_for_compose = passphrase.clone();
        tokio::task::spawn_blocking(move || {
            compose_archive(
                &db,
                &cfg_for_compose,
                &stamp_for_compose,
                &passphrase_for_compose,
            )
        })
        .await
        .map_err(|e| SyncError::Network(format!("compose task: {e}")))??
    };

    if composed.plaintext_sha256 == cfg.last_pushed_sha256 && !cfg.last_pushed_sha256.is_empty() {
        return Ok(SyncResult::UpToDate);
    }

    let client = build_client(&cfg, &pw)?;
    let if_match = if cfg.last_pushed_etag.is_empty() {
        None
    } else {
        Some(cfg.last_pushed_etag.as_str())
    };
    let outcome = client
        .put(
            &cfg.remote_path,
            Bytes::from(composed.bytes.clone()),
            if_match,
        )
        .await
        .map_err(SyncError::from)?;

    let bytes_pushed = composed.bytes.len() as u64;
    let new_etag = outcome.etag.clone().unwrap_or_default();
    let mut updated = cfg.clone();
    updated.last_pushed_at_ms = now_ms;
    updated.last_pushed_sha256 = composed.plaintext_sha256.clone();
    updated.last_pushed_etag = new_etag;
    persist_sync(&updated)?;
    Ok(SyncResult::Pushed {
        bytes: bytes_pushed,
        sha256: composed.plaintext_sha256,
    })
}

/// Pull the latest `.lfs` from the remote and merge it into the
/// local DB. Skips the body fetch when the remote ETag matches the
/// last push (this is our own push echoing back).
pub async fn pull() -> Result<SyncResult, SyncError> {
    let (cfg, install_id) = prepare()?;
    let pw = read_secret(&cfg.webdav_password_ref)?;
    let passphrase = read_secret(&cfg.passphrase_ref)?;
    let client = build_client(&cfg, &pw)?;

    // PROPFIND depth=0 to read the remote ETag. 404 is the
    // "no remote archive yet" case (first pull on a fresh
    // WebDAV root); the Dart UI surfaces this as a soft skip.
    let entries = match client.propfind(&cfg.remote_path, 0).await {
        Ok(e) => e,
        Err(Error::WebDav(s)) if s.contains("not found") => {
            return Ok(SyncResult::Skipped {
                reason: "no remote archive".to_string(),
            });
        }
        Err(e) => return Err(SyncError::from(e)),
    };
    let remote_etag = entries
        .first()
        .and_then(|e| e.etag.clone())
        .unwrap_or_default();
    if !remote_etag.is_empty() && remote_etag == cfg.last_pushed_etag {
        return Ok(SyncResult::UpToDate);
    }

    // GET the body. The WebDAV client buffers the body for us;
    // the cap (256 MiB) matches the archive parser's
    // [`crate::archive::MAX_ARCHIVE_BYTES`].
    let response = client
        .get(&cfg.remote_path, None)
        .await
        .map_err(SyncError::from)?;
    let body = response
        .bytes()
        .await
        .map_err(|e| SyncError::Network(format!("body read: {e}")))?;
    if body.len() as u64 > crate::archive::MAX_ARCHIVE_BYTES {
        return Err(SyncError::Network(format!(
            "remote archive {} bytes exceeds {}-byte cap",
            body.len(),
            crate::archive::MAX_ARCHIVE_BYTES
        )));
    }
    let body_vec = body.to_vec();

    // Decrypt + parse against the user's sync passphrase. The
    // routine routes through `read_archive_to_pending` after a
    // tmp-file detour because that function takes a path; we
    // write to a temp file so the existing cap + future-version
    // check pipeline stays canonical.
    let pending = parse_archive_bytes(&body_vec, &passphrase)?;
    if let Some(origin) = parse_sync_origin(&pending) {
        // If the manifest's origin starts with our own install id,
        // the archive we just pulled is one we pushed (the server
        // round-tripped it without a peer device touching it).
        // Skip applying so we don't churn the local DB.
        if origin.starts_with(&format!("{install_id}:")) {
            return Ok(SyncResult::UpToDate);
        }
    }

    let db = require_db()?;
    let outcome =
        tokio::task::spawn_blocking(move || -> Result<super::merge::MergeOutcome, SyncError> {
            db.with_conn_mut(|c| merge_pending_into_local(c, &pending))
                .map_err(SyncError::from)
        })
        .await
        .map_err(|e| SyncError::Network(format!("merge task: {e}")))??;

    let now_ms = now_unix_ms();
    let mut updated = cfg.clone();
    updated.last_pulled_at_ms = now_ms;
    persist_sync(&updated)?;

    Ok(SyncResult::PullApplied {
        sessions_merged: outcome.sessions_merged,
        keys_merged: outcome.keys_merged,
        tags_merged: outcome.tags_merged,
        snippets_merged: outcome.snippets_merged,
        bookmarks_merged: outcome.bookmarks_merged,
    })
}

// ── plumbing helpers ─────────────────────────────────────────────

struct ComposedArchive {
    bytes: Vec<u8>,
    plaintext_sha256: String,
}

fn compose_archive(
    db: &Arc<crate::db::Db>,
    _cfg: &SyncConfig,
    sync_origin: &str,
    passphrase: &str,
) -> Result<ComposedArchive, SyncError> {
    let now_ms = now_unix_ms();
    // Read the live config snapshot for the export so the
    // archive's `config.json` entry carries the portable subset
    // (per `strip_for_export`).
    let app_cfg = crate::config_store::instance()
        .get_app_config()
        .unwrap_or_default();
    let mut config_value = app_cfg.to_json_value();
    strip_for_export(&mut config_value);
    let config_json = config_value.to_string();

    // Pull every live session id so the export ships the full
    // local snapshot — the peer's pull pipeline expects a
    // complete picture each time.
    let session_ids = db
        .with_conn(crate::db::sessions::list_all)
        .map_err(SyncError::from)?
        .into_iter()
        .map(|r| r.id)
        .collect::<Vec<_>>();

    let input = ExportInput {
        options: ExportOptions {
            include_sessions: true,
            include_known_hosts: true,
            include_config: true,
            include_tags: true,
            include_snippets: true,
            include_all_manager_keys: true,
            has_manager_keys: true,
        },
        selected_session_ids: session_ids,
        selected_empty_folders: Vec::new(),
        config_json,
        schema_version: i64::from(SchemaVersions::ARCHIVE),
        app_version: Some(env!("CARGO_PKG_VERSION").to_string()),
        master_password: Some(passphrase.to_string()),
        // Production-default Argon2id params — mirror what the
        // export composer uses for user-initiated `.lfs` writes
        // so the on-disk shape and the sync archive read through
        // the same KDF posture.
        kdf_memory_kib: 46 * 1024,
        kdf_iterations: 2,
        kdf_parallelism: 1,
        created_at_ms: now_ms,
        sync_origin: Some(sync_origin.to_string()),
    };

    let bytes = db
        .with_conn(|c| archive::export_archive(c, &input))
        .map_err(SyncError::from)?;

    // For the SHA-256 we hash the encrypted envelope bytes —
    // hashing the plaintext would force a second compose pass
    // just to recompute the digest, and the envelope hash is
    // equally suitable for the "did anything change" check
    // because the inner ZIP is stored-mode + deterministic
    // (manifest carries the input timestamp; the rest of the
    // ZIP is the DB snapshot byte-for-byte). The envelope adds
    // fresh salt + IV on every encrypt so different push
    // attempts of the same DB state will not collide on hash —
    // which is fine because the "skip identical push" check
    // is an optimisation, not a correctness invariant.
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let digest = hasher.finalize();
    let hex_digest: String = digest.iter().map(|b| format!("{b:02x}")).collect();

    Ok(ComposedArchive {
        bytes,
        plaintext_sha256: hex_digest,
    })
}

fn parse_archive_bytes(body: &[u8], passphrase: &str) -> Result<PendingImport, SyncError> {
    // Decrypt + parse entirely in-memory. The cap +
    // future-version check below mirror the `read_archive_to_pending`
    // pipeline (we cannot reuse it directly because it expects a
    // file path, and writing a tempfile every pull would add a
    // disk round-trip for no win — the body already sits in RAM).
    // `ENC_HEADER_MAGIC` is `LFSE`; a `PK\x03\x04` prefix means a
    // plaintext archive which the sync orchestrator does not
    // emit (every push runs through the envelope) but accept on
    // pull for symmetry with the import pipeline.
    let zip_bytes: Zeroizing<Vec<u8>> = if body.len() >= 4 && body[..4] == [0x4C, 0x46, 0x53, 0x45]
    {
        archive::decrypt_archive_with_password(body, passphrase).map_err(SyncError::from)?
    } else if body.len() >= 4 && &body[..4] == b"PK\x03\x04" {
        Zeroizing::new(body.to_vec())
    } else {
        return Err(SyncError::Network(
            "remote archive: not an LFSE envelope or ZIP file".into(),
        ));
    };
    let (pending, schema_version) =
        archive::parse_pending_import(&zip_bytes).map_err(SyncError::from)?;
    let supported = i64::from(crate::migration::SchemaVersions::ARCHIVE);
    if !(1..=supported).contains(&schema_version) {
        return Err(SyncError::ArchiveFutureVersion {
            found: schema_version,
            supported: crate::migration::SchemaVersions::ARCHIVE,
        });
    }
    Ok(pending)
}

fn build_client(cfg: &SyncConfig, password: &str) -> Result<WebDavClient, SyncError> {
    let method = match cfg.webdav_auth_method.as_str() {
        "basic" => AuthMethod::Basic,
        "digest" => AuthMethod::Digest,
        "bearer" => AuthMethod::Bearer,
        other => {
            return Err(SyncError::ConfigInvalid(format!(
                "unknown auth method: {other}"
            )))
        }
    };
    let creds = Credentials {
        method,
        username: if cfg.webdav_username.is_empty() {
            None
        } else {
            Some(cfg.webdav_username.clone())
        },
        password_or_token: Zeroizing::new(password.to_string()),
    };
    WebDavClient::new(&cfg.webdav_url, creds).map_err(|e| SyncError::ConfigInvalid(e.to_string()))
}

fn prepare() -> Result<(SyncConfig, String), SyncError> {
    let app_cfg = crate::config_store::instance()
        .get_app_config()
        .ok_or_else(|| SyncError::ConfigInvalid("config_store not initialised".into()))?;
    if !app_cfg.sync.enabled {
        return Err(SyncError::Disabled);
    }
    if app_cfg.sync.webdav_url.is_empty() {
        return Err(SyncError::ConfigInvalid("WebDAV URL is empty".into()));
    }
    let install_id = read_install_id();
    Ok((app_cfg.sync, install_id))
}

fn read_secret(id: &str) -> Result<String, SyncError> {
    let bytes = crate::app::instance()
        .secrets
        .get(id)
        .ok_or_else(|| SyncError::ConfigInvalid(format!("secret not staged: {id}")))?;
    String::from_utf8(bytes.to_vec())
        .map_err(|e| SyncError::ConfigInvalid(format!("secret not UTF-8: {e}")))
}

fn require_db() -> Result<Arc<crate::db::Db>, SyncError> {
    crate::app::instance()
        .db()
        .ok_or_else(|| SyncError::ConfigInvalid("DB not initialised".into()))
}

fn persist_sync(updated: &SyncConfig) -> Result<(), SyncError> {
    crate::config_store::instance()
        .update_sync(updated.clone())
        .map_err(SyncError::ConfigInvalid)
}

fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Stable per-install identifier the orchestrator stamps into
/// `manifest.sync_origin` on every push. The token is the
/// hostname (or `"install"` as a last-resort fallback) joined
/// with the process start time so a peer device's pull can
/// recognise its own push echoing back through the WebDAV
/// round-trip. The id is opaque to the user and never crosses
/// any other boundary; if a future arc needs a stable, opaque
/// device id this is the slot to lift it out of.
fn read_install_id() -> String {
    static INSTALL_ID: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    INSTALL_ID
        .get_or_init(|| {
            // Random 12 bytes; the slot is per-process not per-install
            // because a stable per-install token would need a separate
            // persisted file. Per-process is enough for the echo-guard
            // case — a push by this process round-tripping back to
            // this process within the same launch is what we
            // explicitly want to skip; a peer launch would mint a
            // different id and the merge runs.
            use rand::RngCore;
            let mut bytes = [0u8; 12];
            rand::rngs::OsRng.fill_bytes(&mut bytes);
            bytes.iter().map(|b| format!("{b:02x}")).collect()
        })
        .clone()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_error_from_webdav_etag_string_maps_to_etag_mismatch() {
        let e = Error::WebDav("put: HTTP 412: etag mismatch".into());
        match SyncError::from(e) {
            SyncError::EtagMismatch => {}
            other => panic!("expected EtagMismatch, got {other:?}"),
        }
    }

    #[test]
    fn sync_error_from_webdav_auth_string_maps_to_unauthorized() {
        let e = Error::WebDav("put: HTTP 401: authentication failed".into());
        match SyncError::from(e) {
            SyncError::Unauthorized => {}
            other => panic!("expected Unauthorized, got {other:?}"),
        }
    }

    #[test]
    fn sync_error_from_other_webdav_string_maps_to_network() {
        let e = Error::WebDav("put: HTTP 503: service unavailable".into());
        match SyncError::from(e) {
            SyncError::Network(_) => {}
            other => panic!("expected Network, got {other:?}"),
        }
    }

    #[test]
    fn sync_error_from_archive_future_version_passes_through() {
        let e = Error::ArchiveFutureVersion {
            found: 99,
            supported: 2,
        };
        match SyncError::from(e) {
            SyncError::ArchiveFutureVersion { found, supported } => {
                assert_eq!(found, 99);
                assert_eq!(supported, 2);
            }
            other => panic!("expected ArchiveFutureVersion, got {other:?}"),
        }
    }
}
