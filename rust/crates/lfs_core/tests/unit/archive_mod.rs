/// Unit tests extracted from archive/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::io::Write;

use zip::write::SimpleFileOptions;

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
        ssh_key_certificates_json: None,
        webdav_session_details_json: None,
        s3_session_details_json: None,
        sftp_bookmarks_json: None,
        port_forward_rules_json: None,
        recordings: Vec::new(),
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
    let pending =
        pending_with_sessions(r#"[{"label":"prod","host":"a"},{"label":"staging","host":"b"}]"#);
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

#[test]
fn read_archive_to_pending_rejects_future_version() {
    // Future-version manifest stamped by a hypothetical newer
    // build. Current build supports SchemaVersions::ARCHIVE = 1
    // and must refuse rather than silently apply whatever subset
    // of fields it understands.
    let zip = build_test_zip(&[
        ("manifest.json", r#"{"schema_version":99}"#),
        ("sessions.json", "[]"),
    ]);
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("future.lfs");
    std::fs::write(&path, &zip).unwrap();
    let err = read_archive_to_pending(path.to_str().unwrap(), "")
        .expect_err("future-version archive must error");
    match err {
        Error::ArchiveFutureVersion { found, supported } => {
            assert_eq!(found, 99);
            assert_eq!(supported, crate::migration::SchemaVersions::ARCHIVE);
        }
        other => panic!("expected ArchiveFutureVersion, got {other:?}"),
    }
}

#[test]
fn read_archive_to_pending_accepts_current_version() {
    let zip = build_test_zip(&[
        (
            "manifest.json",
            &format!(
                "{{\"schema_version\":{}}}",
                crate::migration::SchemaVersions::ARCHIVE
            ),
        ),
        ("sessions.json", "[]"),
    ]);
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("current.lfs");
    std::fs::write(&path, &zip).unwrap();
    let (_pending, preview) =
        read_archive_to_pending(path.to_str().unwrap(), "").expect("current version");
    assert_eq!(
        preview.schema_version,
        i64::from(crate::migration::SchemaVersions::ARCHIVE),
    );
}

#[test]
fn read_archive_to_pending_accepts_legacy_v1_manifest() {
    // v1 archives written before the sync_origin field existed
    // must still import — `1..=ARCHIVE` is the supported range
    // and the v3 manifest is a superset of the v1 wire shape.
    let zip = build_test_zip(&[
        ("manifest.json", r#"{"schema_version":1}"#),
        ("sessions.json", "[]"),
    ]);
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("v1.lfs");
    std::fs::write(&path, &zip).unwrap();
    let (_pending, preview) =
        read_archive_to_pending(path.to_str().unwrap(), "").expect("legacy v1");
    assert_eq!(preview.schema_version, 1);
}

/// v1 archive carrying every typed slot the reader knows about —
/// manifest, sessions, child tables, `sync_origin`. Pins that
/// the slim `read_archive_to_pending` accepts the current shape
/// end-to-end without surfacing unknown-entry warnings. The
/// forward-version gate is covered by the
/// `rejects_future_version` test above.
#[test]
fn read_archive_to_pending_v1_with_all_typed_slots_parses() {
    let zip = build_test_zip(&[
        (
            "manifest.json",
            r#"{"schema_version":1,"sync_origin":"install-x:42"}"#,
        ),
        ("sessions.json", "[]"),
        ("ssh_key_certificates.json", "[]"),
        ("webdav_session_details.json", "[]"),
        ("s3_session_details.json", "[]"),
        ("sftp_bookmarks.json", "[]"),
        ("port_forward_rules.json", "[]"),
    ]);
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("v1-full.lfs");
    std::fs::write(&path, &zip).unwrap();
    let (pending, preview) = read_archive_to_pending(path.to_str().unwrap(), "").expect("v1 parse");
    assert_eq!(preview.schema_version, 1);
    assert!(pending.ssh_key_certificates_json.is_some());
    assert!(pending.webdav_session_details_json.is_some());
    assert!(pending.s3_session_details_json.is_some());
    assert!(pending.sftp_bookmarks_json.is_some());
    assert!(pending.port_forward_rules_json.is_some());
}

#[test]
fn parse_sync_origin_extracts_field_from_manifest() {
    let pending = PendingImport {
        manifest_json: Some(r#"{"schema_version":2,"sync_origin":"inst-1:42"}"#.into()),
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
    };
    assert_eq!(parse_sync_origin(&pending).as_deref(), Some("inst-1:42"));
}

#[test]
fn parse_sync_origin_returns_none_when_field_absent_or_empty() {
    let mut pending = PendingImport {
        manifest_json: Some(r#"{"schema_version":2}"#.into()),
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
    };
    assert!(parse_sync_origin(&pending).is_none());
    pending.manifest_json = Some(r#"{"schema_version":2,"sync_origin":""}"#.into());
    assert!(parse_sync_origin(&pending).is_none());
    pending.manifest_json = None;
    assert!(parse_sync_origin(&pending).is_none());
}

#[test]
fn resolve_relevant_empty_folders_empty_selection_returns_empty() {
    let out = resolve_relevant_empty_folders(&[], &[], false);
    assert!(out.is_empty());
}

#[test]
fn resolve_relevant_empty_folders_pulls_in_ancestors_of_selected_folders() {
    let selected = vec!["a/b/c".to_string()];
    let source: Vec<String> = vec![];
    let out = resolve_relevant_empty_folders(&selected, &source, false);
    assert_eq!(out, vec!["a".to_string(), "a/b".to_string()]);
}

#[test]
fn resolve_relevant_empty_folders_includes_descendants_skips_unrelated() {
    let selected = vec!["a".to_string()];
    let source = vec!["a/x".to_string(), "b".to_string(), "root".to_string()];
    let out = resolve_relevant_empty_folders(&selected, &source, false);
    assert!(out.contains(&"a/x".to_string()));
    assert!(!out.contains(&"b".to_string()));
    assert!(!out.contains(&"root".to_string()));
}

#[test]
fn resolve_relevant_empty_folders_all_selected_includes_every_source_folder() {
    let selected = vec!["prod/web".to_string()];
    let source = vec!["prod".to_string(), "stg".to_string(), "archive".to_string()];
    let out = resolve_relevant_empty_folders(&selected, &source, true);
    assert!(out.contains(&"prod".to_string()));
    assert!(out.contains(&"stg".to_string()));
    assert!(out.contains(&"archive".to_string()));
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
