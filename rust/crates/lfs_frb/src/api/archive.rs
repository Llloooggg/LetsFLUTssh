//! FRB adapter for `lfs_core::archive` — the `.lfs` export
//! orchestrator. Dart hands in options + selected ids + the
//! pre-serialised `config.json` payload (since `config.json` is
//! file-based, not DB-resident); Rust returns the encrypted archive
//! bytes ready to write atomically.

use lfs_core::archive::{ExportInput, ExportOptions, QrExportInput, QrExportOptions};

fn require_db() -> Result<std::sync::Arc<lfs_core::db::Db>, String> {
    lfs_core::app::instance()
        .db()
        .ok_or_else(|| "db not initialized".to_string())
}

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
    /// Empty string → no encryption, raw ZIP. Non-empty → Argon2id
    /// + AES-GCM envelope under the canonical `LFSE`-magic header.
    pub master_password: String,
    pub kdf_memory_kib: u32,
    pub kdf_iterations: u32,
    pub kdf_parallelism: u32,
    pub created_at_ms: i64,
}

/// Compose and (optionally) encrypt the `.lfs` archive entirely
/// inside Rust. Plaintext credentials never cross the FRB boundary
/// outbound — the bytes flow DB → JSON → ZIP → AES-GCM and only the
/// finished archive returns to Dart.
pub async fn db_export_archive(input: DbExportInput) -> Result<Vec<u8>, String> {
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
            Some(input.master_password)
        },
        kdf_memory_kib: input.kdf_memory_kib,
        kdf_iterations: input.kdf_iterations,
        kdf_parallelism: input.kdf_parallelism,
        created_at_ms: input.created_at_ms,
    };

    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn(|c| lfs_core::archive::export_archive(c, &core_input))
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| format!("export task: {e}"))?
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

fn random_handle_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    let mut hex = String::with_capacity(32);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
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
pub async fn db_import_open(
    path: String,
    password: String,
) -> Result<DbImportOpenResult, String> {
    tokio::task::spawn_blocking(move || {
        let (pending, preview) = lfs_core::archive::read_archive_to_pending(&path, &password)
            .map_err(|e| e.to_string())?;
        let app = lfs_core::app::instance();
        let handle_id = random_handle_id();
        app.imports.insert(handle_id.clone(), pending);
        Ok(DbImportOpenResult {
            handle_id,
            preview: preview.into(),
        })
    })
    .await
    .map_err(|e| format!("import open task: {e}"))?
}

/// Drop the staged archive without applying it. Idempotent on a
/// missing handle id. Pair with [`db_import_open`] from the Dart
/// side: cancel button on the preview dialog calls this; OK
/// button hands the id to the apply driver (lands in a
/// follow-up).
pub async fn db_import_drop(handle_id: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::app::instance().imports.drop_handle(&handle_id);
    })
    .await
    .map_err(|e| format!("import drop task: {e}"))
}
