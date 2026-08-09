/// Unit tests extracted from sessions.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn make(id: &str, label: &str, folder: &str, host: &str, user: &str) -> SearchableSession {
    SearchableSession {
        id: id.to_string(),
        label: label.to_string(),
        folder: folder.to_string(),
        host: host.to_string(),
        user: user.to_string(),
    }
}

#[test]
fn auth_type_wire_round_trip_every_variant() {
    for v in [
        AuthType::Password,
        AuthType::Key,
        AuthType::KeyWithPassword,
        AuthType::Agent,
    ] {
        assert_eq!(AuthType::from_wire_name(v.wire_name()), v);
    }
}

#[test]
fn auth_type_unknown_wire_falls_back_to_password() {
    assert_eq!(AuthType::from_wire_name(""), AuthType::Password);
    assert_eq!(
        AuthType::from_wire_name("does-not-exist"),
        AuthType::Password
    );
}

#[test]
fn auth_type_wire_names_match_dart_enum_dot_name() {
    // Byte-identity guard — these strings round-trip the DB
    // column and the canonical-JSON payload, so a typo would
    // brick every saved row.
    assert_eq!(AuthType::Password.wire_name(), "password");
    assert_eq!(AuthType::Key.wire_name(), "key");
    assert_eq!(AuthType::KeyWithPassword.wire_name(), "keyWithPassword");
    assert_eq!(AuthType::Agent.wire_name(), "agent");
}

#[test]
fn session_kind_wire_round_trip_every_variant() {
    for v in [SessionKind::Ssh, SessionKind::Webdav, SessionKind::S3] {
        assert_eq!(SessionKind::from_wire_name(Some(v.wire_name())), v);
    }
}

#[test]
fn session_kind_unknown_wire_falls_back_to_ssh() {
    assert_eq!(SessionKind::from_wire_name(None), SessionKind::Ssh);
    assert_eq!(SessionKind::from_wire_name(Some("")), SessionKind::Ssh);
    assert_eq!(
        SessionKind::from_wire_name(Some("future-tag")),
        SessionKind::Ssh
    );
}

#[test]
fn session_kind_wire_names_match_db_constants() {
    assert_eq!(
        SessionKind::Ssh.wire_name(),
        crate::db::sessions::SESSION_KIND_SSH
    );
    assert_eq!(
        SessionKind::Webdav.wire_name(),
        crate::db::sessions::SESSION_KIND_WEBDAV
    );
    assert_eq!(
        SessionKind::S3.wire_name(),
        crate::db::sessions::SESSION_KIND_S3
    );
}

#[test]
fn empty_query_returns_every_id_in_order() {
    let items = vec![
        make("a", "Frontend", "Production", "1.2.3.4", "root"),
        make("b", "Backend", "Production", "5.6.7.8", "deploy"),
    ];
    assert_eq!(filter_sessions(&items, ""), vec!["a", "b"]);
}

#[test]
fn matches_label_case_insensitively() {
    let items = vec![
        make("a", "Frontend Web", "Production/EU", "x", "u"),
        make("b", "API Backend", "Production/US", "x", "u"),
    ];
    assert_eq!(filter_sessions(&items, "frontend"), vec!["a"]);
    assert_eq!(filter_sessions(&items, "FRONTEND"), vec!["a"]);
}

#[test]
fn matches_folder() {
    let items = vec![
        make("a", "x", "Production/EU", "x", "u"),
        make("b", "x", "Production/US", "x", "u"),
    ];
    assert_eq!(filter_sessions(&items, "us"), vec!["b"]);
}

#[test]
fn matches_host() {
    let items = vec![
        make("a", "x", "y", "alpha.example.com", "u"),
        make("b", "x", "y", "beta.example.com", "u"),
    ];
    assert_eq!(filter_sessions(&items, "alpha"), vec!["a"]);
}

#[test]
fn matches_user() {
    let items = vec![
        make("a", "x", "y", "h", "deploy"),
        make("b", "x", "y", "h", "root"),
    ];
    assert_eq!(filter_sessions(&items, "deploy"), vec!["a"]);
}

#[test]
fn returns_all_matches_in_input_order() {
    let items = vec![
        make("a", "alpha", "y", "h", "u"),
        make("b", "beta", "y", "h", "u"),
        make("c", "alpha-2", "y", "h", "u"),
    ];
    assert_eq!(filter_sessions(&items, "alpha"), vec!["a", "c"]);
}

