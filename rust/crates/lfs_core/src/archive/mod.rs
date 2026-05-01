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
use std::io::{Cursor, Read, Write};

use rusqlite::Connection;
use serde_json::{json, Value};
use zip::write::SimpleFileOptions;
use zip::ZipArchive;

use crate::db::{folders, known_hosts, sessions, snippets, ssh_keys, tags};
use crate::error::Error;

pub mod envelope;
pub(crate) mod iso8601;
pub mod qr_compose;

pub use envelope::decrypt_archive_with_password;
pub use qr_compose::{qr_export_payload, qr_export_payload_size, QrExportInput, QrExportOptions};

use envelope::{encrypt_with_password, ENC_HEADER_MAGIC};
use iso8601::{format_iso8601_utc, parse_iso8601_or_now};

/// Wire-format version stamped into the QR payload's `v` field.
/// Mirrors `_currentFormatVersion` in `lib/core/session/qr_codec.dart`
/// — bump there and here in lockstep.
const QR_FORMAT_VERSION: i64 = 4;

// ---- 5.6 import handle scaffolding -------------------------------
// The import flow is two-phase: Rust decrypts + parses the
// archive, the user reviews a sanitized preview in Dart, then
// the user confirms and Rust applies the cached blob through
// the DAO layer. The handle pattern keeps the decoded entries
// inside Rust so they never round-trip through the Dart heap as
// they would today (`core/import/import_service.dart` walks the
// decoded `ImportResult` Dart-side).
//
// Today the registry only owns the handle slot + sanitized
// preview shape; the apply driver lands in the next 5.6 commit
// alongside the Dart-side `ImportService` retire.

/// Stable handle id for an in-flight import. Allocated Dart-side
/// via `Uuid().v4()` so the same string flows through Riverpod
/// ownership before Rust finishes the decrypt.
pub type ImportHandleId = String;

/// Sanitized preview the FRB layer hands to Dart after
/// `import_decrypt` resolves. Carries counts + non-secret labels
/// so the preview dialog can render without ever materialising
/// session passwords / key PEM bytes on the Dart heap.
#[derive(Debug, Clone)]
pub struct ImportPreview {
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

/// Decrypted-but-not-yet-applied import. Held inside the registry
/// under the caller-supplied handle id; the apply driver consumes
/// the entries in place. The actual entry payload is just the
/// raw JSON byte buffers extracted from the ZIP — the apply step
/// parses + writes per-entity through the DAO layer.
#[derive(Debug, Clone)]
pub struct PendingImport {
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

impl PendingImport {
    pub fn preview(&self, schema_version: i64) -> ImportPreview {
        let session_labels = self
            .sessions_json
            .as_deref()
            .and_then(|s| serde_json::from_str::<Vec<serde_json::Value>>(s).ok())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| {
                        v.get("label")
                            .and_then(|l| l.as_str())
                            .map(|l| l.to_string())
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let session_count = session_labels.len() as i64;
        let manager_key_count = json_array_len(self.keys_json.as_deref());
        let tag_count = json_array_len(self.tags_json.as_deref());
        let snippet_count = json_array_len(self.snippets_json.as_deref());
        let empty_folder_count = json_array_len(self.empty_folders_json.as_deref());
        ImportPreview {
            schema_version,
            session_count,
            session_labels,
            manager_key_count,
            tag_count,
            snippet_count,
            empty_folder_count,
            has_config: self.config_json.as_deref().is_some_and(|s| !s.is_empty()),
            has_known_hosts: self
                .known_hosts_text
                .as_deref()
                .is_some_and(|s| !s.is_empty()),
        }
    }
}

fn json_array_len(s: Option<&str>) -> i64 {
    s.and_then(|s| serde_json::from_str::<Vec<serde_json::Value>>(s).ok())
        .map(|v| v.len() as i64)
        .unwrap_or(0)
}

/// Process-singleton import handle registry. Owned by `AppState`.
pub struct ImportRegistry {
    inner: std::sync::Mutex<std::collections::HashMap<ImportHandleId, PendingImport>>,
}

impl ImportRegistry {
    pub fn new() -> Self {
        Self {
            inner: std::sync::Mutex::new(std::collections::HashMap::new()),
        }
    }

    fn lock(
        &self,
    ) -> std::sync::MutexGuard<'_, std::collections::HashMap<ImportHandleId, PendingImport>> {
        self.inner.lock().expect("import registry mutex poisoned")
    }

