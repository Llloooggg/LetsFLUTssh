//! `.lfs` archive composer — turns a [`crate::db`] state plus a
//! caller-built [`ExportInput`] into the stored-mode ZIP that the
//! LFSE envelope wraps. The crypto envelope itself lives next door
//! in [`super::envelope`]; this module owns wire-shape decisions
//! (entry names, JSON field order, default-omission rules) and the
//! per-entity DB → `serde_json::Value` builders.
//!
//! # Why each entity gets its own builder
//!
//! Sessions / keys / tags / snippets / known-hosts each have their
//! own DAO, their own toggle in [`ExportOptions`], and their own
//! "skip when empty" branch — peeling them apart keeps the export
//! orchestrator readable and makes per-entity wire changes a
//! one-helper edit. The Dart importer (`lib/core/import/
//! import_service.dart`) parses the same shapes; bumping any field
//! name without updating the apply-side parser is a wire break.
//!
//! Plaintext credentials (session passwords, key PEM, passphrases)
//! are read straight from the encrypted DB into Rust-owned strings
//! and threaded through [`Value`] without ever materialising on the
//! Dart heap. The orchestrator hands the raw ZIP bytes to
//! [`super::envelope::encrypt_with_password`] when a master password
//! is set, so the file the user picks in the save dialog is either
//! a raw ZIP (no password) or an LFSE envelope wrapping it.

use std::collections::{HashMap, HashSet};
use std::io::{Cursor, Write};

use serde_json::{json, Value};
use zip::write::SimpleFileOptions;

use crate::db::{
    folders, port_forwards, s3_sessions, sessions, sftp_bookmarks, snippets, ssh_key_certificates,
    ssh_keys, tags, webdav_sessions,
};
use crate::error::Error;

use super::envelope::encrypt_with_password;
use super::iso8601::format_iso8601_utc;
use super::{build_folder_paths, build_known_hosts};

/// What sections the caller wants in the archive. Mirrors the bool
/// fields on `ExportOptions` Dart-side; the orchestrator only emits
/// an entry when its toggle is on AND the underlying source has
/// content.
#[derive(Debug, Clone, Default)]
pub struct ExportOptions {
    pub include_sessions: bool,
    pub include_known_hosts: bool,
    pub include_config: bool,
    pub include_tags: bool,
    pub include_snippets: bool,
    /// True → include every manager key. False → include only the
    /// keys referenced by `selected_session_ids` via their `keyId`.
    pub include_all_manager_keys: bool,
    /// True when the user opted into shipping any manager keys at
    /// all. When false, no `keys.json` entry is written even if the
    /// previous toggle is true.
    pub has_manager_keys: bool,
}

/// Inputs to [`export_archive`]. Sessions / folders / tags / snippets
/// / known-hosts come straight from `letsflutssh.db`; only `config_json`
/// is passed through from Dart because `config.json` lives on disk.
#[derive(Debug, Clone)]
pub struct ExportInput {
    pub options: ExportOptions,
    pub selected_session_ids: Vec<String>,
    pub selected_empty_folders: Vec<String>,
    /// Pre-serialised `config.json` payload (Dart calls
    /// `AppConfig.toJsonForExport()`). Embedded verbatim when
    /// `options.include_config` is true.
    pub config_json: String,
    pub schema_version: i64,
    pub app_version: Option<String>,
    /// `None` → write the raw ZIP. `Some(pw)` → outer Argon2id +
    /// AES-GCM envelope. Empty string is treated as no encryption,
    /// matching the Dart-side contract.
    pub master_password: Option<String>,
    /// Argon2id parameters when `master_password` is set. The
    /// canonical production profile lives in
    /// `lfs_core::security::master_password::KdfParams::defaults`
    /// (64 MiB / t=3 / p=1) and Dart's `KdfParams.productionDefaults`
    /// mirrors it at startup.
    pub kdf_memory_kib: u32,
    pub kdf_iterations: u32,
    pub kdf_parallelism: u32,
    /// Unix millis to stamp into `manifest.created_at`. Passed in
    /// rather than read from the system clock so callers can pin a
    /// deterministic timestamp during tests.
    pub created_at_ms: i64,
    /// Caller-supplied identity stamp written into
    /// `manifest.sync_origin`. The sync orchestrator
    /// (`crate::sync`) stamps a unique
    /// `<install-id>:<unix_ms>` token on every push; a peer
    /// device's pull recognises "this is my own push echoing
    /// back" by comparing the field against its own stamp and
    /// skips applying the archive. `None` emits no field (legacy
    /// shape, manual exports from the Data → Export dialog).
    /// Available since `SchemaVersions::ARCHIVE` v2.
    pub sync_origin: Option<String>,
}

/// Compose and (optionally) encrypt the `.lfs` archive.
///
/// Returns the bytes the caller writes atomically to the chosen
/// path. Errors at any stage abort the archive — partial output is
/// never returned, mirroring Dart's `tmp + rename` discipline.
pub fn export_archive(
    conn: &impl crate::db::DbAccess,
    input: &ExportInput,
) -> Result<Vec<u8>, Error> {
    let zip_bytes = build_zip(conn, input)?;

    let pw = input.master_password.as_deref().unwrap_or("");
    if pw.is_empty() {
        return Ok(zip_bytes);
    }

    encrypt_with_password(
        &zip_bytes,
        pw,
        input.kdf_memory_kib,
        input.kdf_iterations,
        input.kdf_parallelism,
    )
}

/// LFSE envelope overhead added when `master_password` is set.
/// Stays a constant regardless of inner ZIP size:
/// magic (4) + version (1) + KDF params block (10 — algo byte +
/// memory u32 BE + iterations u32 BE + parallelism u8) + salt (32)
/// + IV (12) + AES-GCM tag (16) = 75 bytes.
const LFSE_ENVELOPE_OVERHEAD: u32 = 4 + 1 + 10 + 32 + 12 + 16;

