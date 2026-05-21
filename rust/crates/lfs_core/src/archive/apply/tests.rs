use super::*;

fn fresh_db() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
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
        apply_recordings: false,
    }
}

fn empty_pending() -> PendingImport {
    PendingImport {
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
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
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
            ..empty_pending()
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
    let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k_new","label":"Fresh","private_key":"NEW","public_key":"ssh-ed25519 AAAADUPE","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
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
        sessions_json: Some(json.to_string()),
        ..empty_pending()
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
        known_hosts_text: Some(
            "# leading comment\nfoo.example ssh-ed25519 AAAA\nbar.example:2222 ssh-rsa BBBB\n"
                .to_string(),
        ),
        ..empty_pending()
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
            tags_json: Some(
                r##"[{"id":"t1","name":"prod","color":"#ff0000","created_at":"2026-04-26T00:00:00.000Z"}]"##
                    .to_string(),
            ),
            snippets_json: Some(
                r#"[{"id":"sn1","title":"ll","command":"ls -la","description":"long list","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
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
            sessions_json: Some("not-json".to_string()),
            keys_json: Some(
                r#"[{"id":"k1","label":"good","private_key":"P","public_key":"ssh-ed25519 X","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.keys_applied, 1);
    assert_eq!(result.sessions_applied, 0);
    assert!(!result.errors.is_empty());
}

// ── Per-field session round-trip ────────────────────────────

#[test]
fn apply_sessions_lands_every_field_on_disk() {
    let conn = fresh_db();
    let json = r#"[{
            "id":"s1",
            "label":"prod-server",
            "folder":"",
            "host":"host.example",
            "port":2222,
            "user":"deploy",
            "auth_type":"key",
            "password":"pw-1",
            "key_path":"/home/u/.ssh/id_rsa",
            "key_data":"PRIV-PEM",
            "key_id":"k-ext",
            "passphrase":"kpass",
            "notes":"important box",
            "extras":{"shell":"zsh"},
            "via_session_id":"bastion-1",
            "via_override":{"host":"bastion","port":2200,"user":"jump"},
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
    // Seed bastion target so via_session_id FK passes,
    // and the manager key so key_id FK passes.
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "bastion-1".into(),
            label: "bastion".into(),
            host: "b".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
            ..Default::default()
        },
    )
    .unwrap();
    ssh_keys::upsert(
        &conn,
        &ssh_keys::SshKeyRow {
            id: "k-ext".into(),
            label: "ext".into(),
            private_key: "P".into(),
            public_key: "ssh-ed25519 X".into(),
            key_type: "ssh-ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
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
    let pending = PendingImport {
        sessions_json: Some(json.to_string()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.sessions_applied, 1);
    let row = sessions::get(&conn, "s1").unwrap().unwrap();
    // Every json_string mapping verified.
    assert_eq!(row.label, "prod-server");
    assert_eq!(row.host, "host.example");
    assert_eq!(row.port, 2222);
    assert_eq!(row.user, "deploy");
    assert_eq!(row.auth_type, "key");
    assert_eq!(row.password, "pw-1");
    assert_eq!(row.key_path, "/home/u/.ssh/id_rsa");
    assert_eq!(row.key_data, "PRIV-PEM");
    assert_eq!(row.key_id.as_deref(), Some("k-ext"));
    assert_eq!(row.passphrase, "kpass");
    assert_eq!(row.notes, "important box");
    assert!(row.extras.contains("zsh"));
    assert_eq!(row.via_session_id.as_deref(), Some("bastion-1"));
    assert_eq!(row.via_host.as_deref(), Some("bastion"));
    assert_eq!(row.via_port, Some(2200));
    assert_eq!(row.via_user.as_deref(), Some("jump"));
}

#[test]
fn apply_session_skips_row_with_blank_id() {
    let conn = fresh_db();
    let pending = PendingImport {
        sessions_json: Some(
            r#"[{"id":"","label":"x","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                .to_string(),
        ),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.sessions_applied, 0);
    assert!(result.errors.iter().any(|e| e.contains("missing id")));
}

#[test]
fn apply_session_uses_created_at_iso_when_provided() {
    let conn = fresh_db();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"x","host":"a","port":22,"user":"u","auth_type":"password","created_at":"2024-01-01T00:00:00.000Z","updated_at":"2024-01-01T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 9_999_000_000_000)
            .unwrap();
    assert_eq!(result.sessions_applied, 1);
    let row = sessions::get(&conn, "s1").unwrap().unwrap();
    // 2024-01-01T00:00:00Z = 1704067200000 ms.
    assert_eq!(row.created_at_ms, 1_704_067_200_000);
    // updated_at_ms is always now_ms (the apply moment).
    assert_eq!(row.updated_at_ms, 9_999_000_000_000);
}

// ── Folder tree from session.folder paths ──────────────────

#[test]
fn apply_folder_tree_builds_nested_hierarchy_and_assigns_ids() {
    let conn = fresh_db();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[
                    {"id":"s1","label":"l1","folder":"Prod/Web","host":"a","port":22,"user":"u","auth_type":"password"},
                    {"id":"s2","label":"l2","folder":"Prod/DB","host":"b","port":22,"user":"u","auth_type":"password"},
                    {"id":"s3","label":"l3","folder":"Staging","host":"c","port":22,"user":"u","auth_type":"password"}
                ]"#
                .to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    // Folders: Prod, Prod/Web, Prod/DB, Staging = 4 distinct
    // folder rows.
    assert_eq!(result.folders_applied, 4);
    let all = folders::list_all(&conn).unwrap();
    let names: HashSet<&str> = all.iter().map(|f| f.name.as_str()).collect();
    assert!(names.contains("Prod"));
    assert!(names.contains("Web"));
    assert!(names.contains("DB"));
    assert!(names.contains("Staging"));
    // Web's parent is Prod, DB's parent is Prod, Staging is root.
    let prod = all.iter().find(|f| f.name == "Prod").unwrap();
    let web = all.iter().find(|f| f.name == "Web").unwrap();
    let db = all.iter().find(|f| f.name == "DB").unwrap();
    let staging = all.iter().find(|f| f.name == "Staging").unwrap();
    assert!(prod.parent_id.is_none());
    assert_eq!(web.parent_id.as_deref(), Some(prod.id.as_str()));
    assert_eq!(db.parent_id.as_deref(), Some(prod.id.as_str()));
    assert!(staging.parent_id.is_none());
    // Sessions land with the resolved folder_id of their leaf.
    let s1 = sessions::get(&conn, "s1").unwrap().unwrap();
    assert_eq!(s1.folder_id.as_deref(), Some(web.id.as_str()));
    let s2 = sessions::get(&conn, "s2").unwrap().unwrap();
    assert_eq!(s2.folder_id.as_deref(), Some(db.id.as_str()));
    let s3 = sessions::get(&conn, "s3").unwrap().unwrap();
    assert_eq!(s3.folder_id.as_deref(), Some(staging.id.as_str()));
}

#[test]
fn apply_folder_tree_skips_when_folder_path_blank() {
    let conn = fresh_db();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l1","folder":"","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.folders_applied, 0);
    let s1 = sessions::get(&conn, "s1").unwrap().unwrap();
    assert!(s1.folder_id.is_none());
}

#[test]
fn apply_empty_folders_creates_rows_for_paths_with_no_sessions() {
    let conn = fresh_db();
    let pending = PendingImport {
        sessions_json: Some("[]".to_string()),
        empty_folders_json: Some(r#"["A/B","C"]"#.to_string()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    // A, A/B, C = 3 folder rows.
    assert_eq!(result.folders_applied, 3);
    let all = folders::list_all(&conn).unwrap();
    assert_eq!(all.len(), 3);
}

#[test]
fn apply_empty_folders_dedups_against_session_folders() {
    let conn = fresh_db();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"A","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            // "A" already exists from sessions_json — must not double-create.
            empty_folders_json: Some(r#"["A","B"]"#.to_string()),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    // 2 folders: A (from sessions) + B (from empty_folders).
    assert_eq!(result.folders_applied, 2);
}

#[test]
fn apply_empty_folders_skips_blank_paths() {
    let conn = fresh_db();
    let pending = PendingImport {
        sessions_json: Some("[]".to_string()),
        empty_folders_json: Some(r#"["","A"]"#.to_string()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.folders_applied, 1);
}

// ── Per-toggle gating ──────────────────────────────────────

#[test]
fn apply_keys_off_skips_keys_stage_entirely() {
    let conn = fresh_db();
    let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k1","label":"l","private_key":"P","public_key":"ssh-ed25519 X","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    let mut opts = merge_all_options();
    opts.apply_keys = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.keys_applied, 0);
    assert!(ssh_keys::get(&conn, "k1").unwrap().is_none());
}

#[test]
fn apply_session_tags_requires_both_sessions_and_tags_toggles() {
    let conn = fresh_db();
    // Pre-seed session + tag so the link target exists.
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "s1".into(),
            label: "l".into(),
            host: "a".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
            ..Default::default()
        },
    )
    .unwrap();
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "t1".into(),
            name: "n".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();
    let pending = PendingImport {
        session_tags_json: Some(r#"[{"session_id":"s1","tag_id":"t1"}]"#.to_string()),
        ..empty_pending()
    };
    // Tags off → link skipped.
    let mut opts = merge_all_options();
    opts.apply_tags = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.session_tags_applied, 0);
    // Sessions off → also skipped.
    let mut opts = merge_all_options();
    opts.apply_sessions = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.session_tags_applied, 0);
    // Both on → link applied.
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.session_tags_applied, 1);
    assert_eq!(tags::list_session_tag_ids(&conn, "s1").unwrap(), vec!["t1"]);
}

#[test]
fn apply_folder_tags_resolves_paths_against_freshly_built_folder_tree() {
    let conn = fresh_db();
    // Tag must exist on the receiving side; the import may have
    // staged it via tags.json (gated by apply_tags) and the
    // folder must materialise via sessions.json or
    // empty_folders.json so the path → id map carries it.
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "t1".into(),
            name: "n".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"Work/Prod","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            folder_tags_json: Some(
                r#"[{"folder_path":"Work/Prod","tag_id":"t1"}]"#.to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.folder_tags_applied, 1);
    // The freshly-minted folder id for "Work/Prod" must carry
    // the tag now.
    let folder_id = folders::list_all(&conn)
        .unwrap()
        .into_iter()
        .find(|f| f.name == "Prod")
        .map(|f| f.id)
        .expect("Prod folder created");
    assert_eq!(
        tags::list_folder_tag_ids(&conn, &folder_id).unwrap(),
        vec!["t1"],
    );
}

#[test]
fn apply_folder_tags_skips_unknown_paths() {
    let conn = fresh_db();
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "t1".into(),
            name: "n".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();
    // No sessions / empty_folders ⇒ Work/Prod never materialises;
    // the tag link must be silently dropped, not error.
    let pending = PendingImport {
        folder_tags_json: Some(r#"[{"folder_path":"Work/Prod","tag_id":"t1"}]"#.to_string()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.folder_tags_applied, 0);
    assert!(result.errors.is_empty(), "errors: {:?}", result.errors);
}

#[test]
fn apply_folder_tags_requires_both_sessions_and_tags_toggles() {
    let conn = fresh_db();
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "t1".into(),
            name: "n".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"Work","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            folder_tags_json: Some(
                r#"[{"folder_path":"Work","tag_id":"t1"}]"#.to_string(),
            ),
            ..empty_pending()
        };
    // Tags off → link skipped.
    let mut opts = merge_all_options();
    opts.apply_tags = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.folder_tags_applied, 0);
    // Sessions off → also skipped (the folder never materialises).
    let mut opts = merge_all_options();
    opts.apply_sessions = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.folder_tags_applied, 0);
    // Both on → link applied.
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.folder_tags_applied, 1);
}

