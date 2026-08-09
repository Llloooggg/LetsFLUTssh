//! QR-share payload composer.
//!
//! Reads the same DB tables the `.lfs` archive does, but emits the
//! compact dedicated wire format for QR-deeplink sharing
//! (`encodeExportPayload` in the Dart era). Plaintext credential
//! bytes (manager-key PEM, session passwords) flow DB → JSON →
//! deflate → base64 inside Rust; only the encoded ASCII string
//! crosses the FRB boundary back to Dart for the QR canvas.
//!
//! Wire-shape parity with the size-only counterpart
//! [`qr_export_payload_size`] is enforced by the
//! `qr_codec_encode::compress_to_payload[_size]` helpers — both
//! producers run the same `Deflate(default).encode + base64url`
//! pass; only the result type differs.

use std::collections::{HashMap, HashSet};

use serde_json::{json, Value};

use crate::db::{folders, sessions, snippets, ssh_keys, tags};
use crate::error::Error;

// `build_folder_paths` + `build_known_hosts` are private helpers
// in `archive/mod.rs`, exposed via `pub(super)` visibility so this
// submodule can pull them in.
use super::{build_folder_paths, build_known_hosts};

/// Wire-format version stamped into the QR payload's `v` field.
/// Read straight from [`crate::migration::SchemaVersions::QR_PAYLOAD`]
/// so the composer and the decoder (`qr_codec_decode`, which derives
/// its accepted ceiling from the same constant) cannot drift — a
/// hardcoded literal here once diverged from the registry value and
/// the decoder rejected every export as "version too new".
const QR_FORMAT_VERSION: i64 = crate::migration::SchemaVersions::QR_PAYLOAD as i64;