/// Size of the `.lfs` archive bytes for the current selection,
/// without running the Argon2id KDF or AES-GCM encryption pass.
/// Drives the live "archive size" preview line in the Dart export
/// dialog: composes the inner ZIP exactly the way `export_archive`
/// would, then adds the LFSE envelope's fixed overhead when the
/// master password slot is set.
///
/// `master_password` is only consulted to decide whether to add
/// the envelope-overhead constant — the bytes themselves are never
/// inspected, so the caller can hand an empty `Vec<u8>` if it
/// hasn't asked the user for the password yet but wants the
/// encrypted-shape size.
pub fn export_archive_size(
    conn: &impl crate::db::DbAccess,
    input: &ExportInput,
) -> Result<u32, Error> {
    let zip_bytes = build_zip(conn, input)?;
    let inner = u32::try_from(zip_bytes.len()).unwrap_or(u32::MAX);
    let encrypted = !input.master_password.as_deref().unwrap_or("").is_empty();
    Ok(if encrypted {
        inner.saturating_add(LFSE_ENVELOPE_OVERHEAD)
    } else {
        inner
    })
}

fn build_zip(conn: &impl crate::db::DbAccess, input: &ExportInput) -> Result<Vec<u8>, Error> {
    let mut buf = Cursor::new(Vec::new());
    let mut zw = zip::ZipWriter::new(&mut buf);
    let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);

    write_manifest(&mut zw, opts, input)?;

    if input.options.include_sessions {
        let folder_paths = build_folder_paths(conn)?;
        let sessions_value =
            build_sessions_value(conn, &input.selected_session_ids, &folder_paths)?;
        write_json_entry(&mut zw, opts, "sessions.json", &sessions_value)?;
        if !input.selected_empty_folders.is_empty() {
            let value = Value::Array(
                input
                    .selected_empty_folders
                    .iter()
                    .map(|s| Value::String(s.clone()))
                    .collect(),
            );
            write_json_entry(&mut zw, opts, "empty_folders.json", &value)?;
        }
    }

    if input.options.has_manager_keys {
        let keys_value = build_manager_keys_value(
            conn,
            &input.selected_session_ids,
            input.options.include_all_manager_keys,
        )?;
        if let Some(value) = keys_value {
            write_json_entry(&mut zw, opts, "keys.json", &value)?;
        }
    }

    if input.options.include_config && !input.config_json.is_empty() {
        write_text_entry(&mut zw, opts, "config.json", &input.config_json)?;
    }

    if input.options.include_known_hosts {
        let kh = build_known_hosts(conn)?;
        if !kh.is_empty() {
            // Entry name must match `parse_pending_import`'s reader
            // (`archive/mod.rs::parse_pending_import` keys on
            // `"known_hosts.txt"`); writing the bare name silently
            // dropped every known-hosts payload at import time.
            write_text_entry(&mut zw, opts, "known_hosts.txt", &kh)?;
        }
    }

    if input.options.include_tags {
        if let Some(tags_value) = build_tags_value(conn)? {
            write_json_entry(&mut zw, opts, "tags.json", &tags_value)?;

            if let Some(session_tags) = build_session_tags_value(conn, &input.selected_session_ids)?
            {
                write_json_entry(&mut zw, opts, "session_tags.json", &session_tags)?;
            }

            if let Some(folder_tags) = build_folder_tags_value(conn)? {
                write_json_entry(&mut zw, opts, "folder_tags.json", &folder_tags)?;
            }
        }
    }

    if input.options.include_snippets {
        if let Some(snippets_value) = build_snippets_value(conn)? {
            write_json_entry(&mut zw, opts, "snippets.json", &snippets_value)?;
            if let Some(session_snippets) =
                build_session_snippets_value(conn, &input.selected_session_ids)?
            {
                write_json_entry(&mut zw, opts, "session_snippets.json", &session_snippets)?;
            }
        }
    }

    // v3 child-table entries. Each piggy-backs on an existing
    // include toggle so the user does not need a separate checkbox
    // for every newly-portable table:
    // - `ssh_key_certificates` follows `has_manager_keys` (a cert
    //   without its parent key is meaningless).
    // - `webdav_session_details`, `s3_session_details`,
    //   `sftp_bookmarks`, `port_forward_rules` follow `include_sessions`
    //   (each row is keyed by `session_id`).
    if input.options.has_manager_keys {
        if let Some(value) = build_ssh_key_certificates_value(
            conn,
            &input.selected_session_ids,
            input.options.include_all_manager_keys,
        )? {
            write_json_entry(&mut zw, opts, "ssh_key_certificates.json", &value)?;
        }
    }
    // Tombstoned rows travel only on the sync wire, not in manual
    // `.lfs` archive exports. Sync push stamps `sync_origin` on the
    // manifest; manual exports leave the field absent. Keying
    // tombstone emission off that flag keeps the archive-import
    // applier insulated from sync-protocol concerns even when the
    // user-facing dialog reuses the same composer.
    let sync_mode = input.sync_origin.as_deref().is_some_and(|s| !s.is_empty());
    if input.options.include_sessions {
        if let Some(value) =
            build_webdav_session_details_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "webdav_session_details.json", &value)?;
        }
        if let Some(value) =
            build_s3_session_details_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "s3_session_details.json", &value)?;
        }
        if let Some(value) = build_sftp_bookmarks_value(conn, &input.selected_session_ids)? {
            write_json_entry(&mut zw, opts, "sftp_bookmarks.json", &value)?;
        }
        if let Some(value) =
            build_port_forward_rules_value(conn, &input.selected_session_ids, sync_mode)?
        {
            write_json_entry(&mut zw, opts, "port_forward_rules.json", &value)?;
        }
    }

    zw.finish()
        .map_err(|e| Error::Archive(format!("zip finish: {e}")))?;
    Ok(buf.into_inner())
}

fn write_manifest(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    input: &ExportInput,
) -> Result<(), Error> {
    let mut obj = serde_json::Map::new();
    obj.insert("schema_version".into(), json!(input.schema_version));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(input.created_at_ms)),
    );
    if let Some(v) = input.app_version.as_deref() {
        if !v.is_empty() {
            obj.insert("app_version".into(), json!(v));
        }
    }
    // `sync_origin` stamped only when the caller supplied a
    // non-empty token. Manual exports leave the field absent;
    // the sync orchestrator passes `<install-id>:<unix_ms>` so a
    // peer device's pull can detect its own push echoing back.
    // Available since `SchemaVersions::ARCHIVE` v2.
    if let Some(o) = input.sync_origin.as_deref() {
        if !o.is_empty() {
            obj.insert("sync_origin".into(), json!(o));
        }
    }
    write_json_entry(zw, opts, "manifest.json", &Value::Object(obj))
}

