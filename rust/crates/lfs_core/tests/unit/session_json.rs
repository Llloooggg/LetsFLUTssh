/// Unit tests extracted from session_json.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn populated_input() -> SessionJsonInput {
    SessionJsonInput {
        id: "sess-1".into(),
        label: "Edge prod".into(),
        folder: "production/web".into(),
        host: "edge.example.com".into(),
        port: 2222,
        user: "deploy".into(),
        kind: "ssh".into(),
        auth_type: "key".into(),
        key_id: "key-7c8f".into(),
        key_path: "/home/deploy/.ssh/id_ed25519".into(),
        created_at_iso: "2026-05-09T12:00:00.000Z".into(),
        updated_at_iso: "2026-05-09T13:30:00.000Z".into(),
        extras_json: r#"{"tags":"web,prod","priority":1}"#.into(),
        via_session_id: Some("bastion-id".into()),
        via_override: Some(SessionJsonViaOverride {
            host: "bastion.example.com".into(),
            port: 2200,
            user: "jump".into(),
        }),
        notes: "maintenance 03:00 UTC".into(),
        sort_order: 5,
        last_connected_at_ms: Some(1_715_000_000_000),
        include_credentials: false,
        password: "pwd".into(),
        key_data: "PEM".into(),
        passphrase: "phrase".into(),
    }
}

#[test]
fn encode_then_decode_round_trips_every_field() {
    let input = populated_input();
    let json = encode_canonical_json(&input).unwrap();
    let out = decode_canonical_json(&json).unwrap();

    assert_eq!(out.id, input.id);
    assert_eq!(out.label, input.label);
    assert_eq!(out.folder, input.folder);
    assert_eq!(out.host, input.host);
    assert_eq!(out.port, input.port);
    assert_eq!(out.user, input.user);
    // Default 'ssh' kind is omitted on emit; the decoder must
    // fold a missing key back to 'ssh'.
    assert_eq!(out.kind, "ssh");
    assert_eq!(out.auth_type, input.auth_type);
    assert_eq!(out.key_id, input.key_id);
    assert_eq!(out.key_path, input.key_path);
    assert_eq!(out.created_at_iso, input.created_at_iso);
    assert_eq!(out.updated_at_iso, input.updated_at_iso);
    assert_eq!(out.extras.get("priority"), Some(&SessionJsonValue::Int(1)));
    assert_eq!(
        out.extras.get("tags"),
        Some(&SessionJsonValue::Text("web,prod".into()))
    );
    assert_eq!(out.via_session_id.as_deref(), Some("bastion-id"));
    assert_eq!(
        out.via_override,
        Some(SessionJsonViaOverride {
            host: "bastion.example.com".into(),
            port: 2200,
            user: "jump".into(),
        })
    );
    assert_eq!(out.notes, input.notes);
    assert_eq!(out.sort_order, input.sort_order);
    assert_eq!(out.last_connected_at_ms, Some(1_715_000_000_000));
    // Credentials were not included in the encoded payload, so
    // the decoder leaves them empty even though the input
    // carried values.
    assert!(out.password.is_empty());
    assert!(out.key_data.is_empty());
    assert!(out.passphrase.is_empty());
}

#[test]
fn encode_with_credentials_emits_secret_trio_and_decode_reads_back() {
    let mut input = populated_input();
    input.include_credentials = true;
    let json = encode_canonical_json(&input).unwrap();
    assert!(json.contains("\"password\""));
    assert!(json.contains("\"key_data\""));
    assert!(json.contains("\"passphrase\""));
    let out = decode_canonical_json(&json).unwrap();
    assert_eq!(out.password, "pwd");
    assert_eq!(out.key_data, "PEM");
    assert_eq!(out.passphrase, "phrase");
}

#[test]
fn encode_omits_empty_extras_and_decode_handles_missing_key() {
    let mut input = populated_input();
    input.extras_json = String::new();
    let json = encode_canonical_json(&input).unwrap();
    assert!(!json.contains("\"extras\""));
    let out = decode_canonical_json(&json).unwrap();
    assert!(out.extras.is_empty());
}

#[test]
fn encode_omits_empty_extras_object() {
    let mut input = populated_input();
    input.extras_json = "{}".into();
    let json = encode_canonical_json(&input).unwrap();
    assert!(!json.contains("\"extras\""));
}

#[test]
fn decode_tolerates_json_encoded_extras_string() {
    // Older payloads sometimes embedded `"extras":"{\"k\":42}"` —
    // the column shape on the wire mirrors the row column. Make
    // sure the decoder handles both inline-object and string
    // shapes the same way.
    let payload = r#"{
        "id":"x","label":"l","folder":"","host":"h","port":22,"user":"u",
        "auth_type":"password","key_path":"","created_at":"","updated_at":"",
        "extras":"{\"k\":42}"
    }"#;
    let out = decode_canonical_json(payload).unwrap();
    assert_eq!(out.extras.get("k"), Some(&SessionJsonValue::Int(42)));
}