#[test]
fn returns_empty_when_no_match() {
    let items = vec![make("a", "foo", "bar", "baz", "qux")];
    assert!(filter_sessions(&items, "missing").is_empty());
}

#[test]
fn validate_accepts_well_formed_session() {
    assert!(validate_session_fields("example.com", 22, "root").is_none());
}

#[test]
fn validate_rejects_blank_host() {
    assert_eq!(
        validate_session_fields("   ", 22, "root").as_deref(),
        Some("Host is required")
    );
}

#[test]
fn validate_rejects_blank_user() {
    assert_eq!(
        validate_session_fields("h", 22, "  ").as_deref(),
        Some("Username is required")
    );
}

#[test]
fn validate_rejects_zero_port() {
    assert_eq!(
        validate_session_fields("h", 0, "u").as_deref(),
        Some("Port must be 1-65535")
    );
}

#[test]
fn validate_accepts_port_at_max_boundary() {
    assert!(validate_session_fields("h", 65535, "u").is_none());
}

#[test]
fn validate_rejects_negative_port() {
    // Out-of-range negatives surface the same message a zero
    // port does — the grammar tolerates the full `i32` range
    // and the user sees one consistent verdict regardless of
    // how the misuse got there.
    assert_eq!(
        validate_session_fields("h", -1, "u").as_deref(),
        Some("Port must be 1-65535")
    );
}

#[test]
fn validate_rejects_port_above_max() {
    assert_eq!(
        validate_session_fields("h", 70_000, "u").as_deref(),
        Some("Port must be 1-65535")
    );
}

#[test]
fn count_in_folder_matches_exact() {
    let folders = vec![
        "Production".to_string(),
        "Production".to_string(),
        "Staging".to_string(),
    ];
    assert_eq!(count_in_folder(&folders, "Production"), 2);
}

#[test]
fn count_in_folder_includes_children_under_prefix() {
    let folders = vec![
        "Production".to_string(),
        "Production/EU".to_string(),
        "Production/US".to_string(),
        "Staging".to_string(),
    ];
    assert_eq!(count_in_folder(&folders, "Production"), 3);
}

#[test]
fn count_in_folder_skips_partial_prefix_matches() {
    // "ProductionExtra" must not count when we ask about
    // "Production" — the slash boundary matters.
    let folders = vec!["Production".to_string(), "ProductionExtra".to_string()];
    assert_eq!(count_in_folder(&folders, "Production"), 1);
}

#[test]
fn count_in_folder_root_path_counts_root_sessions() {
    let folders = vec![String::new(), "Production".to_string(), String::new()];
    assert_eq!(count_in_folder(&folders, ""), 2);
}

#[test]
fn unique_label_passes_through_when_base_is_free() {
    let taken: std::collections::HashSet<String> = ["foo".into()].into();
    assert_eq!(unique_label("bar", &taken), "bar");
}

#[test]
fn unique_label_appends_copy_marker_when_base_taken() {
    let taken: std::collections::HashSet<String> = ["foo".into()].into();
    assert_eq!(unique_label("foo", &taken), "foo (copy)");
}

#[test]
fn unique_label_appends_copy_n_when_copy_taken() {
    let taken: std::collections::HashSet<String> = ["foo".into(), "foo (copy)".into()].into();
    assert_eq!(unique_label("foo", &taken), "foo (copy 2)");
}

#[test]
fn unique_label_walks_until_free_slot_found() {
    let taken: std::collections::HashSet<String> = [
        "foo".into(),
        "foo (copy)".into(),
        "foo (copy 2)".into(),
        "foo (copy 3)".into(),
    ]
    .into();
    assert_eq!(unique_label("foo", &taken), "foo (copy 4)");
}

#[test]
fn unique_label_keeps_empty_base_empty() {
    // The duplicate-key import path passes through entries with
    // no label; `unique_label("", _)` must not produce
    // " (copy)" — empty in, empty out.
    let taken: std::collections::HashSet<String> = ["foo".into()].into();
    assert_eq!(unique_label("", &taken), "");
}

#[test]
fn distinct_folders_drops_empty_dedups_and_sorts() {
    let folders = vec![
        "Production".to_string(),
        String::new(),
        "Staging".to_string(),
        "Production".to_string(),
        String::new(),
        "Production/EU".to_string(),
    ];
    assert_eq!(
        distinct_folders(&folders),
        vec![
            "Production".to_string(),
            "Production/EU".to_string(),
            "Staging".to_string(),
        ]
    );
}