fn build_sessions_value(
    conn: &impl crate::db::DbAccess,
    selected_ids: &[String],
    folder_paths: &HashMap<String, String>,
) -> Result<Value, Error> {
    let rows = sessions::list_all(conn)?;
    let want: HashSet<&str> = selected_ids.iter().map(|s| s.as_str()).collect();
    let mut arr = Vec::new();
    for r in rows.into_iter().filter(|r| want.contains(r.id.as_str())) {
        arr.push(session_row_to_json(&r, folder_paths)?);
    }
    Ok(Value::Array(arr))
}

fn session_row_to_json(
    r: &sessions::SessionRow,
    folder_paths: &HashMap<String, String>,
) -> Result<Value, Error> {
    let folder_path = r
        .folder_id
        .as_ref()
        .and_then(|id| folder_paths.get(id))
        .cloned()
        .unwrap_or_default();

    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(r.id));
    obj.insert("label".into(), json!(r.label));
    obj.insert("folder".into(), json!(folder_path));
    // `kind` omitted from the payload for SSH-kind rows so an older
    // import (pre-v5 archives) round-trips unchanged. Only WebDAV
    // and any future non-SSH kinds emit the field; the importer
    // defaults missing values to SSH on read.
    if r.kind != sessions::SESSION_KIND_SSH && !r.kind.is_empty() {
        obj.insert("kind".into(), json!(r.kind));
    }
    obj.insert("host".into(), json!(r.host));
    obj.insert("port".into(), json!(r.port));
    obj.insert("user".into(), json!(r.user));
    obj.insert("auth_type".into(), json!(r.auth_type));
    if let Some(kid) = r.key_id.as_deref() {
        if !kid.is_empty() {
            obj.insert("key_id".into(), json!(kid));
        }
    }
    obj.insert("key_path".into(), json!(r.key_path));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(r.created_at_ms)),
    );
    obj.insert(
        "updated_at".into(),
        json!(format_iso8601_utc(r.updated_at_ms)),
    );

    // `extras` is stored as a JSON string in the DB. Emit only when
    // it parses to a non-empty object (matches Dart's
    // `if (extras.isNotEmpty)` branch).
    if !r.extras.is_empty() {
        if let Ok(parsed) = serde_json::from_str::<Value>(&r.extras) {
            if let Some(obj_extras) = parsed.as_object() {
                if !obj_extras.is_empty() {
                    obj.insert("extras".into(), parsed);
                }
            }
        }
    }

    if let Some(via) = r.via_session_id.as_deref() {
        if !via.is_empty() {
            obj.insert("via_session_id".into(), json!(via));
        }
    }
    if let (Some(h), Some(p), Some(u)) = (r.via_host.as_deref(), r.via_port, r.via_user.as_deref())
    {
        if !h.is_empty() && !u.is_empty() {
            obj.insert(
                "via_override".into(),
                json!({"host": h, "port": p, "user": u}),
            );
        }
    }

    // Credentials — always written, mirroring `toJsonWithCredentials`.
    obj.insert("password".into(), json!(r.password));
    obj.insert("key_data".into(), json!(r.key_data));
    obj.insert("passphrase".into(), json!(r.passphrase));

    Ok(Value::Object(obj))
}

fn build_manager_keys_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    include_all: bool,
) -> Result<Option<Value>, Error> {
    let all_keys = ssh_keys::list_all(conn)?;
    if all_keys.is_empty() {
        return Ok(None);
    }
    let used_ids: HashSet<String> = if include_all {
        HashSet::new()
    } else {
        let want_sessions: HashSet<&str> =
            selected_session_ids.iter().map(|s| s.as_str()).collect();
        let session_rows = sessions::list_all(conn)?;
        session_rows
            .into_iter()
            .filter(|s| want_sessions.contains(s.id.as_str()))
            .filter_map(|s| s.key_id.filter(|k| !k.is_empty()))
            .collect()
    };

    let arr: Vec<Value> = all_keys
        .into_iter()
        .filter(|k| include_all || used_ids.contains(&k.id))
        .map(|k| build_key_value(&k))
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

/// Build the per-row JSON for a single `ssh_keys` row. Always emits
/// the `backend` discriminator (`software` / `fido2` / `pkcs11` /
/// `enclave` / `hello` / `tpm` / `keystore`). Per-backend payload:
///
/// | Backend | Fields | Rationale |
/// |---|---|---|
/// | `software` | private_key, public_key, key_type, label | full export today |
/// | `fido2` | public_key, key_type, label, credential_id, application_string, has_user_verification | YubiKey portable across hosts |
/// | `pkcs11` | public_key, key_type, label, pkcs11_uri, pkcs11_token_serial, pkcs11_object_id, pkcs11_object_label | hardware token plugs into new host; module path re-discovered locally |
/// | `enclave`, `hello`, `tpm`, `keystore` | public_key, key_type, label | stub — private side is device-bound |
///
/// `pkcs11_module_path` is NEVER emitted (per-host install location);
/// re-discovered on first use via the well-known-paths scan keyed on
/// `pkcs11_token_serial`.
fn build_key_value(k: &ssh_keys::SshKeyRow) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(k.id));
    obj.insert("label".into(), json!(k.label));
    obj.insert("public_key".into(), json!(k.public_key));
    obj.insert("key_type".into(), json!(k.key_type));
    obj.insert("is_generated".into(), json!(k.is_generated));
    obj.insert(
        "created_at".into(),
        json!(format_iso8601_utc(k.created_at_ms)),
    );
    obj.insert("backend".into(), json!(k.backend.as_db_str()));
    match k.backend {
        ssh_keys::KeyBackend::Software => {
            obj.insert("private_key".into(), json!(k.private_key));
        }
        ssh_keys::KeyBackend::Fido2 => {
            if let Some(ref cid) = k.credential_id {
                obj.insert("credential_id".into(), json!(cid));
            }
            if let Some(ref app) = k.application_string {
                obj.insert("application_string".into(), json!(app));
            }
            obj.insert(
                "has_user_verification".into(),
                json!(k.has_user_verification),
            );
        }
        ssh_keys::KeyBackend::Pkcs11 => {
            if let Some(ref uri) = k.pkcs11_uri {
                obj.insert("pkcs11_uri".into(), json!(uri));
            }
            if let Some(ref serial) = k.pkcs11_token_serial {
                obj.insert("pkcs11_token_serial".into(), json!(serial));
            }
            if let Some(ref oid) = k.pkcs11_object_id {
                obj.insert("pkcs11_object_id".into(), json!(oid));
            }
            if let Some(ref olabel) = k.pkcs11_object_label {
                obj.insert("pkcs11_object_label".into(), json!(olabel));
            }
        }
        ssh_keys::KeyBackend::Enclave
        | ssh_keys::KeyBackend::Hello
        | ssh_keys::KeyBackend::Tpm
        | ssh_keys::KeyBackend::Keystore => {
            // Stub backends — only the label + public_key + key_type
            // + backend discriminator travel. Device-bound material
            // (enclave_tag / hello_credential_name / tpm_* /
            // keystore_*) stays on the source device's hardware.
        }
    }
    Value::Object(obj)
}