    pub fn insert(&self, id: ImportHandleId, pending: PendingImport) {
        self.lock().insert(id, pending);
    }

    pub fn take(&self, id: &str) -> Option<PendingImport> {
        self.lock().remove(id)
    }

    pub fn get_clone(&self, id: &str) -> Option<PendingImport> {
        self.lock().get(id).cloned()
    }

    pub fn drop_handle(&self, id: &str) {
        self.lock().remove(id);
    }

    pub fn count(&self) -> usize {
        self.lock().len()
    }
}

impl Default for ImportRegistry {
    fn default() -> Self {
        Self::new()
    }
}

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

/// Read every entry in the ZIP and pack the recognised JSON /
/// text payloads into a [`PendingImport`]. Unknown entries are
/// dropped — the apply driver is the source of truth for which
/// entries actually move data, the preview just reports counts.
pub fn parse_pending_import(zip_bytes: &[u8]) -> Result<(PendingImport, i64), Error> {
    let cursor = Cursor::new(zip_bytes);
    let mut zip =
        ZipArchive::new(cursor).map_err(|e| Error::Io(format!("import zip open: {e}")))?;

    let mut pending = PendingImport {
        manifest_json: None,
        sessions_json: None,
        keys_json: None,
        tags_json: None,
        session_tags_json: None,
        folder_tags_json: None,
        snippets_json: None,
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
    };

    for i in 0..zip.len() {
        let mut entry = zip
            .by_index(i)
            .map_err(|e| Error::Io(format!("import zip entry {i}: {e}")))?;
        let name = entry.name().to_string();
        let mut buf = String::new();
        entry
            .read_to_string(&mut buf)
            .map_err(|e| Error::Io(format!("import read {name}: {e}")))?;
        match name.as_str() {
            "manifest.json" => pending.manifest_json = Some(buf),
            "sessions.json" => pending.sessions_json = Some(buf),
            "keys.json" => pending.keys_json = Some(buf),
            "tags.json" => pending.tags_json = Some(buf),
            "session_tags.json" => pending.session_tags_json = Some(buf),
            "folder_tags.json" => pending.folder_tags_json = Some(buf),
            "snippets.json" => pending.snippets_json = Some(buf),
            "session_snippets.json" => pending.session_snippets_json = Some(buf),
            "empty_folders.json" => pending.empty_folders_json = Some(buf),
            "config.json" => pending.config_json = Some(buf),
            "known_hosts.txt" => pending.known_hosts_text = Some(buf),
            _ => {}
        }
    }

    let schema_version = pending
        .manifest_json
        .as_deref()
        .and_then(|s| serde_json::from_str::<Value>(s).ok())
        .and_then(|v| v.get("schema_version").and_then(|x| x.as_i64()))
        .unwrap_or(0);
    Ok((pending, schema_version))
}

/// Read the file at `path`, detect whether it's an LFSE envelope
/// (4-byte magic) or a raw ZIP (`PK\x03\x04`), decrypt+parse, and
/// return the preview the apply driver consumes. The decoded
/// `PendingImport` is *not* registered here — the FRB layer
/// stages it into [`crate::app::AppState::imports`] after the
/// caller approves the preview.
pub fn read_archive_to_pending(
    path: &str,
    password: &str,
) -> Result<(PendingImport, ImportPreview), Error> {
    let bytes = std::fs::read(path).map_err(|e| Error::Io(format!("import read {path}: {e}")))?;
    let zip_bytes = if bytes.len() >= 4 && bytes[..4] == ENC_HEADER_MAGIC {
        decrypt_archive_with_password(&bytes, password)?
    } else if bytes.len() >= 4 && &bytes[..4] == b"PK\x03\x04" {
        bytes
    } else {
        return Err(Error::Io(format!(
            "{path}: not an LFSE archive or ZIP file"
        )));
    };
    let (pending, schema_version) = parse_pending_import(&zip_bytes)?;
    let preview = pending.preview(schema_version);
    Ok((pending, preview))
}

/// Apply mode — `Merge` upserts, `Replace` clears the matching
/// kinds first inside a transaction so a partial failure rolls
/// back cleanly. Mirrors the Dart `ImportMode` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ImportMode {
    #[default]
    Merge,
    Replace,
}

/// What entries the apply driver should commit. Mirrors the
/// Dart `ImportOptions` toggle set; turning a flag off skips
/// every entry of that kind, even if the staged JSON carries it.
#[derive(Debug, Clone, Default)]
pub struct ApplyOptions {
    pub mode: ImportMode,
    pub apply_sessions: bool,
    pub apply_keys: bool,
    pub apply_tags: bool,
    pub apply_snippets: bool,
    pub apply_known_hosts: bool,
}

/// Aggregate counters the apply driver returns. `errors` carries
/// per-entry parse failures encountered along the way — apply
/// keeps going past a bad row so a single corrupt session in a
/// 500-host archive doesn't abort the whole import.
#[derive(Debug, Clone, Default)]
pub struct ApplyResult {
    pub sessions_applied: i64,
    pub keys_applied: i64,
    pub keys_skipped_dedup: i64,
    pub tags_applied: i64,
    pub snippets_applied: i64,
    pub known_hosts_applied: i64,
    pub folders_applied: i64,
    pub session_tags_applied: i64,
    pub session_snippets_applied: i64,
    pub errors: Vec<String>,
}

/// Apply a staged [`PendingImport`].
///
/// **Merge mode** upserts every entry by id; collisions update
/// the existing row's mutable columns. Known-hosts upsert by
/// `(host, port)`; manager keys dedup by public-key fingerprint
/// so a key already on disk does not double-land under the
/// archive's id. Folder paths from `sessions.json` flatten
/// into a per-archive folder tree; ids are minted fresh.
///
/// **Replace mode** runs every stage inside a single sqlite
/// transaction. For each enabled kind, the existing rows clear
/// before the archive entries insert; a downstream parse error
/// rolls the whole transaction back, so a botched import never
/// leaves the DB half-overwritten. Junctions (`session_tags`,
/// `session_snippets`) are cleared alongside their owning
/// kinds (sessions / tags).
///
/// `now_ms` stamps the rows that lack a timestamp in the
/// archive (apply moment as the effective `created_at` /
/// `updated_at`).
pub fn apply_pending_import(
    conn: &mut Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    match options.mode {
        ImportMode::Merge => {
            let mut result = ApplyResult::default();
            run_apply(conn, pending, options, now_ms, &mut result);
            Ok(result)
        }
        ImportMode::Replace => {
            let tx = conn
                .transaction()
                .map_err(|e| Error::Io(format!("apply tx begin: {e}")))?;
            let mut result = ApplyResult::default();
            run_replace_clear(&tx, options, &mut result);
            run_apply(&tx, pending, options, now_ms, &mut result);
            tx.commit()
                .map_err(|e| Error::Io(format!("apply tx commit: {e}")))?;
            Ok(result)
        }
    }
}

/// Backwards-compatible alias. Existing callers route through
/// here; the new mode-aware entry point is
/// [`apply_pending_import`].
pub fn apply_pending_import_merge(
    conn: &Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    let mut result = ApplyResult::default();
    run_apply(conn, pending, options, now_ms, &mut result);
    Ok(result)
}

fn run_apply(
    conn: &Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    if options.apply_keys {
        if let Some(json) = pending.keys_json.as_deref() {
            apply_keys(conn, json, now_ms, result);
        }
    }
    // Apply folders + sessions together so session.folder_id
    // resolves through the freshly-inserted folder tree.
    let mut folder_path_to_id: HashMap<String, String> = HashMap::new();
    if options.apply_sessions {
        if let Some(json) = pending.sessions_json.as_deref() {
            folder_path_to_id = apply_folder_tree(conn, json, now_ms, result);
            apply_sessions(conn, json, &folder_path_to_id, now_ms, result);
        }
        if let Some(json) = pending.empty_folders_json.as_deref() {
            apply_empty_folders(conn, json, &mut folder_path_to_id, now_ms, result);
        }
    }
    if options.apply_tags {
        if let Some(json) = pending.tags_json.as_deref() {
            apply_tags(conn, json, now_ms, result);
        }
    }
    if options.apply_sessions && options.apply_tags {
        if let Some(json) = pending.session_tags_json.as_deref() {
            apply_session_tags(conn, json, result);
        }
    }
    if options.apply_snippets {
        if let Some(json) = pending.snippets_json.as_deref() {
            apply_snippets(conn, json, now_ms, result);
        }
    }
    if options.apply_sessions && options.apply_snippets {
        if let Some(json) = pending.session_snippets_json.as_deref() {
            apply_session_snippets(conn, json, result);
        }
    }
    if options.apply_known_hosts {
        if let Some(text) = pending.known_hosts_text.as_deref() {
            apply_known_hosts(conn, text, now_ms, result);
        }
    }
}

fn run_replace_clear(conn: &Connection, options: &ApplyOptions, result: &mut ApplyResult) {
    // Order matters — junctions clear before their owning rows
    // so the FKs stay sane. Each `delete_all` is idempotent on
    // an already-empty table.
    if options.apply_sessions {
        if let Err(e) = sessions::delete_all(conn) {
            result.errors.push(format!("replace clear sessions: {e}"));
        }
        if let Err(e) = folders::delete_all(conn) {
            result.errors.push(format!("replace clear folders: {e}"));
        }
    }
    if options.apply_tags {
        if let Err(e) = tags::delete_all(conn) {
            result.errors.push(format!("replace clear tags: {e}"));
        }
    }
    if options.apply_snippets {
        if let Err(e) = snippets::delete_all(conn) {
            result.errors.push(format!("replace clear snippets: {e}"));
        }
    }
    if options.apply_known_hosts {
        if let Err(e) = known_hosts::clear_all(conn) {
            result
                .errors
                .push(format!("replace clear known_hosts: {e}"));
        }
    }
    // Manager keys are intentionally NOT wiped on replace — the
    // user's existing keys stay valid; the archive's keys merge
    // by fingerprint as in merge mode. Mirrors the Dart impl.
}

fn apply_folder_tree(
    conn: &Connection,
    sessions_json: &str,
    now_ms: i64,
    result: &mut ApplyResult,
) -> HashMap<String, String> {
    use rand::RngCore;
    let arr = match serde_json::from_str::<Vec<Value>>(sessions_json) {
        Ok(a) => a,
        Err(_) => return HashMap::new(),
    };
    // Collect every distinct folder path from sessions.
    let mut paths: HashSet<String> = HashSet::new();
    for v in &arr {
        if let Some(p) = v.get("folder").and_then(|x| x.as_str()) {
            if !p.is_empty() {
                paths.insert(p.to_string());
            }
        }
    }
    let mut path_to_id: HashMap<String, String> = HashMap::new();
    let mut sort_order: i64 = 0;
    let mut sorted: Vec<String> = paths.into_iter().collect();
    sorted.sort();
    for path in sorted {
        // Walk from root → leaf so each segment's parent_id
        // resolves before the child lands.
        let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        let mut parent_id: Option<String> = None;
        let mut accum = String::new();
        for seg in segments {
            if !accum.is_empty() {
                accum.push('/');
            }
            accum.push_str(seg);
            if let Some(existing) = path_to_id.get(&accum) {
                parent_id = Some(existing.clone());
                continue;
            }
            let mut bytes = [0u8; 16];
            rand::rngs::OsRng.fill_bytes(&mut bytes);
            let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let row = folders::FolderRow {
                id: id.clone(),
                name: seg.to_string(),
                parent_id: parent_id.clone(),
                sort_order,
                collapsed: false,
                created_at_ms: now_ms,
            };
            sort_order += 1;
            match folders::upsert(conn, &row) {
                Ok(_) => {
                    result.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    result.errors.push(format!("folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
    path_to_id
}

fn apply_empty_folders(
    conn: &Connection,
    json: &str,
    path_to_id: &mut HashMap<String, String>,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    use rand::RngCore;
    let arr: Vec<String> = match serde_json::from_str(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("empty_folders parse: {e}"));
            return;
        }
    };
    let mut sort_order: i64 = path_to_id.len() as i64;
    for path in arr {
        if path.is_empty() || path_to_id.contains_key(&path) {
            continue;
        }
        let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        let mut parent_id: Option<String> = None;
        let mut accum = String::new();
        for seg in segments {
            if !accum.is_empty() {
                accum.push('/');
            }
            accum.push_str(seg);
            if let Some(existing) = path_to_id.get(&accum) {
                parent_id = Some(existing.clone());
                continue;
            }
            let mut bytes = [0u8; 16];
            rand::rngs::OsRng.fill_bytes(&mut bytes);
            let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let row = folders::FolderRow {
                id: id.clone(),
                name: seg.to_string(),
                parent_id: parent_id.clone(),
                sort_order,
                collapsed: false,
                created_at_ms: now_ms,
            };
            sort_order += 1;
            match folders::upsert(conn, &row) {
                Ok(_) => {
                    result.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    result
                        .errors
                        .push(format!("empty_folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
}

fn apply_session_tags(conn: &Connection, json: &str, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("session_tags parse: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        let tag_id = json_string(&v, "tag_id");
        if session_id.is_empty() || tag_id.is_empty() {
            continue;
        }
        match tags::link_session_tag(conn, &session_id, &tag_id) {
            Ok(_) => result.session_tags_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session_tag {session_id}↔{tag_id}: {e}")),
        }
    }
}

fn apply_session_snippets(conn: &Connection, json: &str, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("session_snippets parse: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        let snippet_id = json_string(&v, "snippet_id");
        if session_id.is_empty() || snippet_id.is_empty() {
            continue;
        }
        match snippets::link_session_snippet(conn, &session_id, &snippet_id) {
            Ok(_) => result.session_snippets_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session_snippet {session_id}↔{snippet_id}: {e}")),
        }
    }
}

fn json_string(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
}

fn json_i64(v: &Value, key: &str) -> i64 {
    v.get(key).and_then(|x| x.as_i64()).unwrap_or(0)
}

fn apply_sessions(
    conn: &Connection,
    json: &str,
    folder_path_to_id: &HashMap<String, String>,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("sessions parse: {e}"));
            return;
        }
    };
    for v in arr {
        // `via_override` (host/port/user trio) lives as a nested
        // object Dart-side; flatten back into the column trio.
        let (via_host, via_port, via_user) = match v.get("via_override") {
            Some(o) => (
                o.get("host").and_then(|x| x.as_str()).map(String::from),
                o.get("port").and_then(|x| x.as_i64()),
                o.get("user").and_then(|x| x.as_str()).map(String::from),
            ),
            None => (None, None, None),
        };
        let extras = v
            .get("extras")
            .filter(|x| x.is_object())
            .map(|x| x.to_string())
            .unwrap_or_default();
        // Resolve `folder` (path string) → folder_id via the
        // map [`apply_folder_tree`] built moments earlier.
        let folder_id = v
            .get("folder")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .and_then(|p| folder_path_to_id.get(p).cloned());
        let row = sessions::SessionRow {
            id: json_string(&v, "id"),
            label: json_string(&v, "label"),
            folder_id,
            host: json_string(&v, "host"),
            port: json_i64(&v, "port"),
            user: json_string(&v, "user"),
            auth_type: json_string(&v, "auth_type"),
            password: json_string(&v, "password"),
            key_path: json_string(&v, "key_path"),
            key_data: json_string(&v, "key_data"),
            key_id: v
                .get("key_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            passphrase: json_string(&v, "passphrase"),
            sort_order: 0,
            notes: json_string(&v, "notes"),
            last_connected_at_ms: None,
            extras,
            via_session_id: v
                .get("via_session_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            via_host,
            via_port,
            via_user,
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
            updated_at_ms: now_ms,
        };
        if row.id.is_empty() {
            result.errors.push("session row missing id".to_string());
            continue;
        }
        match sessions::upsert(conn, &row) {
            Ok(_) => result.sessions_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session {} upsert: {e}", row.id)),
        }
    }
}

fn apply_keys(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("keys parse: {e}"));
            return;
        }
    };
    // Dedup against existing public-key fingerprints — exact
    // dupe lands the archive's id on top of the existing row,
    // but we count it as skipped so the UI summary reads
    // "added N, deduped M".
    let existing = match ssh_keys::list_metadata(conn) {
        Ok(v) => v,
        Err(e) => {
            result.errors.push(format!("keys metadata: {e}"));
            return;
        }
    };
    let existing_fps: HashSet<String> = existing
        .iter()
        .map(|m| m.public_fingerprint.clone())
        .filter(|s| !s.is_empty())
        .collect();
    for v in arr {
        let public_key = json_string(&v, "public_key");
        let fp = key_pub_fingerprint(&public_key);
        if !fp.is_empty() && existing_fps.contains(&fp) {
            result.keys_skipped_dedup += 1;
            continue;
        }
        let row = ssh_keys::SshKeyRow {
            id: json_string(&v, "id"),
            label: json_string(&v, "label"),
            private_key: json_string(&v, "private_key"),
            public_key,
            key_type: json_string(&v, "key_type"),
            is_generated: v
                .get("is_generated")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
        };
        if row.id.is_empty() {
            result.errors.push("key row missing id".to_string());
            continue;
        }
        match ssh_keys::upsert(conn, &row) {
            Ok(_) => result.keys_applied += 1,
            Err(e) => result.errors.push(format!("key {} upsert: {e}", row.id)),
        }
    }
}

fn apply_tags(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("tags parse: {e}"));
            return;
        }
    };
    for v in arr {
        let row = tags::TagRow {
            id: json_string(&v, "id"),
            name: json_string(&v, "name"),
            color: v
                .get("color")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
        };
        if row.id.is_empty() || row.name.is_empty() {
            continue;
        }
        match tags::upsert(conn, &row) {
            Ok(_) => result.tags_applied += 1,
            Err(e) => result.errors.push(format!("tag {} upsert: {e}", row.id)),
        }
    }
}

fn apply_snippets(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("snippets parse: {e}"));
            return;
        }
    };
    for v in arr {
        let row = snippets::SnippetRow {
            id: json_string(&v, "id"),
            title: json_string(&v, "title"),
            command: json_string(&v, "command"),
            description: json_string(&v, "description"),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
            updated_at_ms: now_ms,
        };
        if row.id.is_empty() || row.title.is_empty() {
            continue;
        }
        match snippets::upsert(conn, &row) {
            Ok(_) => result.snippets_applied += 1,
            Err(e) => result
                .errors
                .push(format!("snippet {} upsert: {e}", row.id)),
        }
    }
}

fn apply_known_hosts(conn: &Connection, text: &str, now_ms: i64, result: &mut ApplyResult) {
    // Format: "host[:port] keytype key_base64" per line. Comments
    // (`#` lines) and blanks skipped. Default port 22 when the
    // host omits the colon — same fallback the Dart importer uses.
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.splitn(3, char::is_whitespace);
        let (Some(host_port), Some(key_type), Some(key_base64)) =
            (parts.next(), parts.next(), parts.next())
        else {
            continue;
        };
        let (host, port) = match host_port.rsplit_once(':') {
            Some((h, p)) => match p.parse::<i64>() {
                Ok(n) => (h, n),
                Err(_) => (host_port, 22),
            },
            None => (host_port, 22),
        };
        match known_hosts::upsert_by_host_port(conn, host, port, key_type, key_base64, now_ms) {
            Ok(_) => result.known_hosts_applied += 1,
            Err(e) => result.errors.push(format!("known_host {host}:{port}: {e}")),
        }
    }
}

