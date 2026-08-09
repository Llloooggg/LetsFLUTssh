/// Unit tests extracted from sync/merge.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::archive::PendingImport;
use crate::db::{bootstrap_schema, sessions, snippets, ssh_keys, tags, Connection, Db};

fn fresh_db() -> Db {
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    Db::from_raw_for_tests(conn)
}

fn pending_with(sessions_json: Option<&str>) -> PendingImport {
    PendingImport {
        manifest_json: None,
        sessions_json: sessions_json.map(String::from),
        keys_json: None,
        tags_json: None,
        session_tags_json: None,
        folder_tags_json: None,
        snippets_json: None,
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
    }
}

#[test]
fn merge_inserts_peer_only_session() {
    let db = fresh_db();
    let json = r#"[{
        "id":"s1","label":"prod","folder":"",
        "host":"h.example.com","port":22,"user":"root",
        "auth_type":"password","password":"pw",
        "key_path":"","key_data":"","passphrase":"",
        "created_at":"2024-01-01T00:00:00.000Z",
        "updated_at":"2024-01-01T00:00:00.000Z"
    }]"#;
    let pending = pending_with(Some(json));
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.sessions_merged, 1);
    let rows = db.with_conn(sessions::list_all).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].id, "s1");
    assert_eq!(rows[0].label, "prod");
}

#[test]
fn merge_skips_stale_peer_session() {
    // Local has s1 with updated_at = 1700000000000; peer has the
    // same id with an older updated_at. LWW must keep the local
    // shape.
    let db = fresh_db();
    let row = sessions::SessionRow {
        id: "s1".into(),
        label: "local-label".into(),
        host: "local.example.com".into(),
        port: 22,
        user: "root".into(),
        auth_type: "password".into(),
        password: "local-pw".into(),
        created_at_ms: 1_700_000_000_000,
        updated_at_ms: 1_700_000_000_000,
        ..Default::default()
    };
    db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
    let peer_json = r#"[{
        "id":"s1","label":"peer-label","folder":"",
        "host":"peer.example.com","port":22,"user":"root",
        "auth_type":"password","password":"peer-pw",
        "key_path":"","key_data":"","passphrase":"",
        "created_at":"2023-01-01T00:00:00.000Z",
        "updated_at":"2023-01-01T00:00:00.000Z"
    }]"#;
    let pending = pending_with(Some(peer_json));
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.sessions_merged, 0);
    let rows = db.with_conn(sessions::list_all).unwrap();
    assert_eq!(rows[0].label, "local-label");
}

#[test]
fn merge_overwrites_with_newer_peer_session() {
    let db = fresh_db();
    let row = sessions::SessionRow {
        id: "s1".into(),
        label: "old".into(),
        host: "h".into(),
        port: 22,
        user: "root".into(),
        auth_type: "password".into(),
        created_at_ms: 1_700_000_000_000,
        updated_at_ms: 1_700_000_000_000,
        ..Default::default()
    };
    db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
    let peer_json = r#"[{
        "id":"s1","label":"new","folder":"",
        "host":"h","port":22,"user":"root",
        "auth_type":"password","password":"",
        "key_path":"","key_data":"","passphrase":"",
        "created_at":"2024-01-01T00:00:00.000Z",
        "updated_at":"2030-01-01T00:00:00.000Z"
    }]"#;
    let pending = pending_with(Some(peer_json));
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.sessions_merged, 1);
    let rows = db.with_conn(sessions::list_all).unwrap();
    assert_eq!(rows[0].label, "new");
}

#[test]
fn merge_keeps_local_only_session() {
    let db = fresh_db();
    let row = sessions::SessionRow {
        id: "local-only".into(),
        label: "kept".into(),
        host: "h".into(),
        port: 22,
        user: "root".into(),
        auth_type: "password".into(),
        created_at_ms: 1_700_000_000_000,
        updated_at_ms: 1_700_000_000_000,
        ..Default::default()
    };
    db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
    let pending = pending_with(Some("[]"));
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.sessions_merged, 0);
    let rows = db.with_conn(sessions::list_all).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].id, "local-only");
}