// ── v3 child-table composers ─────────────────────────────────────

fn build_ssh_key_certificates_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    include_all_keys: bool,
) -> Result<Option<Value>, Error> {
    let all_certs = ssh_key_certificates::list_all(conn)?;
    if all_certs.is_empty() {
        return Ok(None);
    }
    // Filter to the cert rows whose parent key actually travels
    // through this export. When `include_all_keys` is true every
    // cert ships; otherwise we keep only certs whose `key_id`
    // appears in the keys-from-selected-sessions cone.
    let allowed_keys: Option<HashSet<String>> = if include_all_keys {
        None
    } else {
        let want_sessions: HashSet<&str> =
            selected_session_ids.iter().map(|s| s.as_str()).collect();
        let session_rows = sessions::list_all(conn)?;
        Some(
            session_rows
                .into_iter()
                .filter(|s| want_sessions.contains(s.id.as_str()))
                .filter_map(|s| s.key_id.filter(|k| !k.is_empty()))
                .collect(),
        )
    };
    let arr: Vec<Value> = all_certs
        .into_iter()
        .filter(|c| {
            allowed_keys
                .as_ref()
                .is_none_or(|set| set.contains(&c.key_id))
        })
        .map(|c| {
            json!({
                "key_id": c.key_id,
                "certificate": c.certificate,
                "valid_after": c.valid_after,
                "valid_before": c.valid_before,
                "principals": c.principals,
                "critical_options": c.critical_options,
                "fingerprint": c.fingerprint,
            })
        })
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_webdav_session_details_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = webdav_sessions::list_all_with_tombstones(conn)?;
        for (r, updated_at, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(webdav_row_to_value(&r, Some(updated_at), deleted_at));
        }
    } else {
        let rows = webdav_sessions::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(webdav_row_to_value(&r, None, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn webdav_row_to_value(
    r: &webdav_sessions::WebDavSessionRow,
    updated_at: Option<i64>,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("base_url".into(), json!(r.base_url));
    obj.insert("username".into(), json!(r.username));
    obj.insert("auth_method".into(), json!(r.auth_method));
    if let Some(pem) = r.trusted_cert_pem.as_deref() {
        obj.insert("trusted_cert_pem".into(), json!(pem));
    }
    if r.insecure_skip_verify {
        obj.insert("insecure_skip_verify".into(), json!(true));
    }
    // Credential bytes stay on the source device. The canonical
    // SecretStore id is reconstructed by the receiving device via
    // `webdav_secret_id(session_id)`; surfacing the id pointer keeps
    // the import path explicit about "re-enter password" without
    // embedding any secret material on the wire.
    obj.insert(
        "credential_secret_id".into(),
        json!(webdav_sessions::webdav_secret_id(&r.session_id)),
    );
    if let Some(ts) = updated_at {
        obj.insert("updated_at_ms".into(), json!(ts));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_s3_session_details_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = s3_sessions::list_all_with_tombstones(conn)?;
        for (r, updated_at, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(s3_row_to_value(&r, Some(updated_at), deleted_at));
        }
    } else {
        let rows = s3_sessions::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(s3_row_to_value(&r, None, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn s3_row_to_value(
    r: &s3_sessions::S3SessionRow,
    updated_at: Option<i64>,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("access_key_id".into(), json!(r.access_key_id));
    obj.insert("region".into(), json!(r.region));
    obj.insert("endpoint".into(), json!(r.endpoint));
    obj.insert("path_style".into(), json!(r.path_style));
    obj.insert("default_bucket".into(), json!(r.default_bucket));
    obj.insert("default_prefix".into(), json!(r.default_prefix));
    if let Some(pem) = &r.trusted_cert_pem {
        obj.insert("trusted_cert_pem".into(), json!(pem));
    }
    if r.insecure_skip_verify {
        obj.insert("insecure_skip_verify".into(), json!(true));
    }
    // Same opaque-pointer discipline as WebDAV: the access key id is
    // the public half of the AWS credential and travels verbatim;
    // the secret access key bytes don't — the receiving device finds
    // them missing and surfaces "re-enter secret access key" on
    // first connect.
    obj.insert(
        "secret_access_key_secret_id".into(),
        json!(s3_sessions::s3_secret_id(&r.session_id)),
    );
    if let Some(ts) = updated_at {
        obj.insert("updated_at_ms".into(), json!(ts));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_sftp_bookmarks_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
) -> Result<Option<Value>, Error> {
    let all_rows = sftp_bookmarks::list_all(conn)?;
    if all_rows.is_empty() {
        return Ok(None);
    }
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let arr: Vec<Value> = all_rows
        .into_iter()
        .filter(|r| want.contains(r.session_id.as_str()))
        .map(|r| {
            json!({
                "id": r.id,
                "session_id": r.session_id,
                "remote_path": r.remote_path,
                "label": r.label,
                "created_at": format_iso8601_utc(r.created_at_ms),
            })
        })
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_port_forward_rules_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
    sync_mode: bool,
) -> Result<Option<Value>, Error> {
    let want: HashSet<&str> = selected_session_ids.iter().map(|s| s.as_str()).collect();
    let mut arr: Vec<Value> = Vec::new();
    if sync_mode {
        let rows = port_forwards::list_all_with_tombstones(conn)?;
        for (r, deleted_at) in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(port_forward_row_to_value(&r, true, deleted_at));
        }
    } else {
        let rows = port_forwards::list_all(conn)?;
        for r in rows {
            if !want.contains(r.session_id.as_str()) {
                continue;
            }
            arr.push(port_forward_row_to_value(&r, false, None));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn port_forward_row_to_value(
    r: &port_forwards::PortForwardRuleRow,
    include_sync_stamps: bool,
    deleted_at: Option<i64>,
) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), json!(r.id));
    obj.insert("session_id".into(), json!(r.session_id));
    obj.insert("kind".into(), json!(r.kind));
    obj.insert("bind_host".into(), json!(r.bind_host));
    obj.insert("bind_port".into(), json!(r.bind_port));
    obj.insert("remote_host".into(), json!(r.remote_host));
    obj.insert("remote_port".into(), json!(r.remote_port));
    obj.insert("description".into(), json!(r.description));
    obj.insert("enabled".into(), json!(r.enabled));
    obj.insert("sort_order".into(), json!(r.sort_order));
    obj.insert("created_at_ms".into(), json!(r.created_at_ms));
    if include_sync_stamps {
        obj.insert("updated_at_ms".into(), json!(r.updated_at_ms));
    }
    if let Some(ts) = deleted_at {
        obj.insert("deleted_at_ms".into(), json!(ts));
        obj.insert("tombstone".into(), json!(true));
    }
    Value::Object(obj)
}

fn build_tags_value(conn: &impl crate::db::DbAccess) -> Result<Option<Value>, Error> {
    let rows = tags::list_all(conn)?;
    if rows.is_empty() {
        return Ok(None);
    }
    let arr: Vec<Value> = rows
        .into_iter()
        .map(|t| {
            json!({
                "id": t.id,
                "name": t.name,
                "color": t.color,
                "created_at": format_iso8601_utc(t.created_at_ms),
            })
        })
        .collect();
    Ok(Some(Value::Array(arr)))
}

fn build_session_tags_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
) -> Result<Option<Value>, Error> {
    let mut arr = Vec::new();
    for sid in selected_session_ids {
        let tag_ids = tags::list_session_tag_ids(conn, sid)?;
        for tid in tag_ids {
            arr.push(json!({"session_id": sid, "tag_id": tid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_folder_tags_value(conn: &impl crate::db::DbAccess) -> Result<Option<Value>, Error> {
    let folders = folders::list_all(conn)?;
    if folders.is_empty() {
        return Ok(None);
    }
    let folder_paths = build_folder_paths(conn)?;
    let mut arr = Vec::new();
    for f in folders {
        let tag_ids = tags::list_folder_tag_ids(conn, &f.id)?;
        if tag_ids.is_empty() {
            continue;
        }
        let path = folder_paths.get(&f.id).cloned().unwrap_or_default();
        for tid in tag_ids {
            arr.push(json!({"folder_path": path, "tag_id": tid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_snippets_value(conn: &impl crate::db::DbAccess) -> Result<Option<Value>, Error> {
    let rows = snippets::list_all(conn)?;
    if rows.is_empty() {
        return Ok(None);
    }
    let arr: Vec<Value> = rows
        .into_iter()
        .map(|s| {
            json!({
                "id": s.id,
                "title": s.title,
                "command": s.command,
                "description": s.description,
                "created_at": format_iso8601_utc(s.created_at_ms),
                "updated_at": format_iso8601_utc(s.updated_at_ms),
            })
        })
        .collect();
    Ok(Some(Value::Array(arr)))
}

fn build_session_snippets_value(
    conn: &impl crate::db::DbAccess,
    selected_session_ids: &[String],
) -> Result<Option<Value>, Error> {
    let mut arr = Vec::new();
    for sid in selected_session_ids {
        let snippet_ids = snippets::list_session_snippet_ids(conn, sid)?;
        for snid in snippet_ids {
            arr.push(json!({"session_id": sid, "snippet_id": snid}));
        }
    }
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn write_json_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    value: &Value,
) -> Result<(), Error> {
    let serialised = serde_json::to_vec(value)
        .map_err(|e| Error::Archive(format!("json serialise {name}: {e}")))?;
    zw.start_file(name, opts)
        .map_err(|e| Error::Archive(format!("zip start {name}: {e}")))?;
    zw.write_all(&serialised)
        .map_err(|e| Error::Archive(format!("zip write {name}: {e}")))?;
    Ok(())
}

fn write_text_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    text: &str,
) -> Result<(), Error> {
    zw.start_file(name, opts)
        .map_err(|e| Error::Archive(format!("zip start {name}: {e}")))?;
    zw.write_all(text.as_bytes())
        .map_err(|e| Error::Archive(format!("zip write {name}: {e}")))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{self, folders, known_hosts, sessions, snippets, ssh_keys, tags, Connection};
    use std::io::Read;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        db::bootstrap_schema(&conn).unwrap();
        conn
    }

    fn baseline_input() -> ExportInput {
        ExportInput {
            options: ExportOptions::default(),
            selected_session_ids: vec![],
            selected_empty_folders: vec![],
            config_json: String::new(),
            schema_version: 7,
            app_version: None,
            master_password: None,
            kdf_memory_kib: 1024,
            kdf_iterations: 1,
            kdf_parallelism: 1,
            created_at_ms: 1_700_000_000_000, // 2023-11-14T22:13:20Z
            sync_origin: None,
        }
    }

    fn read_zip(bytes: &[u8]) -> Vec<(String, Vec<u8>)> {
        let mut zr = zip::ZipArchive::new(Cursor::new(bytes.to_vec())).unwrap();
        (0..zr.len())
            .map(|i| {
                let mut f = zr.by_index(i).unwrap();
                let name = f.name().to_string();
                let mut buf = Vec::new();
                f.read_to_end(&mut buf).unwrap();
                (name, buf)
            })
            .collect()
    }

    fn json_entry(zip: &[(String, Vec<u8>)], name: &str) -> Option<Value> {
        zip.iter()
            .find(|(n, _)| n == name)
            .map(|(_, b)| serde_json::from_slice(b).unwrap())
    }

    fn text_entry<'a>(zip: &'a [(String, Vec<u8>)], name: &str) -> Option<&'a [u8]> {
        zip.iter()
            .find(|(n, _)| n == name)
            .map(|(_, b)| b.as_slice())
    }

    fn insert_session(conn: &impl crate::db::DbAccess, row: SessionRow) {
        sessions::upsert(conn, &row).unwrap();
    }

    fn make_session(id: &str, label: &str) -> SessionRow {
        SessionRow {
            id: id.into(),
            label: label.into(),
            host: format!("{id}.example.com"),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            password: format!("pw-{id}"),
            key_path: String::new(),
            key_data: String::new(),
            passphrase: String::new(),
            extras: String::new(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        }
    }

    use sessions::SessionRow;

    // ── Envelope-vs-raw boundary ───────────────────────────────

    #[test]
    fn returns_raw_zip_when_master_password_is_none() {
        let conn = fresh_db();
        let bytes = export_archive(&conn, &baseline_input()).unwrap();
        // ZIP local-file-header magic.
        assert_eq!(&bytes[..4], b"PK\x03\x04");
    }

    #[test]
    fn returns_raw_zip_when_master_password_is_empty_string() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.master_password = Some(String::new());
        let bytes = export_archive(&conn, &input).unwrap();
        assert_eq!(&bytes[..4], b"PK\x03\x04");
    }

    #[test]
    fn returns_lfse_envelope_when_master_password_is_set() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.master_password = Some("secret".into());
        let bytes = export_archive(&conn, &input).unwrap();
        // LFSE magic precedes the encrypted ZIP.
        assert_eq!(&bytes[..4], b"LFSE");
    }

    // ── manifest.json ─────────────────────────────────────────

    #[test]
    fn manifest_carries_schema_version_and_iso8601_created_at() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.schema_version = 9;
        input.created_at_ms = 1_704_067_200_000; // 2024-01-01T00:00:00Z
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").expect("manifest");
        assert_eq!(manifest["schema_version"], 9);
        assert_eq!(manifest["created_at"], "2024-01-01T00:00:00.000Z");
    }

    #[test]
    fn manifest_omits_app_version_when_none_or_empty() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.app_version = Some(String::new());
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").unwrap();
        assert!(manifest.get("app_version").is_none());
    }

    #[test]
    fn manifest_emits_sync_origin_when_caller_supplies_one() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.sync_origin = Some("install-abc:1700000000000".into());
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").unwrap();
        assert_eq!(manifest["sync_origin"], "install-abc:1700000000000");
    }

    #[test]
    fn manifest_omits_sync_origin_when_caller_supplies_none_or_empty() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.sync_origin = None;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").unwrap();
        assert!(manifest.get("sync_origin").is_none());
        // Empty string also suppresses, matching the `app_version`
        // grammar — the orchestrator never emits an empty token but
        // a malformed install id should not produce a header line
        // that pings on every peer device.
        input.sync_origin = Some(String::new());
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").unwrap();
        assert!(manifest.get("sync_origin").is_none());
    }

    #[test]
    fn manifest_includes_app_version_when_provided() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.app_version = Some("0.42.0".into());
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let manifest = json_entry(&zip, "manifest.json").unwrap();
        assert_eq!(manifest["app_version"], "0.42.0");
    }

    // ── sessions.json ─────────────────────────────────────────

    #[test]
    fn sessions_filtered_by_selected_ids() {
        let conn = fresh_db();
        // sessions::list_all sorts by sort_order ASC then label ASC,
        // so use sortable labels to lock the expected ordering.
        insert_session(&conn, make_session("s1", "alpha"));
        insert_session(&conn, make_session("s2", "bravo"));
        insert_session(&conn, make_session("s3", "charlie"));
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into(), "s3".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        let ids: Vec<&str> = arr
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, vec!["s1", "s3"]);
        // s2 must not have leaked through the filter.
        assert!(!ids.contains(&"s2"));
    }

    #[test]
    fn sessions_carry_credentials_and_core_fields() {
        let conn = fresh_db();
        let mut s = make_session("s1", "prod");
        s.password = "secret-pw".into();
        s.key_data = "PRIVATE KEY DATA".into();
        s.passphrase = "kpass".into();
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        let s0 = &arr.as_array().unwrap()[0];
        assert_eq!(s0["id"], "s1");
        assert_eq!(s0["label"], "prod");
        assert_eq!(s0["host"], "s1.example.com");
        assert_eq!(s0["port"], 22);
        assert_eq!(s0["user"], "root");
        assert_eq!(s0["auth_type"], "password");
        assert_eq!(s0["password"], "secret-pw");
        assert_eq!(s0["key_data"], "PRIVATE KEY DATA");
        assert_eq!(s0["passphrase"], "kpass");
    }

    #[test]
    fn session_folder_resolves_to_path() {
        let conn = fresh_db();
        folders::upsert(
            &conn,
            &folders::FolderRow {
                id: "f-prod".into(),
                name: "Production".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        let mut s = make_session("s1", "p1");
        s.folder_id = Some("f-prod".into());
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        assert_eq!(arr[0]["folder"], "Production");
    }

    #[test]
    fn session_folder_blank_when_session_has_no_folder() {
        let conn = fresh_db();
        insert_session(&conn, make_session("s1", "p1"));
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        assert_eq!(arr[0]["folder"], "");
    }

    #[test]
    fn session_emits_via_session_id_when_set() {
        let conn = fresh_db();
        // FK constraint: via_session_id must reference an existing
        // sessions.id row, so seed the bastion target first.
        insert_session(&conn, make_session("bastion-1", "bastion"));
        let mut s = make_session("s1", "p1");
        s.via_session_id = Some("bastion-1".into());
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        assert_eq!(arr[0]["via_session_id"], "bastion-1");
    }

    #[test]
    fn session_emits_via_override_when_full_triple_present() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.via_host = Some("jump.example.com".into());
        s.via_port = Some(2222);
        s.via_user = Some("relay".into());
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let s0 = &json_entry(&zip, "sessions.json").unwrap()[0];
        let via = s0["via_override"].as_object().expect("via_override");
        assert_eq!(via["host"], "jump.example.com");
        assert_eq!(via["port"], 2222);
        assert_eq!(via["user"], "relay");
    }

    #[test]
    fn session_omits_via_override_when_host_blank() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.via_host = Some(String::new()); // blank → suppressed
        s.via_port = Some(22);
        s.via_user = Some("u".into());
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let s0 = &json_entry(&zip, "sessions.json").unwrap()[0];
        assert!(s0.get("via_override").is_none());
    }

    #[test]
    fn session_emits_extras_only_when_object_non_empty() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.extras = r#"{"shell":"zsh"}"#.into();
        insert_session(&conn, s);
        let mut s2 = make_session("s2", "p2");
        s2.extras = "{}".into();
        insert_session(&conn, s2);
        let mut s3 = make_session("s3", "p3");
        s3.extras = String::new();
        insert_session(&conn, s3);
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into(), "s2".into(), "s3".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "sessions.json").unwrap();
        // s1 → extras present
        assert_eq!(arr[0]["extras"]["shell"], "zsh");
        // s2 → empty object suppressed
        assert!(arr[1].get("extras").is_none());
        // s3 → empty string suppressed
        assert!(arr[2].get("extras").is_none());
    }

    // ── empty_folders.json ────────────────────────────────────

    #[test]
    fn empty_folders_emitted_when_list_non_empty() {
        let conn = fresh_db();
        insert_session(&conn, make_session("s1", "p1"));
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        input.selected_empty_folders = vec!["A/B".into(), "C".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "empty_folders.json").unwrap();
        assert_eq!(arr, json!(["A/B", "C"]));
    }

    #[test]
    fn empty_folders_omitted_when_list_empty() {
        let conn = fresh_db();
        insert_session(&conn, make_session("s1", "p1"));
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(json_entry(&zip, "empty_folders.json").is_none());
    }

    // ── keys.json ─────────────────────────────────────────────

    fn insert_key(conn: &impl crate::db::DbAccess, id: &str, label: &str) {
        ssh_keys::upsert(
            conn,
            &ssh_keys::SshKeyRow {
                id: id.into(),
                label: label.into(),
                private_key: format!("PRIV-{id}"),
                public_key: format!("PUB-{id}"),
                key_type: "ed25519".into(),
                is_generated: true,
                created_at_ms: 1_700_000_000_000,
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
            },
        )
        .unwrap();
    }

    #[test]
    fn keys_omitted_when_has_manager_keys_false() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "k-1");
        let mut input = baseline_input();
        input.options.has_manager_keys = false;
        input.options.include_all_manager_keys = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(json_entry(&zip, "keys.json").is_none());
    }

    #[test]
    fn keys_include_all_when_include_all_manager_keys_true() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "k-1");
        insert_key(&conn, "k2", "k-2");
        let mut input = baseline_input();
        input.options.has_manager_keys = true;
        input.options.include_all_manager_keys = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "keys.json").unwrap();
        let ids: Vec<&str> = arr
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&"k1"));
        assert!(ids.contains(&"k2"));
    }

    #[test]
    fn keys_filter_by_selected_sessions_when_include_all_false() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "k-1");
        insert_key(&conn, "k2", "k-2");
        let mut s = make_session("s1", "p1");
        s.key_id = Some("k1".into());
        insert_session(&conn, s);
        let mut input = baseline_input();
        input.options.has_manager_keys = true;
        input.options.include_all_manager_keys = false;
        input.selected_session_ids = vec!["s1".into()];
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "keys.json").unwrap();
        let ids: Vec<&str> = arr
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, vec!["k1"]);
    }

    #[test]
    fn keys_carry_private_and_public_pem_bytes() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "label-1");
        let mut input = baseline_input();
        input.options.has_manager_keys = true;
        input.options.include_all_manager_keys = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let k0 = &json_entry(&zip, "keys.json").unwrap()[0];
        assert_eq!(k0["id"], "k1");
        assert_eq!(k0["label"], "label-1");
        assert_eq!(k0["private_key"], "PRIV-k1");
        assert_eq!(k0["public_key"], "PUB-k1");
        assert_eq!(k0["key_type"], "ed25519");
        assert_eq!(k0["is_generated"], true);
    }

    // ── tags.json + session_tags.json + folder_tags.json ──────

    fn insert_tag(conn: &impl crate::db::DbAccess, id: &str, name: &str) {
        tags::upsert(
            conn,
            &tags::TagRow {
                id: id.into(),
                name: name.into(),
                color: Some("#abcdef".into()),
                created_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
    }

    #[test]
    fn tags_entry_omitted_when_no_tags() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_tags = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(json_entry(&zip, "tags.json").is_none());
        assert!(json_entry(&zip, "session_tags.json").is_none());
    }

    #[test]
    fn tags_entry_includes_name_color_id() {
        let conn = fresh_db();
        insert_tag(&conn, "t-prod", "prod");
        let mut input = baseline_input();
        input.options.include_tags = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let t0 = &json_entry(&zip, "tags.json").unwrap()[0];
        assert_eq!(t0["id"], "t-prod");
        assert_eq!(t0["name"], "prod");
        assert_eq!(t0["color"], "#abcdef");
    }

    #[test]
    fn session_tags_emitted_for_selected_sessions_only() {
        let conn = fresh_db();
        insert_tag(&conn, "t1", "tag-1");
        insert_session(&conn, make_session("s1", "p1"));
        insert_session(&conn, make_session("s2", "p2"));
        tags::link_session_tag(&conn, "s1", "t1").unwrap();
        tags::link_session_tag(&conn, "s2", "t1").unwrap();
        let mut input = baseline_input();
        input.options.include_tags = true;
        input.selected_session_ids = vec!["s1".into()]; // only s1
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "session_tags.json").unwrap();
        assert_eq!(arr.as_array().unwrap().len(), 1);
        assert_eq!(arr[0]["session_id"], "s1");
        assert_eq!(arr[0]["tag_id"], "t1");
    }

    #[test]
    fn folder_tags_emitted_with_resolved_folder_path() {
        let conn = fresh_db();
        insert_tag(&conn, "t1", "tag-1");
        folders::upsert(
            &conn,
            &folders::FolderRow {
                id: "f1".into(),
                name: "Prod".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        tags::link_folder_tag(&conn, "f1", "t1").unwrap();
        let mut input = baseline_input();
        input.options.include_tags = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "folder_tags.json").unwrap();
        assert_eq!(arr[0]["folder_path"], "Prod");
        assert_eq!(arr[0]["tag_id"], "t1");
    }

    // ── snippets.json + session_snippets.json ─────────────────

    fn insert_snippet(conn: &impl crate::db::DbAccess, id: &str, title: &str) {
        snippets::upsert(
            conn,
            &snippets::SnippetRow {
                id: id.into(),
                title: title.into(),
                command: format!("echo {id}"),
                description: format!("desc-{id}"),
                created_at_ms: 1_700_000_000_000,
                updated_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
    }

    #[test]
    fn snippets_omitted_when_none() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_snippets = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(json_entry(&zip, "snippets.json").is_none());
    }

    #[test]
    fn snippets_include_title_command_description() {
        let conn = fresh_db();
        insert_snippet(&conn, "sn1", "list");
        let mut input = baseline_input();
        input.options.include_snippets = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let s0 = &json_entry(&zip, "snippets.json").unwrap()[0];
        assert_eq!(s0["id"], "sn1");
        assert_eq!(s0["title"], "list");
        assert_eq!(s0["command"], "echo sn1");
        assert_eq!(s0["description"], "desc-sn1");
    }

    #[test]
    fn session_snippets_filtered_by_selected_sessions() {
        let conn = fresh_db();
        insert_snippet(&conn, "sn1", "list");
        insert_session(&conn, make_session("s1", "p1"));
        insert_session(&conn, make_session("s2", "p2"));
        snippets::link_session_snippet(&conn, "s1", "sn1").unwrap();
        snippets::link_session_snippet(&conn, "s2", "sn1").unwrap();
        let mut input = baseline_input();
        input.options.include_snippets = true;
        input.selected_session_ids = vec!["s2".into()]; // only s2
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let arr = json_entry(&zip, "session_snippets.json").unwrap();
        assert_eq!(arr.as_array().unwrap().len(), 1);
        assert_eq!(arr[0]["session_id"], "s2");
        assert_eq!(arr[0]["snippet_id"], "sn1");
    }

    // ── known_hosts ───────────────────────────────────────────

    #[test]
    fn known_hosts_omitted_when_db_is_empty() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_known_hosts = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(text_entry(&zip, "known_hosts.txt").is_none());
    }

    #[test]
    fn known_hosts_emitted_with_db_rows_when_present() {
        let conn = fresh_db();
        known_hosts::upsert_by_host_port(
            &conn,
            "example.com",
            22,
            "ssh-ed25519",
            "AAAAB3NzaC1lZDI1NTE5AAAAINexampleKey",
            1_700_000_000_000,
        )
        .unwrap();
        let mut input = baseline_input();
        input.options.include_known_hosts = true;
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let body = text_entry(&zip, "known_hosts.txt").expect("known_hosts entry");
        let s = std::str::from_utf8(body).unwrap();
        assert!(s.contains("example.com"));
        assert!(s.contains("ssh-ed25519"));
        assert!(s.contains("AAAAB3NzaC1lZDI1NTE5AAAAINexampleKey"));
    }

    // ── config ───────────────────────────────────────────────

    #[test]
    fn config_emitted_verbatim_when_toggle_on() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = r#"{"theme":"dark"}"#.into();
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let body = text_entry(&zip, "config.json").expect("config entry");
        assert_eq!(body, br#"{"theme":"dark"}"#);
    }

    #[test]
    fn config_omitted_when_toggle_off_even_with_payload() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = false;
        input.config_json = r#"{"theme":"dark"}"#.into();
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(text_entry(&zip, "config.json").is_none());
    }

    #[test]
    fn config_omitted_when_toggle_on_but_payload_empty() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = String::new();
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        assert!(text_entry(&zip, "config.json").is_none());
    }

    #[test]
    fn config_in_archive_never_carries_config_schema_version() {
        // `to_json_value` stamps `config_schema_version` on every
        // write so the migration runner can route old shapes; the
        // export pipeline must strip it before the JSON lands inside
        // an `.lfs` archive (per-host stamp would otherwise pin the
        // importer to the exporter's bump cadence). Round-trip
        // through `strip_for_export` and assert the wire never
        // carries the field, regardless of which schema version the
        // exporter was on.
        let cfg = crate::config::AppConfig::default();
        let mut json = cfg.to_json_value();
        // Sanity: the source has the stamp before stripping.
        assert!(json
            .as_object()
            .and_then(|o| o.get("config_schema_version"))
            .is_some());
        crate::config::strip_for_export(&mut json);
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = json.to_string();
        let bytes = export_archive(&conn, &input).unwrap();
        let zip = read_zip(&bytes);
        let body = text_entry(&zip, "config.json").expect("config entry");
        let archived: Value = serde_json::from_slice(body).expect("parse archived config");
        assert!(
            archived
                .as_object()
                .and_then(|o| o.get("config_schema_version"))
                .is_none(),
            "archived config.json must not carry config_schema_version; got: {archived}"
        );
    }

    // ── Toggles + ordering ────────────────────────────────────

    #[test]
    fn all_toggles_off_yields_only_manifest() {
        let conn = fresh_db();
        let bytes = export_archive(&conn, &baseline_input()).unwrap();
        let zip = read_zip(&bytes);
        assert_eq!(zip.len(), 1);
        assert_eq!(zip[0].0, "manifest.json");
    }

    #[test]
    fn entries_use_stored_compression() {
        let conn = fresh_db();
        let bytes = export_archive(&conn, &baseline_input()).unwrap();
        // Stored mode: bytes 8..10 of the local file header are the
        // compression-method u16 little-endian (0 = stored, 8 = deflate).
        // Local file header begins at offset 0; method is at offset 8.
        let method = u16::from_le_bytes([bytes[8], bytes[9]]);
        assert_eq!(method, 0, "manifest entry must be stored, not deflated");
    }
}
