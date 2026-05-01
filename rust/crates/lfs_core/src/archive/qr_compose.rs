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

use rusqlite::Connection;
use serde_json::{json, Value};

use crate::db::{folders, sessions, snippets, ssh_keys, tags};
use crate::error::Error;

// `build_folder_paths` + `build_known_hosts` are private helpers
// in `archive/mod.rs`, exposed via `pub(super)` visibility so this
// submodule can pull them in.
use super::{build_folder_paths, build_known_hosts};

/// Wire-format version stamped into the QR payload's `v` field.
/// Mirrors `_currentFormatVersion` in `lib/core/session/qr_codec.dart`
/// — bump there and here in lockstep. Lives next to the only call
/// site (`build_qr_export_json`) since the constant is QR-specific
/// and bumping it does not touch the `.lfs` archive format.
const QR_FORMAT_VERSION: i64 = 4;

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
pub fn qr_export_payload(conn: &Connection, input: &QrExportInput) -> Result<String, Error> {
    let json = build_qr_export_json(conn, input)?;
    Ok(crate::qr_codec_encode::compress_to_payload(&json))
}

/// Same composition as [`qr_export_payload`] but skips the
/// base64url encode step and returns the deflated payload's
/// byte count. Drives the live "fits in QR" gauge in the Dart
/// `unified_export_controller` — single FRB call per checkbox
/// toggle replaces the per-toggle Dart-side JSON build + Rust
/// deflate round-trip the controller used to do.
///
/// Wire-shape parity with [`qr_export_payload`] is enforced by
/// the `qr_codec_encode::compress_to_payload_size` helper:
/// both producers run the same `Deflate(default).encode + base64url`
/// pass, only the result type differs (size only vs full string).
pub fn qr_export_payload_size(conn: &Connection, input: &QrExportInput) -> Result<u32, Error> {
    let json = build_qr_export_json(conn, input)?;
    Ok(crate::qr_codec_encode::compress_to_payload_size(&json))
}