#[test]
fn merge_session_tag_edges_are_unioned() {
    let db = fresh_db();
    // Seed two tags + one session on the local side.
    let session = sessions::SessionRow {
        id: "s1".into(),
        label: "s1".into(),
        host: "h".into(),
        user: "u".into(),
        port: 22,
        auth_type: "password".into(),
        created_at_ms: 1,
        updated_at_ms: 1,
        ..Default::default()
    };
    db.with_conn(|c| sessions::upsert(c, &session)).unwrap();
    let t_local = tags::TagRow {
        id: "t1".into(),
        name: "local".into(),
        color: None,
        created_at_ms: 1,
    };
    let t_peer = tags::TagRow {
        id: "t2".into(),
        name: "peer".into(),
        color: None,
        created_at_ms: 1,
    };
    db.with_conn(|c| tags::upsert(c, &t_local)).unwrap();
    db.with_conn(|c| tags::upsert(c, &t_peer)).unwrap();
    db.with_conn(|c| tags::link_session_tag(c, "s1", "t1"))
        .unwrap();
    // Peer also knows the same session and links it to t2.
    let pending = PendingImport {
        manifest_json: None,
        sessions_json: None,
        keys_json: None,
        tags_json: None,
        session_tags_json: Some(r#"[{"session_id":"s1","tag_id":"t2"}]"#.into()),
        folder_tags_json: None,
        snippets_json: None,
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
    };
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.session_tag_edges_merged, 1);
    let ids = db
        .with_conn(|c| tags::list_session_tag_ids(c, "s1"))
        .unwrap();
    assert!(ids.contains(&"t1".to_string()));
    assert!(ids.contains(&"t2".to_string()));
}

#[test]
fn merge_keys_skips_stale_peer_row() {
    let db = fresh_db();
    let row = ssh_keys::SshKeyRow {
        id: "k1".into(),
        label: "local".into(),
        private_key: "P".into(),
        public_key: "P".into(),
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
    };
    db.with_conn(|c| ssh_keys::upsert(c, &row)).unwrap();
    let peer = r#"[{
        "id":"k1","label":"peer","private_key":"X","public_key":"X",
        "key_type":"ed25519","is_generated":true,
        "created_at":"2020-01-01T00:00:00.000Z"
    }]"#;
    let pending = PendingImport {
        manifest_json: None,
        sessions_json: None,
        keys_json: Some(peer.into()),
        tags_json: None,
        session_tags_json: None,
        folder_tags_json: None,
        snippets_json: None,
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
    };
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.keys_merged, 0);
    let rows = db.with_conn(ssh_keys::list_all).unwrap();
    assert_eq!(rows[0].label, "local");
}

#[test]
fn merge_snippets_overwrites_when_peer_newer() {
    let db = fresh_db();
    let local = snippets::SnippetRow {
        id: "sn1".into(),
        title: "old".into(),
        command: "echo old".into(),
        description: String::new(),
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    db.with_conn(|c| snippets::upsert(c, &local)).unwrap();
    let peer = r#"[{
        "id":"sn1","title":"new","command":"echo new","description":"",
        "created_at":"2020-01-01T00:00:00.000Z",
        "updated_at":"2030-01-01T00:00:00.000Z"
    }]"#;
    let pending = PendingImport {
        manifest_json: None,
        sessions_json: None,
        keys_json: None,
        tags_json: None,
        session_tags_json: None,
        folder_tags_json: None,
        snippets_json: Some(peer.into()),
        session_snippets_json: None,
        empty_folders_json: None,
        config_json: None,
        known_hosts_text: None,
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
    };
    let outcome = db
        .with_conn_mut(|c| merge_pending_into_local(c, &pending))
        .unwrap();
    assert_eq!(outcome.snippets_merged, 1);
    let rows = db.with_conn(snippets::list_all).unwrap();
    assert_eq!(rows[0].title, "new");
}