#[test]
fn apply_session_snippets_requires_both_sessions_and_snippets_toggles() {
    let conn = fresh_db();
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "s1".into(),
            label: "l".into(),
            host: "a".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
            ..Default::default()
        },
    )
    .unwrap();
    snippets::upsert(
        &conn,
        &snippets::SnippetRow {
            id: "sn1".into(),
            title: "t".into(),
            command: "c".into(),
            description: "".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
        },
    )
    .unwrap();
    let pending = PendingImport {
        session_snippets_json: Some(r#"[{"session_id":"s1","snippet_id":"sn1"}]"#.to_string()),
        ..empty_pending()
    };
    let mut opts = merge_all_options();
    opts.apply_snippets = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.session_snippets_applied, 0);
    let mut opts = merge_all_options();
    opts.apply_sessions = false;
    let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.session_snippets_applied, 0);
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.session_snippets_applied, 1);
}

#[test]
fn apply_session_link_skips_blank_ids() {
    let conn = fresh_db();
    let pending = PendingImport {
        session_tags_json: Some(
            r#"[{"session_id":"","tag_id":"t1"},{"session_id":"s1","tag_id":""}]"#.to_string(),
        ),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.session_tags_applied, 0);
    assert!(result.errors.is_empty(), "blank-id rows skip silently");
}