#[test]
fn decode_tolerates_corrupt_extras_string_with_empty_map() {
    let payload = r#"{
        "id":"x","label":"l","folder":"","host":"h","port":22,"user":"u",
        "auth_type":"password","key_path":"","created_at":"","updated_at":"",
        "extras":"{not-json"
    }"#;
    let out = decode_canonical_json(payload).unwrap();
    assert!(out.extras.is_empty());
}

#[test]
fn decode_legacy_group_key_aliases_folder() {
    let payload = r#"{
        "id":"x","label":"l","host":"h","user":"u","group":"Production/EU",
        "auth_type":"password","key_path":"","created_at":"","updated_at":""
    }"#;
    let out = decode_canonical_json(payload).unwrap();
    assert_eq!(out.folder, "Production/EU");
}

#[test]
fn decode_missing_optional_fields_lands_on_defaults() {
    let payload = r#"{"id":"x","host":"h","user":"u"}"#;
    let out = decode_canonical_json(payload).unwrap();
    assert_eq!(out.id, "x");
    assert_eq!(out.host, "h");
    assert_eq!(out.user, "u");
    assert_eq!(out.label, "");
    assert_eq!(out.folder, "");
    assert_eq!(out.port, 22);
    assert_eq!(out.kind, "ssh");
    assert_eq!(out.auth_type, "password");
    assert_eq!(out.key_id, "");
    assert_eq!(out.notes, "");
    assert_eq!(out.sort_order, 0);
    assert!(out.last_connected_at_ms.is_none());
    assert!(out.via_session_id.is_none());
    assert!(out.via_override.is_none());
}

#[test]
fn decode_via_override_with_missing_port_defaults_22() {
    let payload = r#"{
        "id":"x","host":"h","user":"u",
        "auth_type":"password","key_path":"","created_at":"","updated_at":"",
        "via_override":{"host":"b.example","user":"j"}
    }"#;
    let out = decode_canonical_json(payload).unwrap();
    let over = out.via_override.unwrap();
    assert_eq!(over.host, "b.example");
    assert_eq!(over.port, 22);
    assert_eq!(over.user, "j");
}

#[test]
fn decode_rejects_top_level_array() {
    let err = decode_canonical_json("[]").unwrap_err();
    assert!(err.contains("not a JSON object"), "got: {err}");
}

#[test]
fn decode_rejects_malformed_json() {
    let err = decode_canonical_json("{not-json").unwrap_err();
    assert!(err.contains("parse"), "got: {err}");
}

#[test]
fn extras_value_promotes_whole_floats_to_int() {
    // Trap: the `extrasInt('count')` accessor must accept
    // `5` and `5.0` indifferently — `jsonDecode` produces a
    // `num` either way, so the promote keeps that contract.
    let v = SessionJsonValue::from_value(&Value::from(5.0_f64));
    assert_eq!(v, SessionJsonValue::Int(5));
}

#[test]
fn extras_value_preserves_non_integer_floats() {
    let v = SessionJsonValue::from_value(&Value::from(1.5_f64));
    assert_eq!(v, SessionJsonValue::Double(1.5));
}