/// Mirror the SHA-256-of-normalised-PEM fingerprint the
/// `ssh_keys::list_metadata` path computes — keep both sides
/// of the dedup compare reading the same hash. Empty input →
/// empty fingerprint so missing-public-key rows do not
/// false-match the dedup set.
fn key_pub_fingerprint(s: &str) -> String {
    use sha2::{Digest, Sha256};
    let normalised = s.replace("\r\n", "\n");
    let trimmed = normalised.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(trimmed.as_bytes());
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(digest.len() * 2);
    for b in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pending_with_sessions(json: &str) -> PendingImport {
        PendingImport {
            manifest_json: None,
            sessions_json: Some(json.to_string()),
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        }
    }

    #[test]
    fn import_registry_round_trip() {
        let reg = ImportRegistry::new();
        let pending = pending_with_sessions(r#"[{"label":"prod"},{"label":"staging"}]"#);
        reg.insert("h1".into(), pending);
        assert_eq!(reg.count(), 1);
        assert!(reg.get_clone("h1").is_some());
        let taken = reg.take("h1").expect("take");
        assert_eq!(reg.count(), 0);
        assert_eq!(
            taken.sessions_json.as_deref(),
            Some(r#"[{"label":"prod"},{"label":"staging"}]"#)
        );
        // Take is idempotent: a second take on a missing id returns None.
        assert!(reg.take("h1").is_none());
    }

    #[test]
    fn import_registry_drop_handle_evicts_silently() {
        let reg = ImportRegistry::new();
        reg.insert("h1".into(), pending_with_sessions("[]"));
        reg.drop_handle("h1");
        reg.drop_handle("h1"); // missing id is a no-op
        assert_eq!(reg.count(), 0);
    }

    #[test]
    fn import_preview_counts_sessions_and_pulls_labels() {
        let pending = pending_with_sessions(
            r#"[{"label":"prod","host":"a"},{"label":"staging","host":"b"}]"#,
        );
        let preview = pending.preview(7);
        assert_eq!(preview.schema_version, 7);
        assert_eq!(preview.session_count, 2);
        assert_eq!(preview.session_labels, vec!["prod", "staging"]);
        assert!(!preview.has_config);
        assert!(!preview.has_known_hosts);
    }

    #[test]
    fn import_preview_handles_malformed_sessions_json() {
        let mut pending = pending_with_sessions("not-actually-json");
        // Corrupted entries decay to zero counts rather than panic —
        // the apply path surfaces the parse error elsewhere.
        let preview = pending.preview(1);
        assert_eq!(preview.session_count, 0);
        assert!(preview.session_labels.is_empty());
        // Missing optional sources also yield zero counts.
        pending.sessions_json = None;
        let preview = pending.preview(1);
        assert_eq!(preview.session_count, 0);
    }

    #[test]
    fn import_preview_flags_config_and_known_hosts() {
        let mut pending = pending_with_sessions("[]");
        pending.config_json = Some("{\"theme\":\"dark\"}".into());
        pending.known_hosts_text = Some("example.com ssh-ed25519 AAAA".into());
        let preview = pending.preview(1);
        assert!(preview.has_config);
        assert!(preview.has_known_hosts);
    }

    #[test]
    fn import_preview_empty_strings_treat_as_absent() {
        let mut pending = pending_with_sessions("[]");
        pending.config_json = Some(String::new());
        pending.known_hosts_text = Some(String::new());
        let preview = pending.preview(1);
        assert!(!preview.has_config);
        assert!(!preview.has_known_hosts);
    }

    fn build_test_zip(entries: &[(&str, &str)]) -> Vec<u8> {
        let mut buf = Cursor::new(Vec::new());
        let mut zw = zip::ZipWriter::new(&mut buf);
        let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
        for (name, body) in entries {
            zw.start_file(*name, opts).unwrap();
            zw.write_all(body.as_bytes()).unwrap();
        }
        zw.finish().unwrap();
        buf.into_inner()
    }

    #[test]
    fn parse_pending_import_picks_known_entries() {
        let zip = build_test_zip(&[
            ("manifest.json", r#"{"schema_version":7}"#),
            ("sessions.json", r#"[{"label":"x"}]"#),
            ("config.json", r#"{"theme":"dark"}"#),
            ("known_hosts.txt", "host ssh-ed25519 AAAA"),
            ("ignored.bin", "garbage"),
        ]);
        let (pending, schema) = parse_pending_import(&zip).expect("parse");
        assert_eq!(schema, 7);
        assert_eq!(pending.sessions_json.as_deref(), Some(r#"[{"label":"x"}]"#));
        assert_eq!(pending.config_json.as_deref(), Some(r#"{"theme":"dark"}"#));
        assert_eq!(
            pending.known_hosts_text.as_deref(),
            Some("host ssh-ed25519 AAAA")
        );
        assert!(pending.keys_json.is_none());
    }

    #[test]
    fn parse_pending_import_zero_schema_when_manifest_missing() {
        let zip = build_test_zip(&[("sessions.json", "[]")]);
        let (_pending, schema) = parse_pending_import(&zip).expect("parse");
        assert_eq!(schema, 0);
    }

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
        crate::db::bootstrap_schema(&conn).unwrap();
        conn
    }

    fn merge_all_options() -> ApplyOptions {
        ApplyOptions {
            mode: ImportMode::Merge,
            apply_sessions: true,
            apply_keys: true,
            apply_tags: true,
            apply_snippets: true,
            apply_known_hosts: true,
        }
    }

    #[test]
    fn apply_keys_inserts_fresh_row() {
        let conn = fresh_db();
        let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k1","label":"lap","private_key":"PRIV","public_key":"ssh-ed25519 AAAA","key_type":"ssh-ed25519","is_generated":true,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..PendingImport {
                manifest_json: None,
                sessions_json: None,
                keys_json: None,
                tags_json: None,
                session_tags_json: None,
                folder_tags_json: None,
                snippets_json: None,
                session_snippets_json: None,
                empty_folders_json: None,
                config_json: None,
                known_hosts_text: None,
            }
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 1);
        let on_disk = ssh_keys::get(&conn, "k1").unwrap().unwrap();
        assert_eq!(on_disk.label, "lap");
        assert!(on_disk.is_generated);
    }

    #[test]
    fn apply_keys_dedups_existing_fingerprint() {
        let conn = fresh_db();
        // Pre-seed with a key whose public_key matches what the
        // archive carries — apply path should skip the dupe.
        ssh_keys::upsert(
            &conn,
            &ssh_keys::SshKeyRow {
                id: "existing".into(),
                label: "Existing".into(),
                private_key: "OLD".into(),
                public_key: "ssh-ed25519 AAAADUPE".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: Some(
                r#"[{"id":"k_new","label":"Fresh","private_key":"NEW","public_key":"ssh-ed25519 AAAADUPE","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 0);
        assert_eq!(result.keys_skipped_dedup, 1);
        // Existing row stayed; the dupe import never landed under
        // its archive id.
        assert!(ssh_keys::get(&conn, "k_new").unwrap().is_none());
    }

    #[test]
    fn apply_sessions_parses_via_override_and_extras() {
        let conn = fresh_db();
        let json = r#"[{
            "id":"s1",
            "label":"prod",
            "host":"a.example",
            "port":22,
            "user":"deploy",
            "auth_type":"password",
            "password":"hunter2",
            "key_path":"",
            "key_data":"",
            "passphrase":"",
            "extras":{"foo":"bar"},
            "via_override":{"host":"bastion","port":2222,"user":"jump"},
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: Some(json.to_string()),
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.sessions_applied, 1);
        let row = sessions::get(&conn, "s1").unwrap().unwrap();
        assert_eq!(row.via_host.as_deref(), Some("bastion"));
        assert_eq!(row.via_port, Some(2222));
        assert_eq!(row.via_user.as_deref(), Some("jump"));
        assert!(row.extras.contains("foo"));
        assert!(row.folder_id.is_none(), "folder hierarchy not yet wired");
    }

    #[test]
    fn apply_known_hosts_appends_lines() {
        let conn = fresh_db();
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: Some(
                "# leading comment\nfoo.example ssh-ed25519 AAAA\nbar.example:2222 ssh-rsa BBBB\n"
                    .to_string(),
            ),
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.known_hosts_applied, 2);
        let foo = known_hosts::get_by_host_port(&conn, "foo.example", 22)
            .unwrap()
            .unwrap();
        assert_eq!(foo.key_type, "ssh-ed25519");
        let bar = known_hosts::get_by_host_port(&conn, "bar.example", 2222)
            .unwrap()
            .unwrap();
        assert_eq!(bar.key_type, "ssh-rsa");
    }

    #[test]
    fn apply_tags_and_snippets_round_trip() {
        let conn = fresh_db();
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: Some(
                r##"[{"id":"t1","name":"prod","color":"#ff0000","created_at":"2026-04-26T00:00:00.000Z"}]"##
                    .to_string(),
            ),
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: Some(
                r#"[{"id":"sn1","title":"ll","command":"ls -la","description":"long list","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.tags_applied, 1);
        assert_eq!(result.snippets_applied, 1);
        assert_eq!(tags::list_all(&conn).unwrap().len(), 1);
        assert_eq!(snippets::list_all(&conn).unwrap().len(), 1);
    }

    #[test]
    fn apply_does_not_abort_on_partial_parse_failure() {
        let conn = fresh_db();
        // Bad sessions JSON should not stop the keys stage.
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: Some("not-json".to_string()),
            keys_json: Some(
                r#"[{"id":"k1","label":"good","private_key":"P","public_key":"ssh-ed25519 X","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 1);
        assert_eq!(result.sessions_applied, 0);
        assert!(!result.errors.is_empty());
    }

    #[test]
    fn json_array_len_handles_object_payload() {
        // The DAO writes top-level arrays today; a future migration
        // could swap to wrapped objects. The helper must not blow
        // up on a non-array — it returns 0 so the preview shows
        // "import contains no entries" rather than panicking.
        assert_eq!(json_array_len(Some(r#"{"sessions":[]}"#)), 0);
        assert_eq!(json_array_len(Some("[]")), 0);
        assert_eq!(json_array_len(Some("[1,2,3]")), 3);
        assert_eq!(json_array_len(None), 0);
    }
}