#[test]
fn distinct_folders_returns_empty_when_every_session_is_at_root() {
    let folders = vec![String::new(), String::new()];
    assert!(distinct_folders(&folders).is_empty());
}

fn build_in_memory_db() -> Db {
    use crate::db::{bootstrap_schema, Connection};
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    Db::from_raw_for_tests(conn)
}

#[test]
fn registry_starts_with_empty_view() {
    let r = Registry::new();
    let view = r.snapshot();
    assert!(view.sessions.is_empty());
    assert!(view.folders.is_empty());
    assert!(view.empty_folders.is_empty());
    assert!(view.collapsed_folders.is_empty());
    assert_eq!(r.session_count(), 0);
}

#[test]
fn registry_reload_hydrates_session_and_folder_view() {
    let db = build_in_memory_db();
    // Folder + child session.
    db.with_conn(|c| {
        crate::db::folders::upsert(
            c,
            &FolderRow {
                id: "f1".into(),
                name: "Production".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 0,
            },
        )?;
        crate::db::folders::upsert(
            c,
            &FolderRow {
                id: "f2".into(),
                name: "EU".into(),
                parent_id: Some("f1".into()),
                sort_order: 0,
                collapsed: true,
                created_at_ms: 0,
            },
        )?;
        crate::db::sessions::upsert(
            c,
            &SessionRow {
                id: "s1".into(),
                label: "web".into(),
                folder_id: Some("f1".into()),
                kind: crate::db::sessions::SESSION_KIND_SSH.into(),
                host: "h".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                password: String::new(),
                key_path: String::new(),
                key_data: String::new(),
                key_id: None,
                passphrase: String::new(),
                sort_order: 0,
                notes: String::new(),
                last_connected_at_ms: None,
                extras: "{}".into(),
                via_session_id: None,
                via_host: None,
                via_port: None,
                via_user: None,
                created_at_ms: 0,
                updated_at_ms: 0,
            },
        )?;
        Ok::<_, Error>(())
    })
    .unwrap();

    let r = Registry::new();
    r.reload(&db).unwrap();
    let view = r.snapshot();

    assert_eq!(view.sessions.len(), 1);
    assert_eq!(view.sessions[0].id, "s1");
    assert_eq!(view.folders.len(), 2);
    // f1 has a session — should not appear in empty_folders.
    // f2 has no session — should appear as "Production/EU".
    assert!(!view.empty_folders.contains("Production"));
    assert!(view.empty_folders.contains("Production/EU"));
    // f2 is collapsed.
    assert!(view.collapsed_folders.contains("Production/EU"));
}

#[test]
fn registry_reload_preserves_view_on_subsequent_calls() {
    let db = build_in_memory_db();
    let r = Registry::new();
    // Empty DB → empty view; reload a couple times to confirm
    // idempotence on the empty case.
    r.reload(&db).unwrap();
    r.reload(&db).unwrap();
    assert_eq!(r.session_count(), 0);
}

#[test]
fn registry_filter_ids_uses_four_field_predicate_against_cache() {
    let db = build_in_memory_db();
    db.with_conn(|c| {
        crate::db::folders::upsert(
            c,
            &FolderRow {
                id: "f1".into(),
                name: "Production".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 0,
            },
        )?;
        for (id, label, folder, host, user) in [
            ("a", "Frontend", Some("f1"), "alpha.example.com", "root"),
            ("b", "Backend", None, "beta.example.com", "deploy"),
        ] {
            crate::db::sessions::upsert(
                c,
                &SessionRow {
                    id: id.into(),
                    label: label.into(),
                    folder_id: folder.map(String::from),
                    kind: crate::db::sessions::SESSION_KIND_SSH.into(),
                    host: host.into(),
                    port: 22,
                    user: user.into(),
                    auth_type: "password".into(),
                    password: String::new(),
                    key_path: String::new(),
                    key_data: String::new(),
                    key_id: None,
                    passphrase: String::new(),
                    sort_order: 0,
                    notes: String::new(),
                    last_connected_at_ms: None,
                    extras: "{}".into(),
                    via_session_id: None,
                    via_host: None,
                    via_port: None,
                    via_user: None,
                    created_at_ms: 0,
                    updated_at_ms: 0,
                },
            )?;
        }
        Ok::<_, Error>(())
    })
    .unwrap();

    let r = Registry::new();
    r.reload(&db).unwrap();

    // Match by label.
    assert_eq!(r.filter_ids("frontend"), vec!["a"]);
    // Match by folder (only `a` is under Production).
    assert_eq!(r.filter_ids("production"), vec!["a"]);
    // Match by host substring.
    assert_eq!(r.filter_ids("beta"), vec!["b"]);
    // Match by user.
    assert_eq!(r.filter_ids("deploy"), vec!["b"]);
    // Empty query returns every id.
    let all = r.filter_ids("");
    assert!(all.contains(&"a".to_string()) && all.contains(&"b".to_string()));
}

