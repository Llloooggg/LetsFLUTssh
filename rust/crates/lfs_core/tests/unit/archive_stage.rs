/// Unit tests extracted from archive_stage.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn parse(json: &str) -> Value {
    serde_json::from_str(json).expect("staged JSON must round-trip")
}

#[test]
fn sessions_empty_collapses_to_none() {
    assert!(stage_sessions_to_json(&[]).is_none());
}

#[test]
fn sessions_emit_required_fields_in_canonical_shape() {
    let row = StagedSessionImport {
        id: "s1".into(),
        label: "lab".into(),
        folder: "infra/prod".into(),
        host: "h.example".into(),
        port: 2222,
        user: "alice".into(),
        auth_type: "password".into(),
        password: "pw".into(),
        key_path: "/keys/id".into(),
        key_data: "data".into(),
        passphrase: "phrase".into(),
        key_id: Some("k0".into()),
        extras_json: r#"{"hello":"world"}"#.into(),
        via_session_id: Some("sx".into()),
        via_override_host: Some("bastion".into()),
        via_override_port: Some(2200),
        via_override_user: Some("jump".into()),
        created_at_ms: 1_777_161_600_000,
        updated_at_ms: 1_777_161_600_123,
    };
    let json = stage_sessions_to_json(&[row]).unwrap();
    let v = parse(&json);
    let s = &v.as_array().unwrap()[0];
    assert_eq!(s.get("id").and_then(Value::as_str), Some("s1"));
    assert_eq!(
        s.get("folder").and_then(Value::as_str),
        Some("infra/prod"),
        "folder is the path string, not folder_id",
    );
    assert_eq!(s.get("port").and_then(Value::as_i64), Some(2222));
    assert_eq!(
        s.get("created_at").and_then(Value::as_str),
        Some("2026-04-26T00:00:00.000Z"),
    );
    assert_eq!(
        s.get("updated_at").and_then(Value::as_str),
        Some("2026-04-26T00:00:00.123Z"),
    );
    assert_eq!(s.get("key_id").and_then(Value::as_str), Some("k0"));
    let extras = s.get("extras").unwrap();
    assert_eq!(
        extras.get("hello").and_then(Value::as_str),
        Some("world"),
        "extras must round-trip as a parsed object, not a JSON string",
    );
    assert_eq!(s.get("via_session_id").and_then(Value::as_str), Some("sx"),);
    let ov = s.get("via_override").unwrap();
    assert_eq!(ov.get("host").and_then(Value::as_str), Some("bastion"));
    assert_eq!(ov.get("port").and_then(Value::as_i64), Some(2200));
    assert_eq!(ov.get("user").and_then(Value::as_str), Some("jump"));
}

#[test]
fn sessions_omit_empty_optionals() {
    // Mirrors Dart's `if (s.keyId.isNotEmpty)` etc. branches —
    // the apply driver treats absent / empty consistently but
    // staging an empty `key_id: ""` would surface as a non-empty
    // override on the DB row, masking a never-set state. Belt
    // and braces.
    let row = StagedSessionImport {
        id: "s1".into(),
        label: "lab".into(),
        host: "h".into(),
        user: "u".into(),
        port: 22,
        auth_type: "password".into(),
        ..Default::default()
    };
    let json = stage_sessions_to_json(&[row]).unwrap();
    let v = parse(&json);
    let s = v.as_array().unwrap()[0].as_object().unwrap();
    assert!(!s.contains_key("key_id"));
    assert!(!s.contains_key("extras"));
    assert!(!s.contains_key("via_session_id"));
    assert!(!s.contains_key("via_override"));
}

#[test]
fn sessions_partial_via_override_collapses() {
    // Mirrors the Dart `if (ov != null)` guard — the override
    // surfaces only when host + port + user are all present. A
    // missing port (the fail-open case) drops the entire
    // override object, matching the existing apply-driver shape.
    let row = StagedSessionImport {
        id: "s1".into(),
        label: "lab".into(),
        host: "h".into(),
        user: "u".into(),
        port: 22,
        auth_type: "password".into(),
        via_override_host: Some("bastion".into()),
        via_override_port: None,
        via_override_user: Some("jump".into()),
        ..Default::default()
    };
    let json = stage_sessions_to_json(&[row]).unwrap();
    let v = parse(&json);
    assert!(!v.as_array().unwrap()[0]
        .as_object()
        .unwrap()
        .contains_key("via_override"));
}

#[test]
fn keys_round_trip_with_iso_created_at() {
    let row = StagedKeyImport {
        id: "k1".into(),
        label: "lab".into(),
        private_key: "PRIV".into(),
        public_key: "PUB".into(),
        key_type: "ed25519".into(),
        is_generated: true,
        created_at_ms: 1_777_161_600_000,
    };
    let json = stage_keys_to_json(&[row]).unwrap();
    let v = parse(&json);
    let k = &v.as_array().unwrap()[0];
    assert_eq!(k.get("id").and_then(Value::as_str), Some("k1"));
    assert_eq!(k.get("private_key").and_then(Value::as_str), Some("PRIV"));
    assert_eq!(k.get("is_generated").and_then(Value::as_bool), Some(true));
    assert_eq!(
        k.get("created_at").and_then(Value::as_str),
        Some("2026-04-26T00:00:00.000Z"),
    );
}

#[test]
fn tags_omit_color_when_unset() {
    let with_color = StagedTagImport {
        id: "t1".into(),
        name: "prod".into(),
        color: Some("#ff0000".into()),
        created_at_ms: 0,
    };
    let without_color = StagedTagImport {
        id: "t2".into(),
        name: "dev".into(),
        color: None,
        created_at_ms: 0,
    };
    let json = stage_tags_to_json(&[with_color, without_color]).unwrap();
    let v = parse(&json);
    let arr = v.as_array().unwrap();
    assert_eq!(arr[0].get("color").and_then(Value::as_str), Some("#ff0000"));
    assert!(!arr[1].as_object().unwrap().contains_key("color"));
}

#[test]
fn snippets_round_trip_with_iso_timestamps() {
    let row = StagedSnippetImport {
        id: "n1".into(),
        title: "t".into(),
        command: "ls".into(),
        description: "list".into(),
        created_at_ms: 1_777_161_600_000,
        updated_at_ms: 1_777_161_600_456,
    };
    let json = stage_snippets_to_json(&[row]).unwrap();
    let v = parse(&json);
    let s = &v.as_array().unwrap()[0];
    assert_eq!(
        s.get("created_at").and_then(Value::as_str),
        Some("2026-04-26T00:00:00.000Z"),
    );
    assert_eq!(
        s.get("updated_at").and_then(Value::as_str),
        Some("2026-04-26T00:00:00.456Z"),
    );
}

#[test]
fn extras_invalid_json_is_silently_dropped() {
    // Belt-and-braces — a malformed `extras` shouldn't poison
    // the entire session entry; the apply driver would otherwise
    // see a malformed JSON value and reject the whole row.
    let row = StagedSessionImport {
        id: "s1".into(),
        label: "lab".into(),
        host: "h".into(),
        user: "u".into(),
        port: 22,
        auth_type: "password".into(),
        extras_json: "not-json".into(),
        ..Default::default()
    };
    let json = stage_sessions_to_json(&[row]).unwrap();
    let v = parse(&json);
    assert!(!v.as_array().unwrap()[0]
        .as_object()
        .unwrap()
        .contains_key("extras"));
}
