//! FRB adapter for `lfs_core::archive` — the `.lfs` export
//! orchestrator. Dart hands in options + selected ids + the
//! pre-serialised `config.json` payload (since `config.json` is
//! file-based, not DB-resident); Rust returns the encrypted archive
//! bytes ready to write atomically.

use lfs_core::archive::{
    export_archive_size, ExportInput, ExportOptions, QrExportInput, QrExportOptions,
};

use crate::api::db::require_db;

/// Mirror of `ExportOptions` over the FRB boundary. Field-for-field
/// copy of the Dart `ExportOptions` toggle bag.
#[derive(Debug, Clone)]
pub struct DbExportOptions {
    pub include_sessions: bool,
    pub include_known_hosts: bool,
    pub include_config: bool,
    pub include_tags: bool,
    pub include_snippets: bool,
    pub include_all_manager_keys: bool,
    pub has_manager_keys: bool,
}

/// Mirror of `ExportInput`. Pulled verbatim across the FRB
/// boundary; the orchestrator owns the actual archive composition.
#[derive(Debug, Clone)]
pub struct DbExportInput {
    pub options: DbExportOptions,
    pub selected_session_ids: Vec<String>,
    pub selected_empty_folders: Vec<String>,
    pub config_json: String,
    pub schema_version: i64,
    pub app_version: Option<String>,
    /// Empty bytes → no encryption, raw ZIP. Non-empty → an
    /// Argon2id + AES-GCM envelope under the canonical
    /// `LFSE`-magic header. Wire shape is `Vec<u8>` so the Dart
    /// caller stays on `Uint8List.fromList(utf8.encode(text))`,
    /// mirroring the master-password / keychain-gate /
    /// tier-orchestrator family.
    pub master_password: Vec<u8>,
    pub kdf_memory_kib: u32,
    pub kdf_iterations: u32,
    pub kdf_parallelism: u32,
    pub created_at_ms: i64,
}

/// Compose, (optionally) encrypt, and atomically write the `.lfs`
/// archive entirely inside Rust. Plaintext credentials never cross
/// the FRB boundary outbound: the bytes flow DB → JSON → ZIP →
/// AES-GCM → atomic file write under `output_path`. Returns the
/// archive byte count so the caller can log or surface progress
/// without re-stat'ing the file. Atomic via
/// [`lfs_core::path::write_bytes_atomic`] (tmp + fsync + rename +
/// parent-dir fsync), so a crash mid-write leaves the previous
/// file at `output_path` (or no file when none existed). The Dart
/// caller no longer maintains its own tmp + writeAsBytes + rename
/// discipline.
pub async fn db_export_archive(input: DbExportInput, output_path: String) -> Result<i64, String> {
    let core_input = ExportInput {
        options: ExportOptions {
            include_sessions: input.options.include_sessions,
            include_known_hosts: input.options.include_known_hosts,
            include_config: input.options.include_config,
            include_tags: input.options.include_tags,
            include_snippets: input.options.include_snippets,
            include_all_manager_keys: input.options.include_all_manager_keys,
            has_manager_keys: input.options.has_manager_keys,
        },
        selected_session_ids: input.selected_session_ids,
        selected_empty_folders: input.selected_empty_folders,
        config_json: input.config_json,
        schema_version: input.schema_version,
        app_version: input.app_version,
        master_password: if input.master_password.is_empty() {
            None
        } else {
            Some(
                String::from_utf8(input.master_password)
                    .map_err(|_| "master_password is not valid UTF-8".to_string())?,
            )
        },
        kdf_memory_kib: input.kdf_memory_kib,
        kdf_iterations: input.kdf_iterations,
        kdf_parallelism: input.kdf_parallelism,
        created_at_ms: input.created_at_ms,
    };

    tokio::task::spawn_blocking(move || -> Result<i64, String> {
        let db = require_db().map_err(|e| e.to_string())?;
        let bytes = db
            .with_conn(|c| lfs_core::archive::export_archive(c, &core_input))
            .map_err(|e| e.to_string())?;
        let len = i64::try_from(bytes.len()).unwrap_or(i64::MAX);
        let path = std::path::PathBuf::from(&output_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("create parent dir for archive: {e}"))?;
        }
        lfs_core::path::write_bytes_atomic(&path, &bytes)
            .map_err(|e| format!("write archive atomic: {e}"))?;
        Ok(len)
    })
    .await
    .map_err(|e| format!("export task: {e}"))?
}

