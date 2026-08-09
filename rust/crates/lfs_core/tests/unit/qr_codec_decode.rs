/// Unit tests extracted from qr_codec_decode.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::io::Write;

fn encode_payload_test(json_str: &str) -> String {
    use flate2::write::DeflateEncoder;
    use flate2::Compression;
    let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
    enc.write_all(json_str.as_bytes()).unwrap();
    let deflated = enc.finish().unwrap();
    URL_SAFE_NO_PAD.encode(&deflated)
}

#[test]
fn empty_payload_errors() {
    let payload = encode_payload_test(r#"{"v": 1}"#);
    let err = decode_payload(&payload).unwrap_err();
    assert!(err.to_string().contains("empty"));
}

#[test]
fn future_version_rejected() {
    let payload = encode_payload_test(r#"{"v": 99, "s": []}"#);
    let err = decode_payload(&payload).unwrap_err();
    assert!(err.to_string().contains("version too new"));
}

#[test]
fn current_wire_version_is_accepted() {
    // The composer stamps `SchemaVersions::QR_PAYLOAD` as `v`; the
    // decoder's ceiling derives from the same constant. A payload at
    // exactly that version must decode — a regression where the two
    // drifted (composer at 4, ceiling at 1) rejected every export as
    // "version too new". Build the version literal from the registry
    // so this stays a same-source check, not a copy of `4`.
    let v = CURRENT_FORMAT_VERSION;
    let payload = encode_payload_test(&format!(
        r#"{{"v": {v}, "s": [{{"l": "x", "h": "h", "u": "u"}}]}}"#
    ));
    assert!(
        decode_payload(&payload).is_ok(),
        "payload at the current wire version v{v} must decode"
    );
}

#[test]
fn decodes_session_array_with_minted_ids() {
    let json_str = r#"{
        "v": 1,
        "s": [
            {"l": "host-a", "h": "a.com", "u": "alice", "p": 2222},
            {"l": "host-b", "h": "b.com", "u": "bob"}
        ]
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let sessions: Vec<Value> =
        serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
    assert_eq!(sessions.len(), 2);
    let s0 = sessions[0].as_object().unwrap();
    assert_eq!(s0.get("label").unwrap().as_str(), Some("host-a"));
    assert_eq!(s0.get("host").unwrap().as_str(), Some("a.com"));
    assert_eq!(s0.get("port").unwrap().as_i64(), Some(2222));
    assert!(!s0.get("id").unwrap().as_str().unwrap().is_empty());
    let s1 = sessions[1].as_object().unwrap();
    assert_eq!(s1.get("port").unwrap().as_i64(), Some(22));
}

#[test]
fn decodes_manager_key_with_short_ref() {
    let json_str = r#"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u", "ki": "k0", "mg": 1}],
        "km": {"k0": "PEM_BYTES"},
        "mk": {"k0": {"l": "MyKey", "t": "ssh-ed25519", "p": "ssh-ed25519 BBBB"}}
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let sessions: Vec<Value> =
        serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
    let s0 = sessions[0].as_object().unwrap();
    assert_eq!(s0.get("key_id").unwrap().as_str(), Some("k0"));
    assert_eq!(s0.get("key_data").unwrap().as_str(), Some(""));

    let keys: Vec<Value> =
        serde_json::from_str(result.pending.keys_json.as_deref().unwrap()).unwrap();
    let k0 = keys[0].as_object().unwrap();
    assert_eq!(k0.get("id").unwrap().as_str(), Some("k0"));
    assert_eq!(k0.get("label").unwrap().as_str(), Some("MyKey"));
    assert_eq!(k0.get("private_key").unwrap().as_str(), Some("PEM_BYTES"));
    assert_eq!(k0.get("key_type").unwrap().as_str(), Some("ssh-ed25519"));
}

#[test]
fn manager_ref_missing_from_km_imports_session_keyless() {
    // Truncated / adversarial payload: the session references a
    // manager key short id that the `km` dedup map does not
    // carry. The manager-key row is emitted only for short ids
    // present in `km`, so keeping the reference would dangle and
    // fail the FK on apply. The session must import keyless.
    let json_str = r#"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u", "ki": "ghost", "mg": 1}],
        "km": {},
        "mk": {"ghost": {"l": "MyKey", "t": "ssh-ed25519", "p": "ssh-ed25519 BBBB"}}
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let sessions: Vec<Value> =
        serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
    let s0 = sessions[0].as_object().unwrap();
    assert!(
        s0.get("key_id").is_none(),
        "dangling manager reference must be dropped, got {:?}",
        s0.get("key_id")
    );
    assert_eq!(s0.get("key_data").unwrap().as_str(), Some(""));
    // No usable manager key row landed either.
    assert!(result.pending.keys_json.is_none());
}

#[test]
fn inflate_capped_rejects_oversize_without_materialising_all() {
    // A highly-compressible payload larger than the cap must be
    // rejected. The read-based decoder caps materialisation at
    // `cap + 1`, so this never balloons the heap to the full
    // decompressed size.
    let oversize = vec![b'A'; MAX_INFLATED_PAYLOAD_BYTES + 4096];
    let compressed = {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
        enc.write_all(&oversize).unwrap();
        enc.finish().unwrap()
    };
    match inflate_capped(&compressed) {
        Err(InflateError::TooLarge { limit }) => {
            assert_eq!(limit, MAX_INFLATED_PAYLOAD_BYTES);
        }
        Err(InflateError::Inflate) => panic!("expected TooLarge, got Inflate"),
        Ok(v) => panic!("expected TooLarge, got Ok({} bytes)", v.len()),
    }
    // A within-cap payload still round-trips.
    let small = b"hello world";
    let compressed_small = {
        use flate2::write::DeflateEncoder;
        use flate2::Compression;
        let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
        enc.write_all(small).unwrap();
        enc.finish().unwrap()
    };
    assert_eq!(inflate_capped(&compressed_small).unwrap(), small);
}

#[test]
fn decodes_embedded_key_inline() {
    let json_str = r#"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u", "ki": "k0"}],
        "km": {"k0": "INLINE_PEM"}
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let sessions: Vec<Value> =
        serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
    let s0 = sessions[0].as_object().unwrap();
    assert!(s0.get("key_id").is_none() || s0.get("key_id").unwrap() == &json!(""));
    assert_eq!(s0.get("key_data").unwrap().as_str(), Some("INLINE_PEM"));
}

#[test]
fn decodes_tags_and_links() {
    // The session carries short id `s0`; the `st` link references
    // it and must resolve onto the UUID `decode_session` mints
    // (the compact session shape carries no UUID of its own).
    let json_str = r##"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u", "i": "s0"}],
        "tg": [{"i": "tag1", "n": "Production", "cl": "#ff0000"}],
        "st": [{"si": "s0", "ti": "tag1"}],
        "ft": [{"fi": "/folder", "ti": "tag1"}]
    }"##;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let tags: Vec<Value> =
        serde_json::from_str(result.pending.tags_json.as_deref().unwrap()).unwrap();
    assert_eq!(
        tags[0].as_object().unwrap().get("name").unwrap().as_str(),
        Some("Production")
    );
    assert_eq!(
        tags[0].as_object().unwrap().get("color").unwrap().as_str(),
        Some("#ff0000")
    );
    let sessions: Vec<Value> =
        serde_json::from_str(result.pending.sessions_json.as_deref().unwrap()).unwrap();
    let session_id = sessions[0]["id"].as_str().unwrap();
    let links: Vec<Value> =
        serde_json::from_str(result.pending.session_tags_json.as_deref().unwrap()).unwrap();
    assert_eq!(links.len(), 1);
    assert_eq!(links[0]["session_id"].as_str(), Some(session_id));
    assert_eq!(links[0]["tag_id"].as_str(), Some("tag1"));
    // folder_tags key on path, not the session remap.
    assert!(result.pending.folder_tags_json.is_some());
}

#[test]
fn session_link_to_absent_session_is_dropped() {
    // A link whose short id no session carries (truncated payload,
    // or a pre-short-id payload) must be dropped rather than
    // passed through with a dangling session id — applying it
    // would FK-fail and, in replace mode, roll back the import.
    let json_str = r##"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u", "i": "s0"}],
        "tg": [{"i": "tag1", "n": "P"}],
        "sn": [{"i": "sn1", "t": "T", "cm": "c"}],
        "st": [{"si": "ghost", "ti": "tag1"}],
        "ss": [{"si": "ghost", "ni": "sn1"}]
    }"##;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    assert!(result.pending.session_tags_json.is_none());
    assert!(result.pending.session_snippets_json.is_none());
}