// ── Replace mode ──────────────────────────────────────────

#[test]
fn replace_mode_clears_existing_sessions_and_tags() {
    let mut conn = fresh_db();
    // Pre-seed live data.
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "old-s".into(),
            label: "old".into(),
            host: "a".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
            ..Default::default()
        },
    )
    .unwrap();
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "old-t".into(),
            name: "old".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"new-s","label":"new","host":"b","port":22,"user":"u","auth_type":"password","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            tags_json: Some(
                r##"[{"id":"new-t","name":"new","color":"#fff","created_at":"2026-04-26T00:00:00.000Z"}]"##
                    .to_string(),
            ),
            ..empty_pending()
        };
    let mut opts = merge_all_options();
    opts.mode = ImportMode::Replace;
    let result = apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
    assert_eq!(result.sessions_applied, 1);
    assert_eq!(result.tags_applied, 1);
    // Old rows cleared, new ones present.
    assert!(sessions::get(&conn, "old-s").unwrap().is_none());
    assert!(sessions::get(&conn, "new-s").unwrap().is_some());
    let all_tags = tags::list_all(&conn).unwrap();
    assert_eq!(all_tags.len(), 1);
    assert_eq!(all_tags[0].id, "new-t");
}

#[test]
fn replace_mode_does_not_wipe_manager_keys() {
    let mut conn = fresh_db();
    ssh_keys::upsert(
        &conn,
        &ssh_keys::SshKeyRow {
            id: "user-k".into(),
            label: "mine".into(),
            private_key: "P".into(),
            public_key: "ssh-ed25519 USERKEY".into(),
            key_type: "ssh-ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
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
    let pending = empty_pending();
    let mut opts = merge_all_options();
    opts.mode = ImportMode::Replace;
    apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
    // Manager key untouched — replace intentionally skips ssh_keys.
    assert!(ssh_keys::get(&conn, "user-k").unwrap().is_some());
}

#[test]
fn replace_mode_clears_known_hosts_when_toggle_on() {
    let mut conn = fresh_db();
    known_hosts::upsert_by_host_port(&conn, "old.example", 22, "ssh-rsa", "OLDK", 0).unwrap();
    let pending = PendingImport {
        known_hosts_text: Some("new.example ssh-ed25519 NEWK".to_string()),
        ..empty_pending()
    };
    let mut opts = merge_all_options();
    opts.mode = ImportMode::Replace;
    apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
    // Old host gone, new host present.
    assert!(known_hosts::get_by_host_port(&conn, "old.example", 22)
        .unwrap()
        .is_none());
    assert!(known_hosts::get_by_host_port(&conn, "new.example", 22)
        .unwrap()
        .is_some());
}

/// Replace mode is all-or-nothing — a per-row apply error
/// MUST roll the transaction back so the user does not end up
/// with their original data wiped + a partially-imported new
/// state on top. Pre-fix shape kept the wipe (and the rows
/// that did succeed) committed; this test pins the rollback
/// guarantee on `errors.is_empty() == false`.
#[test]
fn replace_mode_rolls_back_on_per_row_apply_error() {
    let mut conn = fresh_db();
    // Pre-seed a session + tag the user must keep on a failed
    // import.
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "keep-s".into(),
            label: "keep".into(),
            host: "a".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            created_at_ms: 0,
            updated_at_ms: 0,
            ..Default::default()
        },
    )
    .unwrap();
    tags::upsert(
        &conn,
        &tags::TagRow {
            id: "keep-t".into(),
            name: "keep".into(),
            color: None,
            created_at_ms: 0,
        },
    )
    .unwrap();

    // Hand the apply driver an unparseable sessions JSON so
    // `apply_sessions` records an error. Replace mode must
    // surface that as a rollback.
    let pending = PendingImport {
        sessions_json: Some("not valid json".to_string()),
        ..empty_pending()
    };
    let mut opts = merge_all_options();
    opts.mode = ImportMode::Replace;
    let result = apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();

    assert!(
        result.rolled_back,
        "expected rolled_back flag, got: {result:?}",
    );
    assert!(!result.errors.is_empty(), "errors must propagate");

    // Pre-import data survives — the rollback restored the
    // wipe step too.
    assert!(
        sessions::get(&conn, "keep-s").unwrap().is_some(),
        "pre-import session lost on rollback",
    );
    let surviving_tags = tags::list_all(&conn).unwrap();
    assert!(
        surviving_tags.iter().any(|t| t.id == "keep-t"),
        "pre-import tag lost on rollback",
    );
}