/// Size of the `.lfs` archive bytes for the current selection
/// without running Argon2id KDF or AES-GCM encryption — drives the
/// live "archive size" preview line in the export dialog. Reads
/// sessions / keys / tags / snippets straight from the open
/// SQLCipher connection by id, so manager-key PEM never crosses
/// the FRB boundary into Dart memory for the gauge.
///
/// Sync — composition is a few hundred clones + the ZIP STORED-
/// mode write pass, sub-millisecond on realistic export
/// selections. The dialog calls this on every checkbox toggle so
/// the no-async-hop overhead matters; `master_password` is only
/// consulted to decide whether to add the LFSE envelope's fixed
/// 75-byte overhead constant — the bytes themselves are never
/// inspected, so the dialog can pass an empty `Vec<u8>` until the
/// user reaches the password prompt.
#[flutter_rust_bridge::frb(sync)]
pub fn db_lfs_export_size(input: DbExportInput) -> Result<u32, String> {
    let core_input = ExportInput {
        options: ExportOptions {
            include_sessions: input.options.include_sessions,
            include_known_hosts: input.options.include_known_hosts,
            include_config: input.options.include_config,
            include_tags: input.options.include_tags,
            include_snippets: input.options.include_snippets,
            include_all_manager_keys: input.options.include_all_manager_keys,
            has_manager_keys: input.options.has_manager_keys,
        },
        selected_session_ids: input.selected_session_ids,
        selected_empty_folders: input.selected_empty_folders,
        config_json: input.config_json,
        schema_version: input.schema_version,
        app_version: input.app_version,
        master_password: if input.master_password.is_empty() {
            None
        } else {
            Some(
                String::from_utf8(input.master_password)
                    .map_err(|_| "master_password is not valid UTF-8".to_string())?,
            )
        },
        kdf_memory_kib: input.kdf_memory_kib,
        kdf_iterations: input.kdf_iterations,
        kdf_parallelism: input.kdf_parallelism,
        created_at_ms: input.created_at_ms,
    };
    let db = require_db()?;
    db.with_conn(|c| export_archive_size(c, &core_input))
        .map_err(|e| e.to_string())
}

/// Mirror of `QrExportOptions` over the FRB boundary.
#[derive(Debug, Clone)]
pub struct DbQrExportOptions {
    pub include_sessions: bool,
    pub include_config: bool,
    pub include_known_hosts: bool,
    pub include_passwords: bool,
    pub include_embedded_keys: bool,
    pub include_manager_keys: bool,
    pub include_all_manager_keys: bool,
    pub include_tags: bool,
    pub include_snippets: bool,
}

#[derive(Debug, Clone)]
pub struct DbQrExportInput {
    pub options: DbQrExportOptions,
    pub selected_session_ids: Vec<String>,
    pub selected_empty_folders: Vec<String>,
    pub config_json: Option<String>,
}

/// Same composition as [`db_export_qr_payload`] but skips the
/// base64url encode step and returns the deflated payload's
/// byte count. Drives the live "fits in QR" gauge in the Dart
/// `unified_export_controller` — single FRB call per checkbox
/// toggle replaces the per-toggle Dart-side JSON build + Rust
/// deflate round-trip the controller used to do.
pub async fn db_export_qr_payload_size(input: DbQrExportInput) -> Result<u32, String> {
    let core_input = QrExportInput {
        options: QrExportOptions {
            include_sessions: input.options.include_sessions,
            include_config: input.options.include_config,
            include_known_hosts: input.options.include_known_hosts,
            include_passwords: input.options.include_passwords,
            include_embedded_keys: input.options.include_embedded_keys,
            include_manager_keys: input.options.include_manager_keys,
            include_all_manager_keys: input.options.include_all_manager_keys,
            include_tags: input.options.include_tags,
            include_snippets: input.options.include_snippets,
        },
        selected_session_ids: input.selected_session_ids,
        selected_empty_folders: input.selected_empty_folders,
        config_json: input.config_json,
    };

    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn(|c| lfs_core::archive::qr_export_payload_size(c, &core_input))
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("qr export size task: {e}"))?
}