#[derive(Debug, Clone, Default)]
pub struct QrExportOptions {
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
pub struct QrExportInput {
    pub options: QrExportOptions,
    pub selected_session_ids: Vec<String>,
    pub selected_empty_folders: Vec<String>,
    /// Pre-serialised `config.json` payload — Dart hands the same
    /// `AppConfig.toJson()` shape across the FRB boundary because
    /// `config.json` is file-based, not DB-resident.
    pub config_json: Option<String>,
}

/// Build the QR deeplink payload (`d=` value) entirely Rust-side.
/// Same wire format as the Dart-era `encodeExportPayload`: compact
/// JSON → deflate → base64url-no-pad. Plaintext credential bytes
/// (manager-key PEM, session passwords) flow DB → JSON → deflate
/// → base64 inside Rust and only the encoded ASCII string crosses
/// the FRB boundary back to Dart for the QR canvas.
pub fn qr_export_payload(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
) -> Result<String, Error> {
    let json = build_qr_export_json(conn, input)?;
    Ok(crate::qr_codec_encode::compress_to_payload(&json))
}

/// Same composition as [`qr_export_payload`] but skips the
/// base64url encode step and returns the deflated payload's
/// byte count. Drives the live "fits in QR" gauge in the Dart
/// `unified_export_controller` — one FRB call per checkbox
/// toggle returns the size with no JSON crossing the boundary.
///
/// Wire-shape parity with [`qr_export_payload`] is enforced by
/// the `qr_codec_encode::compress_to_payload_size` helper:
/// both producers run the same `Deflate(default).encode + base64url`
/// pass, only the result type differs (size only vs full string).
pub fn qr_export_payload_size(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
) -> Result<u32, Error> {
    let json = build_qr_export_json(conn, input)?;
    Ok(crate::qr_codec_encode::compress_to_payload_size(&json))
}

/// Internal — build the canonical-JSON payload string. Both the
/// `qr_export_payload` (encode-and-emit) and the
/// `qr_export_payload_size` (encode-and-count) wrappers route
/// through this so the wire shape stays one place.
fn build_qr_export_json(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
) -> Result<String, Error> {
    let mut payload = serde_json::Map::new();
    payload.insert("v".into(), json!(QR_FORMAT_VERSION));

    let folder_paths = build_folder_paths(conn)?;
    let session_rows = collect_session_rows(conn, input)?;

    let session_pem = resolve_session_pems(conn, input, &session_rows)?;
    let mut dedup = KeyDedup::default();
    dedup.add_session_keys(&session_rows, &session_pem);
    let manager_meta = build_manager_meta(conn, input, &mut dedup)?;
    insert_key_maps(&mut payload, &dedup, &manager_meta);

    // Short session ids (`s0`, `s1`, …) keyed by the live DB id, in
    // emission order. The compact `s` shape carries no UUID (camera
    // bandwidth), so the session→tag / session→snippet link tables
    // reference these shorts instead of the 36-char DB id; the
    // decoder mints a fresh UUID per session and remaps the shorts
    // onto it. Without this the links pointed at an id that never
    // lands after decode and every association was dropped on import.
    let session_id_to_short: HashMap<String, String> = session_rows
        .iter()
        .enumerate()
        .map(|(i, s)| (s.id.clone(), format!("s{i}")))
        .collect();

    if input.options.include_sessions {
        let arr = build_sessions_array(
            input,
            &session_rows,
            &folder_paths,
            &dedup,
            &session_id_to_short,
        );
        payload.insert("s".into(), Value::Array(arr));
        if !input.selected_empty_folders.is_empty() {
            payload.insert(
                "eg".into(),
                Value::Array(
                    input
                        .selected_empty_folders
                        .iter()
                        .map(|f| Value::String(f.clone()))
                        .collect(),
                ),
            );
        }
    }

    append_config(&mut payload, input);
    append_known_hosts(conn, input, &mut payload)?;
    append_tags(
        conn,
        input,
        &mut payload,
        &folder_paths,
        &session_id_to_short,
    )?;
    append_snippets(conn, input, &mut payload, &session_id_to_short)?;

    serde_json::to_string(&Value::Object(payload))
        .map_err(|e| Error::Archive(format!("qr json serialise: {e}")))
}

/// Selected session rows for the export, or empty when sessions are
/// not included.
fn collect_session_rows(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
) -> Result<Vec<sessions::SessionRow>, Error> {
    if !input.options.include_sessions {
        return Ok(Vec::new());
    }
    let want: HashSet<&str> = input
        .selected_session_ids
        .iter()
        .map(|s| s.as_str())
        .collect();
    Ok(sessions::list_all(conn)?
        .into_iter()
        .filter(|s| want.contains(s.id.as_str()))
        .collect())
}

/// Resolve each selected session's key bytes once, keyed by session
/// id → (pem, from_manager). Inline `key_data` carries the PEM
/// directly; `key_id` references look up `ssh_keys.private_key`.
/// Sessions without any shippable key material get no entry.
fn resolve_session_pems(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
    session_rows: &[sessions::SessionRow],
) -> Result<HashMap<String, (String, bool)>, Error> {
    let mut session_pem: HashMap<String, (String, bool)> = HashMap::new();
    if !(input.options.include_embedded_keys
        || input.options.include_manager_keys
        || input.options.include_all_manager_keys)
    {
        return Ok(session_pem);
    }
    let key_by_id: HashMap<String, String> = ssh_keys::list_all(conn)?
        .into_iter()
        .map(|k| (k.id, k.private_key))
        .collect();
    for s in session_rows {
        let from_manager = s.key_id.as_deref().is_some_and(|k| !k.is_empty());
        if from_manager
            && !(input.options.include_manager_keys || input.options.include_all_manager_keys)
        {
            continue;
        }
        if !from_manager && !input.options.include_embedded_keys {
            continue;
        }
        let pem = if from_manager {
            key_by_id
                .get(s.key_id.as_ref().unwrap())
                .cloned()
                .unwrap_or_default()
        } else {
            s.key_data.clone()
        };
        if !pem.is_empty() {
            session_pem.insert(s.id.clone(), (pem, from_manager));
        }
    }
    Ok(session_pem)
}

/// PEM-content dedup state. Identical key material across multiple
/// sessions and across embedded vs manager forms collapses into a
/// single `kN` short id (and therefore one `km` entry).
#[derive(Default)]
struct KeyDedup {
    key_to_short: HashMap<String, String>,  // pem → kN
    session_short: HashMap<String, String>, // session id → kN
    manager_shorts: HashSet<String>,
    counter: usize,
}

impl KeyDedup {
    fn short_for(&mut self, pem: &str) -> String {
        if let Some(short) = self.key_to_short.get(pem) {
            return short.clone();
        }
        let id = format!("k{}", self.counter);
        self.counter += 1;
        self.key_to_short.insert(pem.to_string(), id.clone());
        id
    }