// ── known_hosts parsing ───────────────────────────────────

#[test]
fn apply_known_hosts_default_port_22_when_omitted() {
    let conn = fresh_db();
    let pending = PendingImport {
        known_hosts_text: Some("h.example ssh-ed25519 KEYY".to_string()),
        ..empty_pending()
    };
    apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000).unwrap();
    // Default port is 22 — entry must land at (h.example, 22).
    assert!(known_hosts::get_by_host_port(&conn, "h.example", 22)
        .unwrap()
        .is_some());
}

#[test]
fn apply_known_hosts_parses_explicit_port() {
    let conn = fresh_db();
    let pending = PendingImport {
        known_hosts_text: Some("h.example:9000 ssh-rsa KEYY".to_string()),
        ..empty_pending()
    };
    apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000).unwrap();
    assert!(known_hosts::get_by_host_port(&conn, "h.example", 9000)
        .unwrap()
        .is_some());
}

#[test]
fn apply_known_hosts_skips_comments_and_blanks() {
    let conn = fresh_db();
    let text = "\n# comment line\n\n  \nh1 ssh-rsa AAAA\n# another comment\nh2 ssh-rsa BBBB\n";
    let pending = PendingImport {
        known_hosts_text: Some(text.into()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.known_hosts_applied, 2);
}

#[test]
fn apply_known_hosts_skips_lines_with_too_few_columns() {
    let conn = fresh_db();
    let text = "incomplete line\nh ssh-rsa KEYY";
    let pending = PendingImport {
        known_hosts_text: Some(text.into()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.known_hosts_applied, 1);
}

#[test]
fn windows_reserved_name_matches_dos_devices_case_insensitive() {
    // Pin the Win32 reserved-name list the importer warns
    // about. Matches MS-DOS device names: `CON`, `PRN`, `AUX`,
    // `NUL`, `COM1..9`, `LPT1..9`. `COM0` / `LPT0` are NOT
    // reserved on modern Windows. Extension-stripping mirrors
    // CMD's pre-resolution stage so `con.txt` is flagged.
    for label in ["CON", "con", "Con", "PRN", "AUX", "NUL"] {
        assert!(
            is_windows_reserved_name(label),
            "{label} should be reserved"
        );
    }
    for label in ["COM1", "COM9", "LPT1", "LPT9", "com1", "lpt9"] {
        assert!(
            is_windows_reserved_name(label),
            "{label} should be reserved"
        );
    }
    assert!(is_windows_reserved_name("con.txt"));
    // Non-matches.
    for label in [
        "CON ",
        "MYCON",
        "COM",
        "COM0",
        "LPT0",
        "COM10",
        "LPT10",
        "production",
        "Stage",
    ] {
        assert!(
            !is_windows_reserved_name(label),
            "{label} should NOT be reserved"
        );
    }
}

#[test]
fn apply_folder_tree_imports_windows_reserved_label() {
    // Folder labels are tree display strings, not filesystem
    // paths — the warning is advisory and the row must still
    // land. The accompanying `app_log_warn!` cannot be observed
    // from a standalone unit test (no app singleton), so this
    // test covers the import-doesn't-reject leg; the matching
    // predicate is covered separately.
    let conn = fresh_db();
    let sessions = r#"[{
            "id":"s_con",
            "label":"hostnamed",
            "host":"h","port":22,"user":"u","auth_type":"password",
            "folder":"CON",
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
    let pending = PendingImport {
        sessions_json: Some(sessions.to_string()),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    // Folder still imports — the warning is advisory only.
    assert_eq!(result.folders_applied, 1);
    let rows = folders::list_all(&conn).unwrap();
    assert!(rows.iter().any(|r| r.name == "CON"));
}

#[test]
fn apply_known_hosts_skips_invalid_base64_key_body() {
    // `not-base64!!!` contains characters outside the standard
    // base64 alphabet — the row must drop at import time so a
    // corrupt key body never reaches the connect path. Mixed
    // with a valid row so the per-line skip is asserted (good
    // row still lands). Driver-level call so the test can read
    // `outcome.warnings` (not surfaced on the legacy
    // `ApplyResult` shape).
    let mut conn = fresh_db();
    let text = "bad.example ssh-ed25519 not-base64!!!\ngood.example ssh-rsa AAAA";
    let pending = PendingImport {
        known_hosts_text: Some(text.into()),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.known_hosts_applied, 1);
    assert!(known_hosts::get_by_host_port(&conn, "bad.example", 22)
        .unwrap()
        .is_none());
    assert!(known_hosts::get_by_host_port(&conn, "good.example", 22)
        .unwrap()
        .is_some());
    assert!(outcome
        .warnings
        .iter()
        .any(|w| w.contains("invalid base64")));
}

// ── port + json_i64 ───────────────────────────────────────

#[test]
fn apply_session_port_round_trips_actual_value() {
    let conn = fresh_db();
    let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","host":"h","port":12345,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000).unwrap();
    let row = sessions::get(&conn, "s1").unwrap().unwrap();
    // json_i64 mutants would replace the value with 0 / 1 / -1.
    assert_eq!(row.port, 12345);
}

// ── tags / snippets content ───────────────────────────────

#[test]
fn apply_tags_lands_color_and_name_per_row() {
    let conn = fresh_db();
    let pending = PendingImport {
            tags_json: Some(
                r##"[
                    {"id":"t1","name":"prod","color":"#ff0000","created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t2","name":"staging","color":"","created_at":"2026-04-26T00:00:00.000Z"}
                ]"##
                .to_string(),
            ),
            ..empty_pending()
        };
    apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000).unwrap();
    let all = tags::list_all(&conn).unwrap();
    let t1 = all.iter().find(|t| t.id == "t1").unwrap();
    let t2 = all.iter().find(|t| t.id == "t2").unwrap();
    assert_eq!(t1.name, "prod");
    assert_eq!(t1.color.as_deref(), Some("#ff0000"));
    // Empty color string stored as None.
    assert!(t2.color.is_none());
}

#[test]
fn apply_tags_skips_row_with_blank_id_or_name() {
    let conn = fresh_db();
    let pending = PendingImport {
        tags_json: Some(
            r##"[
                    {"id":"","name":"x","color":null,"created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t1","name":"","color":null,"created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t2","name":"good","color":null,"created_at":"2026-04-26T00:00:00.000Z"}
                ]"##
            .to_string(),
        ),
        ..empty_pending()
    };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.tags_applied, 1);
    assert!(tags::list_all(&conn).unwrap().iter().any(|t| t.id == "t2"));
}