#[test]
fn registry_count_in_folder_walks_cached_view() {
    let db = build_in_memory_db();
    db.with_conn(|c| {
        crate::db::folders::upsert(
            c,
            &FolderRow {
                id: "f_prod".into(),
                name: "Production".into(),
                parent_id: None,
                sort_order: 0,
                collapsed: false,
                created_at_ms: 0,
            },
        )?;
        crate::db::folders::upsert(
            c,
            &FolderRow {
                id: "f_eu".into(),
                name: "EU".into(),
                parent_id: Some("f_prod".into()),
                sort_order: 0,
                collapsed: false,
                created_at_ms: 0,
            },
        )?;
        for (id, folder) in [
            ("s_root", None),
            ("s_prod", Some("f_prod")),
            ("s_eu", Some("f_eu")),
        ] {
            crate::db::sessions::upsert(
                c,
                &SessionRow {
                    id: id.into(),
                    label: id.into(),
                    folder_id: folder.map(String::from),
                    kind: crate::db::sessions::SESSION_KIND_SSH.into(),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    password: String::new(),
                    key_path: String::new(),
                    key_data: String::new(),
                    key_id: None,
                    passphrase: String::new(),
                    sort_order: 0,
                    notes: String::new(),
                    last_connected_at_ms: None,
                    extras: "{}".into(),
                    via_session_id: None,
                    via_host: None,
                    via_port: None,
                    via_user: None,
                    created_at_ms: 0,
                    updated_at_ms: 0,
                },
            )?;
        }
        Ok::<_, Error>(())
    })
    .unwrap();

    let r = Registry::new();
    r.reload(&db).unwrap();
    // Production includes its child + the EU child = 2 entries.
    assert_eq!(r.count_in_folder("Production"), 2);
    // Empty path → root-level only.
    assert_eq!(r.count_in_folder(""), 1);
    // Unknown path → 0.
    assert_eq!(r.count_in_folder("Staging"), 0);
}

#[test]
fn parse_ssh_target_bare_host_returns_host_only() {
    let t = parse_ssh_target("example.com").expect("bare host parses");
    assert_eq!(t.host, "example.com");
    assert_eq!(t.user, None);
    assert_eq!(t.port, None);
}

#[test]
fn parse_ssh_target_user_at_host() {
    let t = parse_ssh_target("root@example.com").expect("user@host parses");
    assert_eq!(t.host, "example.com");
    assert_eq!(t.user.as_deref(), Some("root"));
    assert_eq!(t.port, None);
}

#[test]
fn parse_ssh_target_host_colon_port() {
    let t = parse_ssh_target("example.com:2222").expect("host:port parses");
    assert_eq!(t.host, "example.com");
    assert_eq!(t.user, None);
    assert_eq!(t.port, Some(2222));
}

#[test]
fn parse_ssh_target_full_form() {
    let t = parse_ssh_target("alice@example.com:2222").expect("full form parses");
    assert_eq!(t.host, "example.com");
    assert_eq!(t.user.as_deref(), Some("alice"));
    assert_eq!(t.port, Some(2222));
}

#[test]
fn parse_ssh_target_ipv6_bracketed_no_port() {
    let t = parse_ssh_target("[::1]").expect("bracketed IPv6 parses");
    assert_eq!(t.host, "::1");
    assert_eq!(t.port, None);
}

#[test]
fn parse_ssh_target_ipv6_bracketed_with_port() {
    let t = parse_ssh_target("root@[2001:db8::1]:22").expect("user + IPv6 + port");
    assert_eq!(t.host, "2001:db8::1");
    assert_eq!(t.user.as_deref(), Some("root"));
    assert_eq!(t.port, Some(22));
}