    fn add_session_keys(
        &mut self,
        session_rows: &[sessions::SessionRow],
        session_pem: &HashMap<String, (String, bool)>,
    ) {
        for s in session_rows {
            if let Some((pem, from_manager)) = session_pem.get(&s.id) {
                let short = self.short_for(pem);
                self.session_short.insert(s.id.clone(), short.clone());
                if *from_manager {
                    self.manager_shorts.insert(short);
                }
            }
        }
    }
}

/// Manager-key metadata keyed by short → (label, type, pubkey).
/// `include_all_manager_keys` folds every stored key into the dedup
/// map so the receiver imports the full key manager; the narrower
/// `include_manager_keys` fills metadata only for already-referenced
/// shorts.
fn build_manager_meta(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
    dedup: &mut KeyDedup,
) -> Result<HashMap<String, (String, String, String)>, Error> {
    let mut manager_meta: HashMap<String, (String, String, String)> = HashMap::new();
    if input.options.include_all_manager_keys {
        fold_all_manager_keys(conn, dedup, &mut manager_meta)?;
    } else if input.options.include_manager_keys {
        fill_referenced_manager_meta(conn, dedup, &mut manager_meta)?;
    }
    Ok(manager_meta)
}

/// Fold every stored key into the dedup map + metadata, so the
/// receiver imports the full key manager.
fn fold_all_manager_keys(
    conn: &impl crate::db::DbAccess,
    dedup: &mut KeyDedup,
    manager_meta: &mut HashMap<String, (String, String, String)>,
) -> Result<(), Error> {
    for k in ssh_keys::list_all(conn)? {
        if k.private_key.is_empty() {
            continue;
        }
        let short = dedup.short_for(&k.private_key);
        dedup.manager_shorts.insert(short.clone());
        manager_meta.insert(short, (k.label, k.key_type, k.public_key));
    }
    Ok(())
}

/// Fill metadata only for shorts already referenced by a session.
fn fill_referenced_manager_meta(
    conn: &impl crate::db::DbAccess,
    dedup: &KeyDedup,
    manager_meta: &mut HashMap<String, (String, String, String)>,
) -> Result<(), Error> {
    let by_pem: HashMap<String, ssh_keys::SshKeyRow> = ssh_keys::list_all(conn)?
        .into_iter()
        .map(|k| (k.private_key.clone(), k))
        .collect();
    for short in &dedup.manager_shorts {
        let Some((pem, _)) = dedup.key_to_short.iter().find(|(_, v)| *v == short) else {
            continue;
        };
        if let Some(k) = by_pem.get(pem) {
            manager_meta.insert(
                short.clone(),
                (k.label.clone(), k.key_type.clone(), k.public_key.clone()),
            );
        }
    }
    Ok(())
}

fn insert_key_maps(
    payload: &mut serde_json::Map<String, Value>,
    dedup: &KeyDedup,
    manager_meta: &HashMap<String, (String, String, String)>,
) {
    if !dedup.key_to_short.is_empty() {
        let mut km = serde_json::Map::new();
        for (pem, short) in &dedup.key_to_short {
            km.insert(short.clone(), Value::String(pem.clone()));
        }
        payload.insert("km".into(), Value::Object(km));
    }
    if !manager_meta.is_empty() {
        let mut mk = serde_json::Map::new();
        for (short, (label, kt, pk)) in manager_meta {
            mk.insert(short.clone(), json!({"l": label, "t": kt, "p": pk}));
        }
        payload.insert("mk".into(), Value::Object(mk));
    }
}

fn build_sessions_array(
    input: &QrExportInput,
    session_rows: &[sessions::SessionRow],
    folder_paths: &HashMap<String, String>,
    dedup: &KeyDedup,
    session_id_to_short: &HashMap<String, String>,
) -> Vec<Value> {
    session_rows
        .iter()
        .map(|s| {
            let folder_path = s
                .folder_id
                .as_ref()
                .and_then(|id| folder_paths.get(id))
                .cloned()
                .unwrap_or_default();
            let key_short = dedup.session_short.get(&s.id);
            let is_manager = key_short
                .map(|k| dedup.manager_shorts.contains(k))
                .unwrap_or(false);
            let mut entry = crate::qr_codec_encode::encode_session_compact(
                &crate::qr_codec_encode::SessionCompactInputs {
                    label: &s.label,
                    host: &s.host,
                    user: &s.user,
                    port: u16::try_from(s.port.max(0)).unwrap_or(u16::MAX),
                    folder: &folder_path,
                    auth_type: &s.auth_type,
                    key_short: key_short.map(String::as_str),
                    is_manager,
                    include_passwords: input.options.include_passwords,
                    password: &s.password,
                },
            );
            if let (Some(obj), Some(short)) =
                (entry.as_object_mut(), session_id_to_short.get(&s.id))
            {
                obj.insert("i".into(), json!(short));
            }
            entry
        })
        .collect()
}

fn append_config(payload: &mut serde_json::Map<String, Value>, input: &QrExportInput) {
    if !input.options.include_config {
        return;
    }
    let Some(cj) = input.config_json.as_deref() else {
        return;
    };
    if cj.is_empty() {
        return;
    }
    if let Ok(v) = serde_json::from_str::<Value>(cj) {
        payload.insert("c".into(), v);
    }
}

fn append_known_hosts(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
    payload: &mut serde_json::Map<String, Value>,
) -> Result<(), Error> {
    if !input.options.include_known_hosts {
        return Ok(());
    }
    let kh = build_known_hosts(conn)?;
    if !kh.is_empty() {
        payload.insert("kh".into(), Value::String(kh));
    }
    Ok(())
}

fn append_tags(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
    payload: &mut serde_json::Map<String, Value>,
    folder_paths: &HashMap<String, String>,
    session_id_to_short: &HashMap<String, String>,
) -> Result<(), Error> {
    if !input.options.include_tags {
        return Ok(());
    }
    let tag_rows = tags::list_all(conn)?;
    if tag_rows.is_empty() {
        return Ok(());
    }
    let arr: Vec<Value> = tag_rows
        .iter()
        .map(|t| {
            let mut m = serde_json::Map::new();
            m.insert("i".into(), json!(t.id));
            m.insert("n".into(), json!(t.name));
            if let Some(c) = t.color.as_deref() {
                m.insert("cl".into(), json!(c));
            }
            Value::Object(m)
        })
        .collect();
    payload.insert("tg".into(), Value::Array(arr));

    let mut session_tags = Vec::new();
    for sid in &input.selected_session_ids {
        // Reference the session by its short id — the link resolves on
        // import only if the session itself ships (and so has a
        // short). Skip links to unexported sessions, which would
        // dangle.
        let Some(short) = session_id_to_short.get(sid) else {
            continue;
        };
        for tid in tags::list_session_tag_ids(conn, sid)? {
            session_tags.push(json!({"si": short, "ti": tid}));
        }
    }
    if !session_tags.is_empty() {
        payload.insert("st".into(), Value::Array(session_tags));
    }

    let mut folder_tags = Vec::new();
    let folder_rows = folders::list_all(conn)?;
    for f in &folder_rows {
        let path = folder_paths.get(&f.id).cloned().unwrap_or_default();
        for tid in tags::list_folder_tag_ids(conn, &f.id)? {
            folder_tags.push(json!({"fi": path, "ti": tid}));
        }
    }
    if !folder_tags.is_empty() {
        payload.insert("ft".into(), Value::Array(folder_tags));
    }
    Ok(())
}

fn append_snippets(
    conn: &impl crate::db::DbAccess,
    input: &QrExportInput,
    payload: &mut serde_json::Map<String, Value>,
    session_id_to_short: &HashMap<String, String>,
) -> Result<(), Error> {
    if !input.options.include_snippets {
        return Ok(());
    }
    let snip_rows = snippets::list_all(conn)?;
    if snip_rows.is_empty() {
        return Ok(());
    }
    let arr: Vec<Value> = snip_rows
        .iter()
        .map(|s| {
            let mut m = serde_json::Map::new();
            m.insert("i".into(), json!(s.id));
            m.insert("t".into(), json!(s.title));
            m.insert("cm".into(), json!(s.command));
            if !s.description.is_empty() {
                m.insert("d".into(), json!(s.description));
            }
            Value::Object(m)
        })
        .collect();
    payload.insert("sn".into(), Value::Array(arr));

    let mut session_snippets = Vec::new();
    for sid in &input.selected_session_ids {
        let Some(short) = session_id_to_short.get(sid) else {
            continue;
        };
        for snid in snippets::list_session_snippet_ids(conn, sid)? {
            session_snippets.push(json!({"si": short, "ni": snid}));
        }
    }
    if !session_snippets.is_empty() {
        payload.insert("ss".into(), Value::Array(session_snippets));
    }
    Ok(())
}
#[cfg(test)]
#[path = "../../tests/unit/archive_qr_compose.rs"]
mod tests;