#[test]
fn apply_snippets_lands_command_and_description() {
    let conn = fresh_db();
    let pending = PendingImport {
            snippets_json: Some(
                r#"[{"id":"sn1","title":"list","command":"ls -la","description":"long","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
    apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000).unwrap();
    let all = snippets::list_all(&conn).unwrap();
    assert_eq!(all.len(), 1);
    assert_eq!(all[0].command, "ls -la");
    assert_eq!(all[0].description, "long");
}

#[test]
fn apply_snippets_skips_row_with_blank_title_or_id() {
    let conn = fresh_db();
    let pending = PendingImport {
            snippets_json: Some(
                r#"[
                    {"id":"","title":"x","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"sn1","title":"","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"sn2","title":"good","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}
                ]"#
                .to_string(),
            ),
            ..empty_pending()
        };
    let result =
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
    assert_eq!(result.snippets_applied, 1);
}

// ── v3 child-table round-trips (archive + sync) ────────────

/// Seed a session row so child-table FK parents exist before
/// the round-trip test calls the unified apply driver. Kept
/// inside the test module so the per-table tests below don't
/// reach into the prod `db::sessions` constructors directly.
fn seed_session_id(conn: &Connection, id: &str) {
    sessions::upsert(
        conn,
        &sessions::SessionRow {
            id: id.into(),
            label: id.into(),
            host: "h".into(),
            port: 22,
            user: "u".into(),
            auth_type: "password".into(),
            ..Default::default()
        },
    )
    .unwrap();
}

fn seed_key_id(conn: &Connection, id: &str) {
    ssh_keys::upsert(
        conn,
        &ssh_keys::SshKeyRow {
            id: id.into(),
            label: id.into(),
            private_key: "PRIV".into(),
            public_key: "ssh-ed25519 AAAA".into(),
            key_type: "ssh-ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
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
fn apply_ssh_key_certificates_round_trip_under_archive_import_mode() {
    let mut conn = fresh_db();
    seed_key_id(&conn, "k1");
    let pending = PendingImport {
        ssh_key_certificates_json: Some(
            r#"[{
                    "key_id":"k1",
                    "certificate":[1,2,3,4],
                    "valid_after":1700000000,
                    "valid_before":1700086400,
                    "principals":"[\"alice\"]",
                    "critical_options":"{}",
                    "fingerprint":"SHA256:abc"
                }]"#
            .to_string(),
        ),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.ssh_key_certificates_applied, 1);
    let row = crate::db::ssh_key_certificates::get(&conn, "k1")
        .unwrap()
        .expect("cert landed");
    assert_eq!(row.certificate, vec![1, 2, 3, 4]);
    assert_eq!(row.valid_after, 1_700_000_000);
    assert_eq!(row.fingerprint, "SHA256:abc");
}

#[test]
fn apply_ssh_key_certificates_drops_with_warning_when_parent_absent() {
    // Sync mode through unified entry — parent key NOT seeded so
    // the cert lands on the warning channel, not the error
    // channel (per the plan: a partial pull doesn't roll back).
    let mut conn = fresh_db();
    let pending = PendingImport {
            ssh_key_certificates_json: Some(
                r#"[{"key_id":"orphan","certificate":[0],"valid_after":0,"valid_before":0,"principals":"[]","critical_options":"{}","fingerprint":"x"}]"#.into(),
            ),
            ..empty_pending()
        };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::Sync,
        &ApplyOptions::default(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.ssh_key_certificates_applied, 0);
    assert!(outcome.errors.is_empty());
    assert!(
        outcome
            .warnings
            .iter()
            .any(|w| w.contains("orphan") && w.contains("parent key absent")),
        "warnings: {:?}",
        outcome.warnings,
    );
}

#[test]
fn apply_webdav_session_details_round_trip() {
    let mut conn = fresh_db();
    seed_session_id(&conn, "s1");
    let pending = PendingImport {
            webdav_session_details_json: Some(
                r#"[{"session_id":"s1","base_url":"https://example.com/dav/","username":"alice","auth_method":"basic","credential_secret_id":"session.webdav.s1"}]"#.into(),
            ),
            ..empty_pending()
        };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.webdav_session_details_applied, 1);
    let row = crate::db::webdav_sessions::get(&conn, "s1")
        .unwrap()
        .expect("webdav detail row landed");
    assert_eq!(row.base_url, "https://example.com/dav/");
    assert_eq!(row.auth_method, "basic");
}

#[test]
fn apply_s3_session_details_round_trip() {
    let mut conn = fresh_db();
    seed_session_id(&conn, "s1");
    let pending = PendingImport {
        s3_session_details_json: Some(
            r#"[{
                    "session_id":"s1",
                    "access_key_id":"AKIAEXAMPLE",
                    "region":"us-east-1",
                    "endpoint":"https://s3.example.com",
                    "path_style":true,
                    "default_bucket":"my-bucket",
                    "default_prefix":"logs/",
                    "secret_access_key_secret_id":"session.s3.s1"
                }]"#
            .into(),
        ),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.s3_session_details_applied, 1);
    let row = crate::db::s3_sessions::get(&conn, "s1")
        .unwrap()
        .expect("s3 detail row landed");
    assert_eq!(row.access_key_id, "AKIAEXAMPLE");
    assert!(row.path_style);
    assert_eq!(row.region, "us-east-1");
}