/// Build the QR deeplink payload (`d=` value) entirely Rust-side.
/// Returns the deflated + base64url-encoded ASCII string ready to
/// hand to a QR widget. Plaintext credential bytes — manager-key
/// PEM, session passwords — flow DB → JSON → deflate → base64
/// inside Rust so the Dart heap only sees the encoded ASCII.
pub async fn db_export_qr_payload(input: DbQrExportInput) -> Result<String, String> {
    let core_input = QrExportInput {
        options: QrExportOptions {
            include_sessions: input.options.include_sessions,
            include_config: input.options.include_config,
            include_known_hosts: input.options.include_known_hosts,
            include_passwords: input.options.include_passwords,
            include_embedded_keys: input.options.include_embedded_keys,
            include_manager_keys: input.options.include_manager_keys,
            include_all_manager_keys: input.options.include_all_manager_keys,
            include_tags: input.options.include_tags,
            include_snippets: input.options.include_snippets,
        },
        selected_session_ids: input.selected_session_ids,
        selected_empty_folders: input.selected_empty_folders,
        config_json: input.config_json,
    };

    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn(|c| lfs_core::archive::qr_export_payload(c, &core_input))
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("qr export task: {e}"))?
}

/// FRB mirror of `lfs_core::archive::ImportPreview`. Sanitised
/// counts + session labels — the apply side reads the full
/// payload from the registry handle, so the preview is the only
/// thing that crosses the boundary outwards.
#[derive(Debug, Clone)]
pub struct DbImportPreview {
    pub schema_version: i64,
    pub session_count: i64,
    pub session_labels: Vec<String>,
    pub manager_key_count: i64,
    pub tag_count: i64,
    pub snippet_count: i64,
    pub empty_folder_count: i64,
    pub has_config: bool,
    pub has_known_hosts: bool,
}

impl From<lfs_core::archive::ImportPreview> for DbImportPreview {
    fn from(p: lfs_core::archive::ImportPreview) -> Self {
        DbImportPreview {
            schema_version: p.schema_version,
            session_count: p.session_count,
            session_labels: p.session_labels,
            manager_key_count: p.manager_key_count,
            tag_count: p.tag_count,
            snippet_count: p.snippet_count,
            empty_folder_count: p.empty_folder_count,
            has_config: p.has_config,
            has_known_hosts: p.has_known_hosts,
        }
    }
}

/// Result of a successful preview — the registered handle id
/// the Dart caller passes back to the apply / drop endpoints,
/// plus the sanitised preview.
#[derive(Debug, Clone)]
pub struct DbImportOpenResult {
    pub handle_id: String,
    pub preview: DbImportPreview,
}

/// Decode a QR / paste-link payload (deflated + base64url JSON,
/// or v1 legacy raw base64url JSON), stage the resulting
/// `PendingImport` under a freshly-generated handle id, and
/// return the sanitised preview. Mirrors `db_import_open` for
/// the QR / deeplink paths so the apply driver sees the same
/// shape regardless of whether the bytes came from a `.lfs`
/// archive or a QR scan.
///
/// `payload` is the value of the `d=` query parameter from a
/// `letsflutssh://import?d=...` deeplink. The Dart caller may
/// also pass the full URI — the leading `letsflutssh://import?d=`
/// is stripped automatically.
/// Pre-decrypt classifier for a candidate `.lfs` file. Mirrors
/// `lfs_core::archive::probe::ProbeKind` so the Dart file-picker
/// can branch on a typed enum without having to interpret a magic
/// byte / size threshold itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbArchiveProbeKind {
    /// Doesn't start with the ZIP local-file-header magic — almost
    /// certainly an encrypted `.lfs` (random 32-byte salt prefix).
    /// Caller surfaces the password prompt.
    EncryptedLfs,
    /// Plain ZIP carrying at least one of our marker entries.
    /// Caller imports without a password.
    UnencryptedLfs,
    /// Anything else — non-ZIP, ZIP without our markers (an `.apk`
    /// picked by mistake), file too big, malformed ZIP, missing
    /// file. Caller refuses the import with a friendly toast.
    NotLfs,
}

impl From<lfs_core::archive::probe::ProbeKind> for DbArchiveProbeKind {
    fn from(k: lfs_core::archive::probe::ProbeKind) -> Self {
        match k {
            lfs_core::archive::probe::ProbeKind::EncryptedLfs => Self::EncryptedLfs,
            lfs_core::archive::probe::ProbeKind::UnencryptedLfs => Self::UnencryptedLfs,
            lfs_core::archive::probe::ProbeKind::NotLfs => Self::NotLfs,
        }
    }
}

/// Classify the file at `path`. Pure best-effort: any I/O / parse
/// error collapses to `NotLfs` so the caller surfaces a single
/// rejection. The probe stays sub-millisecond on small files
/// (header read + size stat) and milliseconds on large plain ZIPs
/// (entry-list scan); blocking-pool wrapped to keep the FRB worker
/// thread free.
pub async fn db_archive_probe(path: String) -> DbArchiveProbeKind {
    tokio::task::spawn_blocking(move || lfs_core::archive::probe::probe(&path).into())
        .await
        .unwrap_or(DbArchiveProbeKind::NotLfs)
}

