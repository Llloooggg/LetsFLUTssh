//! FRB adapter for `lfs_core::qr_compose` — typed QR-payload size
//! estimator that the `unified_export_controller` live "fits in QR"
//! gauge routes through.
//!
//! Sync — composition pulls sessions / keys / tags / snippets from
//! the open SQLCipher connection on every checkbox toggle. The DB
//! lookup is one indexed read per slice (~hundreds of µs even for
//! the 100-session ceiling), so the no-async-hop overhead matters
//! for the live UI gauge while the payload bytes — including
//! manager-key PEM — never cross the FRB boundary back to Dart.
//!
//! Earlier shape (retired): the Dart caller built a fully-resolved
//! `DbQrPayloadInput` that carried every session, tag, snippet, and
//! manager-key PEM as a Dart-side struct, handed it across FRB, and
//! the Rust composer measured the bytes. PEM bytes therefore lived
//! on the Dart heap for the dialog's lifetime. The id-based shape
//! mirrors `db_export_qr_payload` (production export), so the
//! estimator and the production producer share one wire shape and
//! the dialog never materialises private material.

use crate::api::archive::DbQrExportInput;
use lfs_core::archive::{qr_export_payload_size, QrExportInput, QrExportOptions};

fn require_db() -> Result<std::sync::Arc<lfs_core::db::Db>, String> {
    lfs_core::app::instance()
        .db()
        .ok_or_else(|| "db not initialized".to_string())
}

/// Size of the QR payload (`d=` value) for the current selection,
/// in bytes (deflated + base64url-encoded). Reads sessions / keys /
/// tags / snippets straight from the open SQLCipher connection by
/// id so the manager-key PEM never crosses the FRB boundary into
/// Dart memory.
///
/// Wire-shape parity with [`crate::api::archive::db_export_qr_payload`]
/// (the production producer) — both routes through
/// `lfs_core::archive::qr_export_payload_size`, so the gauge value
/// the Dart UI reads is the same number the user would actually
/// get if they hit Export now.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_estimate_export_size(input: DbQrExportInput) -> Result<u32, String> {
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
    let db = require_db()?;
    db.with_conn(|c| qr_export_payload_size(c, &core_input))
        .map_err(|e| e.to_string())
}