#[test]
fn apply_sftp_bookmarks_round_trip() {
    let mut conn = fresh_db();
    seed_session_id(&conn, "s1");
    let pending = PendingImport {
        sftp_bookmarks_json: Some(
            r#"[{
                    "id":"bm1",
                    "session_id":"s1",
                    "remote_path":"/var/log",
                    "label":"logs",
                    "created_at":"2026-04-26T00:00:00.000Z"
                }]"#
            .into(),
        ),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.sftp_bookmarks_applied, 1);
    let rows = crate::db::sftp_bookmarks::list_for_session(&conn, "s1").unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].remote_path, "/var/log");
}

#[test]
fn apply_port_forward_rules_round_trip() {
    let mut conn = fresh_db();
    seed_session_id(&conn, "s1");
    let pending = PendingImport {
        port_forward_rules_json: Some(
            r#"[{
                    "id":"pf1",
                    "session_id":"s1",
                    "kind":"local",
                    "bind_host":"127.0.0.1",
                    "bind_port":8080,
                    "remote_host":"app.example.com",
                    "remote_port":80,
                    "description":"webdev",
                    "enabled":true,
                    "sort_order":0,
                    "created_at_ms":1700000000000
                }]"#
            .into(),
        ),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert_eq!(outcome.port_forward_rules_applied, 1);
    let rows = crate::db::port_forwards::list_for_session(&conn, "s1").unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].bind_port, 8080);
    assert_eq!(rows[0].remote_host, "app.example.com");
}