pub async fn qr_import_open(payload: String) -> Result<DbImportOpenResult, String> {
    tokio::task::spawn_blocking(move || {
        let raw = lfs_core::qr_codec_decode::extract_payload_from_uri(&payload).unwrap_or(payload);
        let decoded = lfs_core::qr_codec_decode::decode_payload(&raw).map_err(|e| e.to_string())?;
        let preview = decoded.pending.preview(decoded.schema_version);
        let app = lfs_core::app::instance();
        let handle_id = lfs_core::id::random_handle_hex_32();
        app.imports.insert(handle_id.clone(), decoded.pending);
        Ok(DbImportOpenResult {
            handle_id,
            preview: preview.into(),
        })
    })
    .await
    .map_err(|e| format!("qr import open task: {e}"))?
}

/// Open and decrypt a `.lfs` archive (or a raw ZIP for the
/// no-password export shape). Stages the decoded entries inside
/// `AppState::imports` under a freshly-generated handle id and
/// returns the sanitised preview. Plaintext payload (sessions,
/// keys, …) stays Rust-side; the Dart caller only sees counts
/// + labels until it hands the handle back to the apply driver.
///
/// `password` empty → assumes a raw-ZIP archive (matches the
/// "no encryption" export branch). Wrong password / malformed
/// envelope surfaces as an error and no handle is registered.
pub async fn db_import_open(path: String, password: Vec<u8>) -> Result<DbImportOpenResult, String> {
    tokio::task::spawn_blocking(move || {
        let pw = std::str::from_utf8(&password)
            .map_err(|_| "password is not valid UTF-8".to_string())?;
        let (pending, preview) =
            lfs_core::archive::read_archive_to_pending(&path, pw).map_err(|e| e.to_string())?;
        let app = lfs_core::app::instance();
        let handle_id = lfs_core::id::random_handle_hex_32();
        app.imports.insert(handle_id.clone(), pending);
        Ok(DbImportOpenResult {
            handle_id,
            preview: preview.into(),
        })
    })
    .await
    .map_err(|e| format!("import open task: {e}"))?
}

/// Pre-parsed JSON entries staged directly in the import
/// registry, bypassing the LFSE decrypt + zip parse path.
/// Used by Dart consumers that already hold the JSON payloads
/// in memory (QR import, OpenSSH import, the legacy Dart-side
/// archive decrypt flow) so they can route the apply step
/// through the Rust driver without round-tripping the bytes
/// back through a temp file.
///
/// Every field is optional — missing entries no-op on the
/// apply side, same as the LFSE path.
#[derive(Debug, Clone)]
pub struct DbStagedImport {
    pub manifest_json: Option<String>,
    pub sessions_json: Option<String>,
    pub keys_json: Option<String>,
    pub tags_json: Option<String>,
    pub session_tags_json: Option<String>,
    pub folder_tags_json: Option<String>,
    pub snippets_json: Option<String>,
    pub session_snippets_json: Option<String>,
    pub empty_folders_json: Option<String>,
    pub config_json: Option<String>,
    pub known_hosts_text: Option<String>,
}

/// Stage a [`DbStagedImport`] into the registry under a
/// freshly-minted handle id. Returns the handle so the caller
/// can hand it back to [`db_import_apply`] / [`db_import_drop`].
/// Skips the LFSE decrypt + zip parse — the caller's already
/// done that work or has built the JSONs locally (QR import,
/// OpenSSH parser).
pub async fn db_import_stage(input: DbStagedImport) -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let pending = lfs_core::archive::PendingImport {
            manifest_json: input.manifest_json,
            sessions_json: input.sessions_json,
            keys_json: input.keys_json,
            tags_json: input.tags_json,
            session_tags_json: input.session_tags_json,
            folder_tags_json: input.folder_tags_json,
            snippets_json: input.snippets_json,
            session_snippets_json: input.session_snippets_json,
            empty_folders_json: input.empty_folders_json,
            config_json: input.config_json,
            known_hosts_text: input.known_hosts_text,
        };
        let app = lfs_core::app::instance();
        let handle_id = lfs_core::id::random_handle_hex_32();
        app.imports.insert(handle_id.clone(), pending);
        Ok(handle_id)
    })
    .await
    .map_err(|e| format!("import stage task: {e}"))?
}

/// Drop the staged archive without applying it. Idempotent on a
/// missing handle id. Pair with [`db_import_open`] /
/// [`db_import_stage`] from the Dart side: cancel button on the
/// preview dialog calls this; OK button hands the id to
/// [`db_import_apply`].
pub async fn db_import_drop(handle_id: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::app::instance().imports.drop_handle(&handle_id);
    })
    .await
    .map_err(|e| format!("import drop task: {e}"))
}

