//! FRB adapter for `lfs_core::archive` — the `.lfs` export
//! orchestrator. Dart hands in options + selected ids + the
//! pre-serialised `config.json` payload (since `config.json` is
//! file-based, not DB-resident); Rust returns the encrypted archive
//! bytes ready to write atomically.

use lfs_core::archive::{ExportInput, ExportOptions};

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