/// Internal — build the canonical-JSON payload string. Both the
/// `qr_export_payload` (encode-and-emit) and the
/// `qr_export_payload_size` (encode-and-count) wrappers route
/// through this so the wire shape stays one place.
fn build_qr_export_json(conn: &Connection, input: &QrExportInput) -> Result<String, Error> {
    let mut payload = serde_json::Map::new();
    payload.insert("v".into(), json!(QR_FORMAT_VERSION));

    let folder_paths = build_folder_paths(conn)?;
    let session_rows: Vec<sessions::SessionRow> = if input.options.include_sessions {
        let want: HashSet<&str> = input
            .selected_session_ids
            .iter()
            .map(|s| s.as_str())
            .collect();
        sessions::list_all(conn)?
            .into_iter()
            .filter(|s| want.contains(s.id.as_str()))
            .collect()
    } else {
        Vec::new()
    };

    // Resolve every selected session's key bytes once. For inline
    // `key_data` the row carries the PEM directly; for keyId
    // references (`session.key_id`) we look up `ssh_keys.private_key`.
    // The map keyed by session.id holds the PEM the dedup logic
    // dedupes against; sessions without any key material have no
    // entry.
    let mut session_pem: HashMap<String, (String, bool)> = HashMap::new(); // id → (pem, fromManager)
    if !(input.options.include_embedded_keys
        || input.options.include_manager_keys
        || input.options.include_all_manager_keys)
    {
        // No PEMs ship; skip the lookup entirely.
    } else {
        let key_rows = ssh_keys::list_all(conn)?;
        let key_by_id: HashMap<String, String> = key_rows
            .into_iter()
            .map(|k| (k.id, k.private_key))
            .collect();
        for s in &session_rows {
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
    }

    // Dedup PEM bytes by content into `kN` short ids. Identical key
    // material across multiple sessions / and across embedded vs
    // manager forms collapses into a single `km` entry.
    let mut key_to_short: HashMap<String, String> = HashMap::new();
    let mut session_short: HashMap<String, String> = HashMap::new();
    let mut manager_shorts: HashSet<String> = HashSet::new();
    let mut counter = 0usize;
    for s in &session_rows {
        if let Some((pem, from_manager)) = session_pem.get(&s.id) {
            let short = key_to_short
                .entry(pem.clone())
                .or_insert_with(|| {
                    let id = format!("k{counter}");
                    counter += 1;
                    id
                })
                .clone();
            session_short.insert(s.id.clone(), short.clone());
            if *from_manager {
                manager_shorts.insert(short);
            }
        }
    }

    // "include all manager keys" — fold every stored key into the
    // map so the receiving side imports the full key manager.
    let mut manager_meta: HashMap<String, (String, String, String)> = HashMap::new(); // short → (label, type, pubkey)
    if input.options.include_all_manager_keys {
        let all_keys = ssh_keys::list_all(conn)?;
        for k in all_keys {
            if k.private_key.is_empty() {
                continue;
            }
            let short = key_to_short
                .entry(k.private_key.clone())
                .or_insert_with(|| {
                    let id = format!("k{counter}");
                    counter += 1;
                    id
                })
                .clone();
            manager_shorts.insert(short.clone());
            manager_meta.insert(short, (k.label, k.key_type, k.public_key));
        }
    } else if input.options.include_manager_keys {
        // Fill metadata only for keys actually referenced.
        let all_keys = ssh_keys::list_all(conn)?;
        let by_pem: HashMap<String, ssh_keys::SshKeyRow> = all_keys
            .into_iter()
            .map(|k| (k.private_key.clone(), k))
            .collect();
        for short in &manager_shorts {
            // find pem for this short
            if let Some((pem, _)) = key_to_short.iter().find(|(_, v)| *v == short) {
                if let Some(k) = by_pem.get(pem) {
                    manager_meta.insert(
                        short.clone(),
                        (k.label.clone(), k.key_type.clone(), k.public_key.clone()),
                    );
                }
            }
        }
    }

    if !key_to_short.is_empty() {
        let mut km = serde_json::Map::new();
        for (pem, short) in &key_to_short {
            km.insert(short.clone(), Value::String(pem.clone()));
        }
        payload.insert("km".into(), Value::Object(km));
    }

    if !manager_meta.is_empty() {
        let mut mk = serde_json::Map::new();
        for (short, (label, kt, pk)) in &manager_meta {
            mk.insert(short.clone(), json!({"l": label, "t": kt, "p": pk}));
        }
        payload.insert("mk".into(), Value::Object(mk));
    }

    if input.options.include_sessions {
        let arr: Vec<Value> = session_rows
            .iter()
            .map(|s| {
                let folder_path = s
                    .folder_id
                    .as_ref()
                    .and_then(|id| folder_paths.get(id))
                    .cloned()
                    .unwrap_or_default();
                let key_short = session_short.get(&s.id);
                let is_manager = key_short
                    .map(|k| manager_shorts.contains(k))
                    .unwrap_or(false);
                crate::qr_codec_encode::encode_session_compact(
                    &s.label,
                    &s.host,
                    &s.user,
                    u16::try_from(s.port.max(0)).unwrap_or(u16::MAX),
                    &folder_path,
                    &s.auth_type,
                    key_short.map(String::as_str),
                    is_manager,
                    input.options.include_passwords,
                    &s.password,
                )
            })
            .collect();
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

    if input.options.include_config {
        if let Some(cj) = input.config_json.as_deref() {
            if !cj.is_empty() {
                if let Ok(v) = serde_json::from_str::<Value>(cj) {
                    payload.insert("c".into(), v);
                }
            }
        }
    }

    if input.options.include_known_hosts {
        let kh = build_known_hosts(conn)?;
        if !kh.is_empty() {
            payload.insert("kh".into(), Value::String(kh));
        }
    }

    if input.options.include_tags {
        let tag_rows = tags::list_all(conn)?;
        if !tag_rows.is_empty() {
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
                for tid in tags::list_session_tag_ids(conn, sid)? {
                    session_tags.push(json!({"si": sid, "ti": tid}));
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
        }
    }

    if input.options.include_snippets {
        let snip_rows = snippets::list_all(conn)?;
        if !snip_rows.is_empty() {
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
                for snid in snippets::list_session_snippet_ids(conn, sid)? {
                    session_snippets.push(json!({"si": sid, "ni": snid}));
                }
            }
            if !session_snippets.is_empty() {
                payload.insert("ss".into(), Value::Array(session_snippets));
            }
        }
    }

    let json = serde_json::to_string(&Value::Object(payload))
        .map_err(|e| Error::Io(format!("qr json serialise: {e}")))?;
    Ok(json)
}