#[test]
fn extras_value_arrays_and_objects_carry_typed_children() {
    let array = serde_json::from_str::<Value>(r#"[1,"two",false]"#).unwrap();
    match SessionJsonValue::from_value(&array) {
        SessionJsonValue::Array(items) => {
            assert_eq!(items.len(), 3);
            assert_eq!(items[0], SessionJsonValue::Int(1));
            assert_eq!(items[1], SessionJsonValue::Text("two".into()));
            assert_eq!(items[2], SessionJsonValue::Bool(false));
        }
        other => panic!("expected Array, got {other:?}"),
    }
    let object = serde_json::from_str::<Value>(r#"{"nested":true}"#).unwrap();
    match SessionJsonValue::from_value(&object) {
        SessionJsonValue::Object(pairs) => {
            assert_eq!(pairs.len(), 1);
            assert_eq!(pairs[0].0, "nested");
            assert_eq!(pairs[0].1, SessionJsonValue::Bool(true));
        }
        other => panic!("expected Object, got {other:?}"),
    }
}

#[test]
fn extras_value_recurses_through_nested_arrays_and_objects() {
    let value =
        serde_json::from_str::<Value>(r#"{"layers":[{"name":"web","flags":[true,false]},42]}"#)
            .unwrap();
    let typed = SessionJsonValue::from_value(&value);
    let SessionJsonValue::Object(top) = typed else {
        panic!("expected top-level Object");
    };
    assert_eq!(top.len(), 1);
    assert_eq!(top[0].0, "layers");
    let SessionJsonValue::Array(layers) = &top[0].1 else {
        panic!("expected layers Array");
    };
    assert_eq!(layers.len(), 2);
    let SessionJsonValue::Object(first) = &layers[0] else {
        panic!("expected first layer Object");
    };
    // `serde_json::Map` uses a BTreeMap by default, so the inner
    // object's keys land sorted alphabetically ("flags" before
    // "name"). The Dart consumer does its own re-keying into a
    // `Map<String, Object?>` so the order is not load-bearing for
    // call sites — the test asserts on it to pin the contract.
    let first_keys: Vec<&str> = first.iter().map(|(k, _)| k.as_str()).collect();
    assert_eq!(first_keys, vec!["flags", "name"]);
    let flags_pair = first.iter().find(|(k, _)| k == "flags").unwrap();
    let SessionJsonValue::Array(flags) = &flags_pair.1 else {
        panic!("expected flags Array");
    };
    assert_eq!(
        flags,
        &vec![SessionJsonValue::Bool(true), SessionJsonValue::Bool(false)]
    );
    let name_pair = first.iter().find(|(k, _)| k == "name").unwrap();
    assert_eq!(name_pair.1, SessionJsonValue::Text("web".into()));
    assert_eq!(layers[1], SessionJsonValue::Int(42));
}

#[test]
fn session_array_round_trips_through_encode_decode() {
    let a = populated_input();
    let mut b = populated_input();
    b.id = "sess-2".into();
    b.label = "another".into();
    let encoded = encode_session_array(&[a.clone(), b.clone()]).unwrap();
    let decoded = decode_session_array(&encoded).unwrap();
    assert_eq!(decoded.len(), 2);
    assert_eq!(decoded[0].id, "sess-1");
    assert_eq!(decoded[0].label, "Edge prod");
    assert_eq!(decoded[1].id, "sess-2");
    assert_eq!(decoded[1].label, "another");
}

#[test]
fn session_array_decode_rejects_non_array_top_level() {
    let err = decode_session_array("{}").unwrap_err();
    assert!(err.contains("not a JSON array"), "got: {err}");
}

#[test]
fn decode_extras_string_handles_empty_blob() {
    assert!(decode_extras_string("").is_empty());
}

#[test]
fn decode_extras_string_yields_typed_leaves() {
    let m = decode_extras_string(r#"{"flag":true,"name":"r","count":7}"#);
    assert_eq!(m.get("flag"), Some(&SessionJsonValue::Bool(true)));
    assert_eq!(m.get("name"), Some(&SessionJsonValue::Text("r".into())));
    assert_eq!(m.get("count"), Some(&SessionJsonValue::Int(7)));
}

#[test]
fn encode_extras_string_empty_yields_empty_string() {
    // Mirrors the DB column default — the upsert path inserts
    // `''` for sessions with no extras and the decode side
    // tolerates an empty blob.
    assert_eq!(encode_extras_string(&[]).unwrap(), "");
}

#[test]
fn encode_extras_string_round_trips_through_decode() {
    let extras = vec![
        ("flag".to_string(), SessionJsonValue::Bool(true)),
        ("count".to_string(), SessionJsonValue::Int(7)),
        ("name".to_string(), SessionJsonValue::Text("edge".into())),
        (
            "nested".to_string(),
            SessionJsonValue::Object(vec![("k".to_string(), SessionJsonValue::Text("v".into()))]),
        ),
    ];
    let encoded = encode_extras_string(&extras).unwrap();
    let decoded = decode_extras_string(&encoded);
    assert_eq!(decoded.get("flag"), Some(&SessionJsonValue::Bool(true)));
    assert_eq!(decoded.get("count"), Some(&SessionJsonValue::Int(7)));
    assert_eq!(
        decoded.get("name"),
        Some(&SessionJsonValue::Text("edge".into()))
    );
    // Nested object round-trips intact.
    let SessionJsonValue::Object(pairs) = decoded.get("nested").cloned().unwrap() else {
        panic!("expected nested object");
    };
    assert_eq!(pairs.len(), 1);
    assert_eq!(pairs[0].0, "k");
    assert_eq!(pairs[0].1, SessionJsonValue::Text("v".into()));
}

#[test]
fn snapshot_envelope_round_trips_sessions_folders_description() {
    let a = populated_input();
    let envelope = encode_snapshot_envelope(
        std::slice::from_ref(&a),
        &["empty/folder".to_string()],
        "delete session",
    )
    .unwrap();
    let decoded = decode_snapshot_envelope(&envelope).unwrap();
    assert_eq!(decoded.sessions.len(), 1);
    assert_eq!(decoded.sessions[0].id, "sess-1");
    assert_eq!(decoded.empty_folders, vec!["empty/folder".to_string()]);
    assert_eq!(decoded.description, "delete session");
}

#[test]
fn snapshot_envelope_decode_tolerates_missing_fields() {
    // Tolerant decode: a malformed envelope with a missing
    // `emptyFolders` or `description` still round-trips so a
    // partial blob from a future build doesn't poison the undo
    // stack.
    let envelope = decode_snapshot_envelope(r#"{"sessions":[]}"#).unwrap();
    assert!(envelope.sessions.is_empty());
    assert!(envelope.empty_folders.is_empty());
    assert_eq!(envelope.description, "");
}

#[test]
fn snapshot_envelope_decode_rejects_non_object_root() {
    let err = decode_snapshot_envelope("[]").unwrap_err();
    assert!(err.contains("not a JSON object"), "got: {err}");
}
