//! `.lfs` archive export orchestrator. Composes the on-disk archive
//! format Dart's `ExportImport` reads, but does the work entirely
//! inside Rust so plaintext credentials never round-trip through the
//! Dart heap during a user-initiated export.
//!
//! # Wire compatibility
//!
//! Output is byte-compatible with the existing Dart writer:
//!
//! - Stored-mode ZIP carrying named entries (manifest.json,
//!   sessions.json, keys.json, …).
//! - Optional outer encryption: `LFSE` magic (4) + version byte
//!   (`0x02` = Argon2id) + KdfParams (algorithm id + memory KiB +
//!   iters + parallelism, 10 bytes for Argon2id) + 32-byte salt +
//!   12-byte IV + AES-256-GCM ciphertext.
//!
//! # Boundary contract
//!
//! Every plaintext byte (session passwords / key PEM / passphrases)
//! is read straight from the encrypted DB into a Rust-owned `Vec<u8>`,
//! threaded through `serde_json::Value` for shape preservation, and
//! handed to AES-GCM. The Dart caller passes only the export options
//! plus the pre-serialised `config_json` string (since `config.json`
//! is file-based, not in `lfs_core.db`) and receives the encrypted
//! archive bytes ready to write atomically.

use std::collections::{HashMap, HashSet};
use std::io::{Cursor, Write};

use rand::rngs::OsRng;
use rand::RngCore;
use rusqlite::Connection;
use serde_json::{json, Value};
use zeroize::Zeroizing;
use zip::write::SimpleFileOptions;

use crate::crypto::{aes_gcm_encrypt_raw, argon2id_derive};
use crate::db::{folders, known_hosts, sessions, snippets, ssh_keys, tags};
use crate::error::Error;

/// LFSE encrypted-archive magic (`'L','F','S','E'`).
const ENC_HEADER_MAGIC: [u8; 4] = [0x4C, 0x46, 0x53, 0x45];
/// Version byte for the Argon2id + AES-GCM envelope.
const ENC_VERSION_ARGON2ID: u8 = 0x02;
/// Algorithm id for Argon2id in the embedded KdfParams block.
const KDF_ALGO_ARGON2ID: u8 = 0x01;
const SALT_LEN: usize = 32;
const IV_LEN: usize = 12;
const AES_KEY_LEN: u32 = 32;

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
/// / known-hosts come straight from `lfs_core.db`; only `config_json`
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
    /// Argon2id parameters when `master_password` is set. Dart's
    /// `KdfParams.productionDefaults` are 46 MiB / t=2 / p=1.
    pub kdf_memory_kib: u32,
    pub kdf_iterations: u32,
    pub kdf_parallelism: u32,
    /// Unix millis to stamp into `manifest.created_at`. Passed in
    /// rather than read from the system clock so callers can pin a
    /// deterministic timestamp during tests.
    pub created_at_ms: i64,
}

