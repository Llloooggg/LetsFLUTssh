/// Unit tests extracted from archive/qr_compose.rs
/// Declared via `#[path] mod tests;` in the source file.
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
