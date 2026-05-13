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
/// `unified_export_controller` — single FRB call per checkbox
/// toggle replaces the per-toggle Dart-side JSON build + Rust
/// deflate round-trip the controller used to do.
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
        .map_err(|e| Error::Archive(format!("qr json serialise: {e}")))?;
    Ok(json)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{self, sessions::SessionRow, Connection};

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        db::bootstrap_schema(&conn).unwrap();
        conn
    }

    fn baseline_input() -> QrExportInput {
        QrExportInput {
            options: QrExportOptions::default(),
            selected_session_ids: vec![],
            selected_empty_folders: vec![],
            config_json: None,
        }
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
            extras: String::new(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        }
    }

    fn payload_value(conn: &impl crate::db::DbAccess, input: &QrExportInput) -> Value {
        let s = build_qr_export_json(conn, input).unwrap();
        serde_json::from_str(&s).unwrap()
    }

    fn insert_key(conn: &impl crate::db::DbAccess, id: &str, label: &str, pem: &str) {
        crate::db::ssh_keys::upsert(
            conn,
            &crate::db::ssh_keys::SshKeyRow {
                id: id.into(),
                label: label.into(),
                private_key: pem.into(),
                public_key: format!("PUB-{id}"),
                key_type: "ed25519".into(),
                is_generated: false,
                created_at_ms: 1_700_000_000_000,
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: crate::db::ssh_keys::AgentPolicy::Ask,
                backend: crate::db::ssh_keys::KeyBackend::Software,
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
    fn payload_carries_format_version_4() {
        let conn = fresh_db();
        let v = payload_value(&conn, &baseline_input());
        assert_eq!(v["v"], 4);
    }

    #[test]
    fn payload_with_no_toggles_only_carries_version() {
        let conn = fresh_db();
        let v = payload_value(&conn, &baseline_input());
        assert_eq!(v.as_object().unwrap().len(), 1);
    }

    #[test]
    fn sessions_array_emitted_with_compact_keys() {
        let conn = fresh_db();
        crate::db::sessions::upsert(&conn, &make_session("s1", "prod")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        let arr = v["s"].as_array().expect("s array present");
        assert_eq!(arr.len(), 1);
        // Compact session uses single-letter keys; verify host shows up.
        let s0 = &arr[0];
        // The encoder packs label/host/user — exact compact key
        // depends on encode_session_compact, but the host string
        // must be reachable via JSON traversal.
        let stringified = serde_json::to_string(s0).unwrap();
        assert!(stringified.contains("s1.example.com"));
        assert!(stringified.contains("prod"));
    }

    #[test]
    fn sessions_filter_by_selected_ids() {
        let conn = fresh_db();
        crate::db::sessions::upsert(&conn, &make_session("s1", "alpha")).unwrap();
        crate::db::sessions::upsert(&conn, &make_session("s2", "bravo")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        assert_eq!(v["s"].as_array().unwrap().len(), 1);
        // s2 must not have leaked.
        let stringified = serde_json::to_string(&v["s"]).unwrap();
        assert!(!stringified.contains("s2.example.com"));
    }

    #[test]
    fn sessions_password_omitted_when_include_passwords_false() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.password = "VERY-SECRET-PW".into();
        crate::db::sessions::upsert(&conn, &s).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_passwords = false;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        let stringified = serde_json::to_string(&v).unwrap();
        assert!(
            !stringified.contains("VERY-SECRET-PW"),
            "passwords must not leak when include_passwords=false"
        );
    }

    #[test]
    fn sessions_password_included_when_include_passwords_true() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.password = "EMITTED-PW".into();
        crate::db::sessions::upsert(&conn, &s).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_passwords = true;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        let stringified = serde_json::to_string(&v).unwrap();
        assert!(stringified.contains("EMITTED-PW"));
    }

    #[test]
    fn embedded_key_data_dedups_into_km() {
        let conn = fresh_db();
        let mut s1 = make_session("s1", "p1");
        s1.key_data = "PEM-A".into();
        s1.auth_type = "key".into();
        crate::db::sessions::upsert(&conn, &s1).unwrap();
        let mut s2 = make_session("s2", "p2");
        s2.key_data = "PEM-A".into(); // same bytes → dedup
        s2.auth_type = "key".into();
        crate::db::sessions::upsert(&conn, &s2).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_embedded_keys = true;
        input.selected_session_ids = vec!["s1".into(), "s2".into()];
        let v = payload_value(&conn, &input);
        let km = v["km"].as_object().expect("km dict");
        assert_eq!(km.len(), 1, "identical PEMs must dedup");
        let (_, value) = km.iter().next().unwrap();
        assert_eq!(value, "PEM-A");
    }

    #[test]
    fn embedded_keys_omitted_when_include_embedded_keys_false() {
        let conn = fresh_db();
        let mut s = make_session("s1", "p1");
        s.key_data = "INLINE-PEM".into();
        s.auth_type = "key".into();
        crate::db::sessions::upsert(&conn, &s).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_embedded_keys = false;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        // No `km` entry expected when no key shipped.
        assert!(v.get("km").is_none());
    }

    #[test]
    fn manager_key_metadata_emitted_when_include_all_manager_keys() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "manager-a", "MGR-PEM-A");
        let mut input = baseline_input();
        input.options.include_all_manager_keys = true;
        let v = payload_value(&conn, &input);
        let mk = v["mk"].as_object().expect("mk dict");
        assert_eq!(mk.len(), 1);
        let (_, meta) = mk.iter().next().unwrap();
        assert_eq!(meta["l"], "manager-a");
        assert_eq!(meta["t"], "ed25519");
        assert_eq!(meta["p"], "PUB-k1");
    }

    #[test]
    fn manager_keys_excluded_when_no_toggles_set() {
        let conn = fresh_db();
        insert_key(&conn, "k1", "manager-a", "MGR-PEM-A");
        let v = payload_value(&conn, &baseline_input());
        assert!(v.get("km").is_none());
        assert!(v.get("mk").is_none());
    }

    #[test]
    fn config_emitted_as_inline_object_when_include_config() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = Some(r#"{"theme":"dark"}"#.into());
        let v = payload_value(&conn, &input);
        assert_eq!(v["c"]["theme"], "dark");
    }

    #[test]
    fn config_omitted_when_payload_is_empty_string() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = Some(String::new());
        let v = payload_value(&conn, &input);
        assert!(v.get("c").is_none());
    }

    #[test]
    fn config_omitted_when_payload_malformed() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_config = true;
        input.config_json = Some("not-json".into());
        let v = payload_value(&conn, &input);
        // Parse failure must not leak a `c` field — silently dropped.
        assert!(v.get("c").is_none());
    }

    #[test]
    fn known_hosts_omitted_when_db_empty() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_known_hosts = true;
        let v = payload_value(&conn, &input);
        assert!(v.get("kh").is_none());
    }

    #[test]
    fn known_hosts_emitted_with_db_rows() {
        let conn = fresh_db();
        crate::db::known_hosts::upsert_by_host_port(
            &conn,
            "example.com",
            22,
            "ssh-ed25519",
            "AAAAB3NzaC1lZDI1NTE5AAAAINexample",
            1_700_000_000_000,
        )
        .unwrap();
        let mut input = baseline_input();
        input.options.include_known_hosts = true;
        let v = payload_value(&conn, &input);
        let kh = v["kh"].as_str().expect("kh string");
        assert!(kh.contains("example.com"));
        assert!(kh.contains("ssh-ed25519"));
    }

    #[test]
    fn empty_folders_emitted_in_eg_when_non_empty() {
        let conn = fresh_db();
        crate::db::sessions::upsert(&conn, &make_session("s1", "p1")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        input.selected_empty_folders = vec!["A".into(), "B/C".into()];
        let v = payload_value(&conn, &input);
        assert_eq!(v["eg"], json!(["A", "B/C"]));
    }

    #[test]
    fn empty_folders_omitted_when_list_empty() {
        let conn = fresh_db();
        crate::db::sessions::upsert(&conn, &make_session("s1", "p1")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        assert!(v.get("eg").is_none());
    }

    #[test]
    fn tags_emitted_with_compact_keys_when_db_has_tags() {
        let conn = fresh_db();
        crate::db::tags::upsert(
            &conn,
            &crate::db::tags::TagRow {
                id: "t1".into(),
                name: "prod".into(),
                color: Some("#abcdef".into()),
                created_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        let mut input = baseline_input();
        input.options.include_tags = true;
        let v = payload_value(&conn, &input);
        let arr = v["tg"].as_array().expect("tg array");
        assert_eq!(arr[0]["i"], "t1");
        assert_eq!(arr[0]["n"], "prod");
        assert_eq!(arr[0]["cl"], "#abcdef");
    }

    #[test]
    fn tags_omitted_when_db_has_no_tags() {
        let conn = fresh_db();
        let mut input = baseline_input();
        input.options.include_tags = true;
        let v = payload_value(&conn, &input);
        assert!(v.get("tg").is_none());
        assert!(v.get("st").is_none());
        assert!(v.get("ft").is_none());
    }

    #[test]
    fn session_tags_link_emitted_for_selected_sessions() {
        let conn = fresh_db();
        crate::db::tags::upsert(
            &conn,
            &crate::db::tags::TagRow {
                id: "t1".into(),
                name: "prod".into(),
                color: None,
                created_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        crate::db::sessions::upsert(&conn, &make_session("s1", "p1")).unwrap();
        crate::db::tags::link_session_tag(&conn, "s1", "t1").unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_tags = true;
        input.selected_session_ids = vec!["s1".into()];
        let v = payload_value(&conn, &input);
        let st = v["st"].as_array().expect("st array");
        assert_eq!(st[0]["si"], "s1");
        assert_eq!(st[0]["ti"], "t1");
    }

    #[test]
    fn snippets_emitted_with_compact_keys_when_db_has_snippets() {
        let conn = fresh_db();
        crate::db::snippets::upsert(
            &conn,
            &crate::db::snippets::SnippetRow {
                id: "sn1".into(),
                title: "list".into(),
                command: "ls -la".into(),
                description: "list files".into(),
                created_at_ms: 1_700_000_000_000,
                updated_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        let mut input = baseline_input();
        input.options.include_snippets = true;
        let v = payload_value(&conn, &input);
        let arr = v["sn"].as_array().expect("sn array");
        assert_eq!(arr[0]["i"], "sn1");
        assert_eq!(arr[0]["t"], "list");
        assert_eq!(arr[0]["cm"], "ls -la");
        assert_eq!(arr[0]["d"], "list files");
    }

    #[test]
    fn snippet_description_omitted_when_empty() {
        let conn = fresh_db();
        crate::db::snippets::upsert(
            &conn,
            &crate::db::snippets::SnippetRow {
                id: "sn1".into(),
                title: "list".into(),
                command: "ls".into(),
                description: String::new(),
                created_at_ms: 1_700_000_000_000,
                updated_at_ms: 1_700_000_000_000,
            },
        )
        .unwrap();
        let mut input = baseline_input();
        input.options.include_snippets = true;
        let v = payload_value(&conn, &input);
        assert!(v["sn"][0].get("d").is_none());
    }

    // ── Public encode wrappers ────────────────────────────────

    #[test]
    fn qr_export_payload_returns_non_empty_base64url() {
        let conn = fresh_db();
        let p = qr_export_payload(&conn, &baseline_input()).unwrap();
        assert!(!p.is_empty());
        // base64url-no-pad: only A-Z a-z 0-9 - _ allowed.
        assert!(p
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
    }

    #[test]
    fn qr_export_payload_size_matches_payload_length() {
        let conn = fresh_db();
        let p = qr_export_payload(&conn, &baseline_input()).unwrap();
        let n = qr_export_payload_size(&conn, &baseline_input()).unwrap();
        assert_eq!(n as usize, p.len());
    }

    #[test]
    fn qr_export_payload_size_grows_with_content() {
        let conn = fresh_db();
        let baseline = qr_export_payload_size(&conn, &baseline_input()).unwrap();
        crate::db::sessions::upsert(&conn, &make_session("s1", "p1")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];
        let with_session = qr_export_payload_size(&conn, &input).unwrap();
        assert!(
            with_session > baseline,
            "adding a session must grow payload"
        );
    }
}