#[test]
fn decodes_snippets() {
    let json_str = r#"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u"}],
        "sn": [{"i": "s1", "t": "Title", "cm": "echo hi", "d": "desc"}]
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    let snips: Vec<Value> =
        serde_json::from_str(result.pending.snippets_json.as_deref().unwrap()).unwrap();
    let s = snips[0].as_object().unwrap();
    assert_eq!(s.get("title").unwrap().as_str(), Some("Title"));
    assert_eq!(s.get("command").unwrap().as_str(), Some("echo hi"));
    assert_eq!(s.get("description").unwrap().as_str(), Some("desc"));
}

#[test]
fn decodes_config_and_known_hosts() {
    let json_str = r#"{
        "v": 1,
        "s": [{"l": "x", "h": "h", "u": "u"}],
        "c": {"theme": "dark"},
        "kh": "host:22 ssh-rsa AAAA"
    }"#;
    let result = decode_payload(&encode_payload_test(json_str)).unwrap();
    assert_eq!(
        result.pending.config_json.as_deref(),
        Some(r#"{"theme":"dark"}"#)
    );
    assert_eq!(
        result.pending.known_hosts_text.as_deref(),
        Some("host:22 ssh-rsa AAAA")
    );
}

#[test]
fn non_deflate_payload_is_rejected() {
    // v1 is strictly deflate — raw base64url(JSON) with no deflate
    // envelope is below the floor and must not decode.
    let json_str = r#"{"v": 1, "s": [{"l": "x", "h": "h", "u": "u"}]}"#;
    let payload = URL_SAFE_NO_PAD.encode(json_str.as_bytes());
    let err = decode_payload(&payload).unwrap_err();
    assert!(err.to_string().contains("inflate"));
}

#[test]
fn extract_payload_from_uri_returns_d_value() {
    let uri = "letsflutssh://import?d=ABCD";
    assert_eq!(extract_payload_from_uri(uri), Some("ABCD".into()));
}

#[test]
fn extract_payload_rejects_other_schemes() {
    assert_eq!(extract_payload_from_uri("https://example.com"), None);
    assert_eq!(
        extract_payload_from_uri("letsflutssh://connect?host=h"),
        None
    );
}

#[test]
fn malformed_base64_errors() {
    let err = decode_payload("!!!not-base64!!!").unwrap_err();
    assert!(err.to_string().contains("base64"));
}
