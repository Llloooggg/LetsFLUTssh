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
        recordings_root: None,
        recording_db_key: None,
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

// ── Export → read roundtrip (writer/reader version parity) ──

#[test]
fn export_at_current_version_reads_back() {
    // End-to-end guard for the writer/reader version contract: an
    // archive stamped with `SchemaVersions::ARCHIVE` (what the Dart
    // export path passes) must read back through the canonical
    // `read_archive_to_pending` reader. Every other compose test
    // stamps an arbitrary version (7 / 9) and only inspects the ZIP
    // bytes, so none of them would catch the writer drifting away
    // from the version the reader's `1..=ARCHIVE` range accepts —
    // the same isolation gap that left QR import rejecting every
    // export. Raw ZIP (no master password) keeps the test off the
    // Argon2id path.
    let conn = fresh_db();
    insert_session(&conn, make_session("s1", "prod"));
    let mut input = baseline_input();
    input.schema_version = i64::from(crate::migration::SchemaVersions::ARCHIVE);
    input.options.include_sessions = true;
    input.selected_session_ids = vec!["s1".into()];

    let bytes = export_archive(&conn, &input).unwrap();
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("roundtrip.lfs");
    std::fs::write(&path, &bytes).unwrap();

    let (pending, preview) = crate::archive::read_archive_to_pending(path.to_str().unwrap(), "")
        .expect("an archive at the current version must read back");
    assert_eq!(
        preview.schema_version,
        i64::from(crate::migration::SchemaVersions::ARCHIVE),
    );
    let sessions: Value = serde_json::from_str(pending.sessions_json.as_deref().unwrap()).unwrap();
    assert!(serde_json::to_string(&sessions)
        .unwrap()
        .contains("s1.example.com"));
}