#[test]
fn parse_ssh_target_trims_surrounding_whitespace() {
    let t = parse_ssh_target("  root@example.com:22  ").expect("trimmed input parses");
    assert_eq!(t.host, "example.com");
    assert_eq!(t.user.as_deref(), Some("root"));
    assert_eq!(t.port, Some(22));
}

#[test]
fn parse_ssh_target_rejects_empty() {
    assert!(parse_ssh_target("").is_none());
    assert!(parse_ssh_target("   ").is_none());
}

#[test]
fn parse_ssh_target_rejects_zero_and_overflow_port() {
    assert!(parse_ssh_target("h:0").is_none());
    assert!(parse_ssh_target("h:65536").is_none());
    assert!(parse_ssh_target("h:99999999").is_none());
}

#[test]
fn parse_ssh_target_rejects_non_numeric_port() {
    assert!(parse_ssh_target("h:abc").is_none());
}

#[test]
fn parse_ssh_target_rejects_control_chars_in_host() {
    assert!(parse_ssh_target("evil\rhost").is_none());
    assert!(parse_ssh_target("evil\nhost").is_none());
    assert!(parse_ssh_target("evil\0host").is_none());
}

#[test]
fn parse_ssh_target_rejects_path_separators_in_host() {
    assert!(parse_ssh_target("a/b").is_none());
    assert!(parse_ssh_target("a\\b").is_none());
}

#[test]
fn parse_ssh_target_rejects_empty_user_part() {
    assert!(parse_ssh_target("@host").is_none());
}

#[test]
fn parse_ssh_target_rejects_oversize_host() {
    let host = "a".repeat(254);
    assert!(parse_ssh_target(&host).is_none());
}

#[test]
fn parse_ssh_target_rejects_oversize_user() {
    let user = "u".repeat(257);
    let input = format!("{}@host", user);
    assert!(parse_ssh_target(&input).is_none());
}

fn pr(id: &str, via: Option<&str>) -> ProxyRef {
    ProxyRef {
        session_id: id.to_string(),
        via_session_id: via.map(str::to_string),
    }
}

#[test]
fn detect_proxy_cycle_new_session_never_loops() {
    // No seed id (new-session branch) — every candidate is safe.
    let chain = vec![pr("a", None), pr("b", Some("a"))];
    assert!(!detect_proxy_cycle(None, "a", &chain));
    assert!(!detect_proxy_cycle(None, "b", &chain));
}

#[test]
fn detect_proxy_cycle_direct_self_trips() {
    let chain = vec![pr("a", None)];
    assert!(detect_proxy_cycle(Some("a"), "a", &chain));
}

#[test]
fn detect_proxy_cycle_two_step_cycle_trips() {
    // Editing A; A wants to go via B; B already goes via A.
    let chain = vec![pr("a", None), pr("b", Some("a"))];
    assert!(detect_proxy_cycle(Some("a"), "b", &chain));
}

#[test]
fn detect_proxy_cycle_three_step_cycle_trips() {
    // A → B → C → A: picking C while editing A trips the probe
    // because the chain walks C → A which is the seed.
    let chain = vec![pr("a", None), pr("b", Some("a")), pr("c", Some("b"))];
    assert!(detect_proxy_cycle(Some("a"), "c", &chain));
}

#[test]
fn detect_proxy_cycle_safe_chain_does_not_trip() {
    // A → B → C, picking C while editing A is fine — chain
    // walks C, then None (C has no via).
    let chain = vec![pr("a", Some("b")), pr("b", Some("c")), pr("c", None)];
    assert!(!detect_proxy_cycle(Some("a"), "c", &chain));
}

#[test]
fn detect_proxy_cycle_orphan_loop_does_not_trip_for_unrelated_seed() {
    // Pre-existing loop B → C → B in the data; editing A wants
    // to go via B. The probe is asking "would THIS edit close a
    // loop through me" — orphan loops elsewhere stay the connect
    // path's problem, not the dialog's.
    let chain = vec![pr("a", None), pr("b", Some("c")), pr("c", Some("b"))];
    assert!(!detect_proxy_cycle(Some("a"), "b", &chain));
}

#[test]
fn detect_proxy_cycle_missing_via_target_is_safe() {
    // Candidate's via points at a deleted session — the chain
    // terminates with None lookup. Not a cycle.
    let chain = vec![pr("b", Some("ghost"))];
    assert!(!detect_proxy_cycle(Some("a"), "b", &chain));
}