// ── SSH key round-trip per backend ─────────────────────────

fn round_trip_key_through_apply(backend: &str, extra_fields: &str) -> ssh_keys::SshKeyRow {
    let mut conn = fresh_db();
    let json = format!(
        r#"[{{
                "id":"k1",
                "label":"my-key",
                "public_key":"ssh-ed25519 AAAA...",
                "key_type":"ssh-ed25519",
                "is_generated":false,
                "created_at":"2026-04-26T00:00:00.000Z",
                "backend":"{backend}"
                {extra_fields}
            }}]"#
    );
    let pending = PendingImport {
        keys_json: Some(json),
        ..empty_pending()
    };
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        &mut conn,
        &pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        &merge_all_options(),
        1_700_000_000_000,
        &mut outcome,
    )
    .unwrap();
    assert!(outcome.errors.is_empty(), "errors: {:?}", outcome.errors);
    ssh_keys::get(&conn, "k1").unwrap().expect("key row landed")
}

#[test]
fn apply_ssh_key_software_round_trips_private_key() {
    let row = round_trip_key_through_apply("software", r#", "private_key":"PRIVATE-BYTES""#);
    assert_eq!(row.backend, ssh_keys::KeyBackend::Software);
    assert_eq!(row.private_key, "PRIVATE-BYTES");
    assert!(!row.imported_as_stub);
}

#[test]
fn apply_ssh_key_fido2_round_trips_credential_id_and_application() {
    let row = round_trip_key_through_apply(
        "fido2",
        r#", "credential_id":[1,2,3,4], "application_string":"ssh:", "has_user_verification":true"#,
    );
    assert_eq!(row.backend, ssh_keys::KeyBackend::Fido2);
    assert_eq!(row.credential_id, Some(vec![1, 2, 3, 4]));
    assert_eq!(row.application_string.as_deref(), Some("ssh:"));
    assert!(row.has_user_verification);
    assert!(!row.imported_as_stub);
    assert!(
        row.private_key.is_empty(),
        "FIDO2 rows carry no private PEM"
    );
}

#[test]
fn apply_ssh_key_pkcs11_round_trips_uri_and_object_ingredients_but_never_module_path() {
    let row = round_trip_key_through_apply(
        "pkcs11",
        r#", "pkcs11_uri":"pkcs11:token=YubiKey", "pkcs11_token_serial":"01ABCDEF", "pkcs11_object_id":[10,20], "pkcs11_object_label":"my-piv-cert""#,
    );
    assert_eq!(row.backend, ssh_keys::KeyBackend::Pkcs11);
    assert_eq!(row.pkcs11_uri.as_deref(), Some("pkcs11:token=YubiKey"),);
    assert_eq!(row.pkcs11_token_serial.as_deref(), Some("01ABCDEF"));
    assert_eq!(row.pkcs11_object_id, Some(vec![10, 20]));
    assert_eq!(row.pkcs11_object_label.as_deref(), Some("my-piv-cert"));
    // Module path is the per-host install location and is
    // resolved locally on first use — never travels through
    // the archive.
    assert!(row.pkcs11_module_path.is_none());
    assert!(!row.imported_as_stub);
}

#[test]
fn apply_ssh_key_enclave_lands_as_stub_with_public_half_only() {
    let row = round_trip_key_through_apply("enclave", "");
    assert_eq!(row.backend, ssh_keys::KeyBackend::Enclave);
    assert!(row.imported_as_stub, "Apple SE row must land as stub");
    assert!(row.private_key.is_empty());
    assert!(row.enclave_tag.is_none());
}

#[test]
fn apply_ssh_key_hello_lands_as_stub_with_public_half_only() {
    let row = round_trip_key_through_apply("hello", "");
    assert_eq!(row.backend, ssh_keys::KeyBackend::Hello);
    assert!(row.imported_as_stub);
    assert!(row.hello_credential_name.is_none());
}

#[test]
fn apply_ssh_key_tpm_lands_as_stub_with_public_half_only() {
    let row = round_trip_key_through_apply("tpm", "");
    assert_eq!(row.backend, ssh_keys::KeyBackend::Tpm);
    assert!(row.imported_as_stub);
    assert!(row.tpm_blob.is_none());
    assert!(row.tpm_handle.is_none());
}

#[test]
fn apply_ssh_key_keystore_lands_as_stub_with_public_half_only() {
    let row = round_trip_key_through_apply("keystore", "");
    assert_eq!(row.backend, ssh_keys::KeyBackend::Keystore);
    assert!(row.imported_as_stub);
    assert!(row.keystore_alias.is_none());
}

// ── cross-mode unified-entry parity ────────────────────────

/// Exercise the same Pending fixture through both
/// ArchiveImport and Sync modes; assert the per-mode DB state
/// matches the documented shape. Archive-import always upserts;
/// Sync gates on LWW. The fixture lands one fresh row that has
/// no local equivalent — both modes must apply it.
#[test]
fn apply_pending_to_db_round_trip_through_both_modes() {
    let session_json = r#"[{
            "id":"s1",
            "label":"prod",
            "host":"h.example.com",
            "port":22,
            "user":"deploy",
            "auth_type":"password",
            "password":"",
            "key_path":"",
            "key_data":"",
            "passphrase":"",
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
    for mode in &[
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        ApplyMode::Sync,
    ] {
        let mut conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(session_json.into()),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            *mode,
            &ApplyOptions {
                apply_sessions: true,
                ..ApplyOptions::default()
            },
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap_or_else(|e| panic!("{mode:?} apply: {e:?}"));
        assert_eq!(outcome.sessions_applied, 1, "{mode:?}");
        let row = sessions::get(&conn, "s1").unwrap().expect("row");
        assert_eq!(row.label, "prod", "{mode:?}");
    }
}
