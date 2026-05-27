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
        for k in ssh_keys::list_all(conn)? {
            if k.private_key.is_empty() {
                continue;
            }
            let short = dedup.short_for(&k.private_key);
            dedup.manager_shorts.insert(short.clone());
            manager_meta.insert(short, (k.label, k.key_type, k.public_key));
        }
    } else if input.options.include_manager_keys {
        let by_pem: HashMap<String, ssh_keys::SshKeyRow> = ssh_keys::list_all(conn)?
            .into_iter()
            .map(|k| (k.private_key.clone(), k))
            .collect();
        for short in &dedup.manager_shorts {
            if let Some((pem, _)) = dedup.key_to_short.iter().find(|(_, v)| *v == short) {
                if let Some(k) = by_pem.get(pem) {
                    manager_meta.insert(
                        short.clone(),
                        (k.label.clone(), k.key_type.clone(), k.public_key.clone()),
                    );
                }
            }
        }
    }
    Ok(manager_meta)
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
    fn payload_carries_current_format_version() {
        // The composer stamps `SchemaVersions::QR_PAYLOAD` verbatim;
        // assert against the constant rather than a literal so a future
        // bump can't leave this test pinning a stale number.
        let conn = fresh_db();
        let v = payload_value(&conn, &baseline_input());
        assert_eq!(v["v"], crate::migration::SchemaVersions::QR_PAYLOAD);
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
        // The link references the session by its short id (the `i`
        // field on the compact session), not the raw DB UUID — the
        // decoder mints a fresh session id and remaps the short onto
        // it, so emitting the UUID here would dangle on import.
        let short = v["s"].as_array().expect("s array")[0]["i"]
            .as_str()
            .expect("session short id");
        let st = v["st"].as_array().expect("st array");
        assert_eq!(st[0]["si"].as_str(), Some(short));
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
    fn export_payload_round_trips_through_canonical_decoder() {
        // End-to-end guard: the real composer output (DB → JSON →
        // deflate → base64url) must decode cleanly through the
        // production `qr_codec_decode::decode_payload`. The existing
        // codec tests feed hand-written JSON; this is the only path
        // that proves the composer's emitted shape and the decoder's
        // accepted shape actually agree on live data.
        let conn = fresh_db();
        let mut s = make_session("s1", "prod");
        s.password = "hunter2".into();
        crate::db::sessions::upsert(&conn, &s).unwrap();
        crate::db::known_hosts::upsert_by_host_port(
            &conn,
            "s1.example.com",
            22,
            "ssh-ed25519",
            "AAAAB3NzaC1lZDI1NTE5AAAAINexample",
            1_700_000_000_000,
        )
        .unwrap();

        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.options.include_passwords = true;
        input.options.include_config = true;
        input.options.include_known_hosts = true;
        input.selected_session_ids = vec!["s1".into()];
        input.config_json = Some(r#"{"theme":"dark","fontSize":14}"#.into());

        let payload = qr_export_payload(&conn, &input).unwrap();
        let decoded = crate::qr_codec_decode::decode_payload(&payload)
            .expect("real composer output must decode through the canonical decoder");

        let sessions: Vec<Value> =
            serde_json::from_str(decoded.pending.sessions_json.as_deref().unwrap()).unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0]["host"], "s1.example.com");
        assert_eq!(sessions[0]["password"], "hunter2");
        assert!(decoded.pending.config_json.is_some());
        assert!(decoded.pending.known_hosts_text.is_some());
    }

    #[test]
    fn export_payload_round_trips_with_deeplink_wrapper() {
        // The QR canvas encodes the `letsflutssh://import?d=<payload>`
        // deeplink, and the in-app scan/paste importer feeds that whole
        // string back to `qr_import_open`, which strips the wrapper via
        // `extract_payload_from_uri` before decoding. Exercise that exact
        // hop so a scheme/param-name drift between the Dart wrapper and
        // the Rust stripper can't slip through unit-tested in isolation.
        let conn = fresh_db();
        crate::db::sessions::upsert(&conn, &make_session("s1", "prod")).unwrap();
        let mut input = baseline_input();
        input.options.include_sessions = true;
        input.selected_session_ids = vec!["s1".into()];

        let payload = qr_export_payload(&conn, &input).unwrap();
        let deeplink = format!("letsflutssh://import?d={payload}");
        let stripped = crate::qr_codec_decode::extract_payload_from_uri(&deeplink)
            .expect("canonical deeplink must strip to its d= payload");
        assert_eq!(stripped, payload);
        assert!(crate::qr_codec_decode::decode_payload(&stripped).is_ok());
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