/// Mirror of `lfs_core::archive::ImportMode`.
#[derive(Debug, Clone, Copy)]
pub enum DbImportMode {
    Merge,
    Replace,
}

impl From<DbImportMode> for lfs_core::archive::ImportMode {
    fn from(m: DbImportMode) -> Self {
        match m {
            DbImportMode::Merge => lfs_core::archive::ImportMode::Merge,
            DbImportMode::Replace => lfs_core::archive::ImportMode::Replace,
        }
    }
}

/// Apply-time toggles. Each flag enables the matching entry kind
/// regardless of what the archive carries — the apply driver
/// silently no-ops on missing JSON entries.
#[derive(Debug, Clone)]
pub struct DbApplyOptions {
    pub mode: DbImportMode,
    pub apply_sessions: bool,
    pub apply_keys: bool,
    pub apply_tags: bool,
    pub apply_snippets: bool,
    pub apply_known_hosts: bool,
}

/// Counters returned by [`db_import_apply`]. Mirrors
/// `lfs_core::archive::ApplyResult` field-for-field.
///
/// `config_json` carries the staged `config.json` payload back to
/// the Dart caller — `config.json` is a Dart-managed file artefact,
/// not a DB row, so the apply driver leaves it alone and returns
/// the JSON for the caller to parse + restore. Only populated when
/// the staged archive carried a config entry; `None` otherwise.
#[derive(Debug, Clone)]
pub struct DbApplyResult {
    pub sessions_applied: i64,
    pub keys_applied: i64,
    pub keys_skipped_dedup: i64,
    pub tags_applied: i64,
    pub snippets_applied: i64,
    pub known_hosts_applied: i64,
    pub folders_applied: i64,
    pub session_tags_applied: i64,
    pub folder_tags_applied: i64,
    pub session_snippets_applied: i64,
    pub errors: Vec<String>,
    pub config_json: Option<String>,
    /// Replace-mode-only flag. True when the apply driver hit a
    /// per-row error and rolled the whole transaction back so the
    /// user's pre-import state survives. Caller MUST treat this
    /// as a hard failure (display `errors`, do not act on the
    /// `*_applied` counters) rather than a partial success.
    pub rolled_back: bool,
}

impl From<lfs_core::archive::ApplyResult> for DbApplyResult {
    fn from(r: lfs_core::archive::ApplyResult) -> Self {
        DbApplyResult {
            sessions_applied: r.sessions_applied,
            keys_applied: r.keys_applied,
            keys_skipped_dedup: r.keys_skipped_dedup,
            tags_applied: r.tags_applied,
            snippets_applied: r.snippets_applied,
            known_hosts_applied: r.known_hosts_applied,
            folders_applied: r.folders_applied,
            session_tags_applied: r.session_tags_applied,
            folder_tags_applied: r.folder_tags_applied,
            session_snippets_applied: r.session_snippets_applied,
            errors: r.errors,
            config_json: None,
            rolled_back: r.rolled_back,
        }
    }
}

/// Commit the staged archive to the DB in merge mode. The
/// handle is consumed (taken out of the registry) on success;
/// on parse failure the registry keeps the entry so the caller
/// can retry / drop. `created_at_ms` stamps the rows that don't
/// carry their own timestamp in the archive.
pub async fn db_import_apply(
    handle_id: String,
    options: DbApplyOptions,
    created_at_ms: i64,
) -> Result<DbApplyResult, String> {
    let core_options = lfs_core::archive::ApplyOptions {
        mode: options.mode.into(),
        apply_sessions: options.apply_sessions,
        apply_keys: options.apply_keys,
        apply_tags: options.apply_tags,
        apply_snippets: options.apply_snippets,
        apply_known_hosts: options.apply_known_hosts,
    };
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let pending = app
            .imports
            .take(&handle_id)
            .ok_or_else(|| format!("import handle {handle_id} not found"))?;
        let staged_config_json = pending.config_json.clone();
        let db = require_db()?;
        let result = db
            .with_conn_mut(|c| {
                lfs_core::archive::apply_pending_import(c, &pending, &core_options, created_at_ms)
            })
            .map_err(|e| e.to_string())?;
        let mut frb_result = DbApplyResult::from(result);
        frb_result.config_json = staged_config_json;
        Ok(frb_result)
    })
    .await
    .map_err(|e| format!("import apply task: {e}"))?
}