/// Compose and (optionally) encrypt the `.lfs` archive.
///
/// Returns the bytes the caller writes atomically to the chosen
/// path. Errors at any stage abort the archive — partial output is
/// never returned, mirroring Dart's `tmp + rename` discipline.
pub fn export_archive(conn: &Connection, input: &ExportInput) -> Result<Vec<u8>, Error> {
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

fn build_zip(conn: &Connection, input: &ExportInput) -> Result<Vec<u8>, Error> {
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
            write_text_entry(&mut zw, opts, "known_hosts", &kh)?;
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

    zw.finish()
        .map_err(|e| Error::Io(format!("zip finish: {e}")))?;
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
    write_json_entry(zw, opts, "manifest.json", &Value::Object(obj))
}

fn build_sessions_value(
    conn: &Connection,
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
    conn: &Connection,
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
        .map(|k| {
            json!({
                "id": k.id,
                "label": k.label,
                "private_key": k.private_key,
                "public_key": k.public_key,
                "key_type": k.key_type,
                "is_generated": k.is_generated,
                "created_at": format_iso8601_utc(k.created_at_ms),
            })
        })
        .collect();
    if arr.is_empty() {
        Ok(None)
    } else {
        Ok(Some(Value::Array(arr)))
    }
}

fn build_known_hosts(conn: &Connection) -> Result<String, Error> {
    let rows = known_hosts::list_all(conn)?;
    if rows.is_empty() {
        return Ok(String::new());
    }
    // Wire format mirrors `KnownHostsManager.exportToString`:
    // `host:port keytype base64key\n` per row.
    let mut out = String::new();
    for r in rows {
        out.push_str(&format!(
            "{}:{} {} {}\n",
            r.host, r.port, r.key_type, r.key_base64
        ));
    }
    Ok(out)
}

fn build_tags_value(conn: &Connection) -> Result<Option<Value>, Error> {
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
    conn: &Connection,
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

fn build_folder_tags_value(conn: &Connection) -> Result<Option<Value>, Error> {
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

fn build_snippets_value(conn: &Connection) -> Result<Option<Value>, Error> {
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
    conn: &Connection,
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

/// Build `{folder_id → "Parent/Child/Leaf"}` by walking the
/// `folders` table. Detached / cyclic chains are resolved
/// best-effort: a hop into an unknown parent_id terminates the path
/// at the last reachable node, matching the loader's tolerance.
fn build_folder_paths(conn: &Connection) -> Result<HashMap<String, String>, Error> {
    let rows = folders::list_all(conn)?;
    let by_id: HashMap<String, &folders::FolderRow> =
        rows.iter().map(|r| (r.id.clone(), r)).collect();
    let mut out = HashMap::new();
    for r in &rows {
        let mut parts: Vec<&str> = Vec::new();
        let mut cursor = Some(r);
        let mut seen: HashSet<&str> = HashSet::new();
        while let Some(node) = cursor {
            if !seen.insert(node.id.as_str()) {
                break;
            }
            parts.push(node.name.as_str());
            cursor = node
                .parent_id
                .as_deref()
                .and_then(|pid| by_id.get(pid).copied());
        }
        parts.reverse();
        out.insert(r.id.clone(), parts.join("/"));
    }
    Ok(out)
}

fn write_json_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    value: &Value,
) -> Result<(), Error> {
    let serialised =
        serde_json::to_vec(value).map_err(|e| Error::Io(format!("json serialise {name}: {e}")))?;
    zw.start_file(name, opts)
        .map_err(|e| Error::Io(format!("zip start {name}: {e}")))?;
    zw.write_all(&serialised)
        .map_err(|e| Error::Io(format!("zip write {name}: {e}")))?;
    Ok(())
}

fn write_text_entry(
    zw: &mut zip::ZipWriter<&mut Cursor<Vec<u8>>>,
    opts: SimpleFileOptions,
    name: &str,
    text: &str,
) -> Result<(), Error> {
    zw.start_file(name, opts)
        .map_err(|e| Error::Io(format!("zip start {name}: {e}")))?;
    zw.write_all(text.as_bytes())
        .map_err(|e| Error::Io(format!("zip write {name}: {e}")))?;
    Ok(())
}

fn encrypt_with_password(
    zip_bytes: &[u8],
    password: &str,
    memory_kib: u32,
    iterations: u32,
    parallelism: u32,
) -> Result<Vec<u8>, Error> {
    let mut salt = [0u8; SALT_LEN];
    let mut iv = [0u8; IV_LEN];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut iv);

    let derived = Zeroizing::new(argon2id_derive(
        password.as_bytes(),
        &salt,
        memory_kib,
        iterations,
        parallelism,
        AES_KEY_LEN,
    )?);
    let ct = aes_gcm_encrypt_raw(&derived, &iv, zip_bytes, &[])?;

    // Header layout — must match the Dart reader byte-for-byte:
    //   magic (4) || version (1) || KdfParams (10) || salt (32) || iv (12) || ct
    let mut out = Vec::with_capacity(4 + 1 + 10 + SALT_LEN + IV_LEN + ct.len());
    out.extend_from_slice(&ENC_HEADER_MAGIC);
    out.push(ENC_VERSION_ARGON2ID);
    // KdfParams.encode() — Argon2id only.
    out.push(KDF_ALGO_ARGON2ID);
    out.extend_from_slice(&memory_kib.to_be_bytes());
    out.extend_from_slice(&iterations.to_be_bytes());
    out.push(parallelism.min(u8::MAX as u32) as u8);
    out.extend_from_slice(&salt);
    out.extend_from_slice(&iv);
    out.extend_from_slice(&ct);
    Ok(out)
}

/// Format a unix-millis timestamp as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
/// Matches what `DateTime.fromMillisecondsSinceEpoch(ms, isUtc:
/// true).toIso8601String()` would emit and parses cleanly through
/// Dart's `DateTime.tryParse`.
fn format_iso8601_utc(ms: i64) -> String {
    let secs_total = ms.div_euclid(1000);
    let millis = ms.rem_euclid(1000) as u32;
    let (year, month, day, hh, mm, ss) = unix_to_civil(secs_total);
    format!("{year:04}-{month:02}-{day:02}T{hh:02}:{mm:02}:{ss:02}.{millis:03}Z")
}

/// Howard Hinnant's date algorithm — convert unix seconds to
/// `(Y, M, D, h, m, s)` UTC. Pure integer arithmetic, no leap-second
/// table. Handles negative inputs (1970-01-01 boundary safe).
fn unix_to_civil(secs: i64) -> (i64, u32, u32, u32, u32, u32) {
    let days = secs.div_euclid(86_400);
    let time_of_day = secs.rem_euclid(86_400) as u32;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = if m <= 2 { y + 1 } else { y };
    let hh = time_of_day / 3600;
    let mm = (time_of_day % 3600) / 60;
    let ss = time_of_day % 60;
    (year, m, d, hh, mm, ss)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso8601_known_value() {
        // 2026-04-26T00:00:00.000Z → ms = 1777161600000
        assert_eq!(
            format_iso8601_utc(1_777_161_600_000),
            "2026-04-26T00:00:00.000Z"
        );
    }

    #[test]
    fn iso8601_handles_millis() {
        assert_eq!(
            format_iso8601_utc(1_777_161_600_123),
            "2026-04-26T00:00:00.123Z"
        );
    }

    #[test]
    fn iso8601_pre_epoch() {
        // 1969-12-31T23:59:59.000Z → ms = -1000
        assert_eq!(format_iso8601_utc(-1000), "1969-12-31T23:59:59.000Z");
    }
}
