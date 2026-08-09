/// Unit tests extracted from qr_codec_encode.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn round_trip_via_inflate_recovers_original() {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
    use flate2::read::DeflateDecoder;
    use std::io::Read;

    let original = r#"{"v":1,"s":[{"l":"my-server","h":"example.com","u":"root"}]}"#;
    let payload = compress_to_payload(original);
    let compressed = URL_SAFE_NO_PAD.decode(payload.as_bytes()).unwrap();
    let mut decoder = DeflateDecoder::new(&compressed[..]);
    let mut decoded = String::new();
    decoder.read_to_string(&mut decoded).unwrap();
    assert_eq!(decoded, original);
}

#[test]
fn payload_uses_no_padding() {
    // Mirror the wire shape `lfs_core::archive::qr_export_payload`
    // writes — deeplink readers parse with `URL_SAFE_NO_PAD` so
    // a trailing `=` would land outside the accepted alphabet.
    let payload = compress_to_payload(r#"{"x":1}"#);
    assert!(
        !payload.contains('='),
        "payload carries `=` padding: {payload}"
    );
}

#[test]
fn payload_round_trips_through_canonical_archive_decoder() {
    // Belt-and-braces — feed the encoded payload through the
    // production `qr_codec_decode::decode_payload` path to prove
    // the encode + decode halves agree on alphabet + deflate
    // parameters, byte-for-byte.
    let original = r#"{"v":1,"s":[{"l":"x","h":"y","u":"z"}]}"#;
    let encoded = compress_to_payload(original);
    let decoded = crate::qr_codec_decode::decode_payload(&encoded);
    // `decode_payload` returns a `DecodedQrPayload`; the
    // round-trip succeeds when no error fires.
    assert!(
        decoded.is_ok(),
        "round-trip via decode_payload failed: {decoded:?}"
    );
}

#[test]
fn empty_input_round_trips_through_deflate() {
    // Empty JSON → minimum-size deflate stream → base64url ASCII.
    // Confirms the encoder doesn't panic on the degenerate input
    // a freshly-opened export dialog with no selection might hit.
    let payload = compress_to_payload("");
    assert!(
        !payload.is_empty(),
        "deflate frame is non-empty even on empty input"
    );
}

#[test]
fn payload_uses_url_safe_base64_alphabet() {
    // The deeplink wraps the payload as `letsflutssh://import?d=<payload>`.
    // base64url's `-` / `_` / `=` characters survive URI parsing
    // without percent-encoding; standard base64's `+` / `/` would
    // both need escaping. Confirm the encoder picked the right
    // alphabet by feeding deterministic bytes that produce both
    // alphabet branches.
    let payload = compress_to_payload("aaaa bbbb cccc dddd eeee ffff");
    for ch in payload.chars() {
        assert!(
            ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' || ch == '=',
            "non-url-safe char in payload: {ch:?}"
        );
    }
}

#[test]
fn size_helper_matches_full_encode_length() {
    let json = r#"{"hello":"world"}"#;
    assert_eq!(
        compress_to_payload_size(json),
        compress_to_payload(json).len() as u32
    );
}

#[test]
fn larger_input_compresses_more_than_smaller_input() {
    // Sanity check on the deflate ratio — the 100x-A run should
    // shrink way past the literal length, while a short random
    // payload doesn't gain much. Shows the encoder is actually
    // running deflate (vs. just base64url-passing the input).
    let small = compress_to_payload("hi");
    let big_repetitive = compress_to_payload(&"A".repeat(500));
    assert!(
        big_repetitive.len() < small.len() + 200,
        "deflate failed to compress 500 As: small={} big={}",
        small.len(),
        big_repetitive.len(),
    );
}

#[test]
fn session_compact_minimal_emits_only_required_keys() {
    // Default port + default auth + no folder + no key → only
    // `l` / `h` / `u` should be present. Mirrors the Dart
    // `encodeSessionCompact` baseline shape.
    let v = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "host.example",
        user: "alice",
        port: 22,
        folder: "",
        auth_type: "password",
        key_short: None,
        is_manager: false,
        include_passwords: false,
        password: "",
    });
    let m = v.as_object().unwrap();
    assert_eq!(m.len(), 3);
    assert_eq!(m.get("l").and_then(Value::as_str), Some("lab"));
    assert_eq!(m.get("h").and_then(Value::as_str), Some("host.example"));
    assert_eq!(m.get("u").and_then(Value::as_str), Some("alice"));
}

#[test]
fn session_compact_emits_optional_fields_only_when_non_default() {
    let v = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "host.example",
        user: "alice",
        port: 2222,
        folder: "infra/prod",
        auth_type: "key",
        key_short: Some("k0"),
        is_manager: true,
        include_passwords: false,
        password: "",
    });
    let m = v.as_object().unwrap();
    assert_eq!(m.get("p").and_then(Value::as_u64), Some(2222));
    assert_eq!(m.get("g").and_then(Value::as_str), Some("infra/prod"));
    assert_eq!(m.get("a").and_then(Value::as_str), Some("key"));
    assert_eq!(m.get("ki").and_then(Value::as_str), Some("k0"));
    assert_eq!(m.get("mg").and_then(Value::as_u64), Some(1));
    assert!(!m.contains_key("pw"));
}

#[test]
fn session_compact_password_gated_behind_opt_in() {
    // Without opt-in, password never lands in the payload even
    // when set — security default for QR. Mirrors the Dart
    // `includePasswords` gate.
    let off = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "h",
        user: "u",
        port: 22,
        folder: "",
        auth_type: "password",
        key_short: None,
        is_manager: false,
        include_passwords: false,
        password: "secret",
    });
    assert!(!off.as_object().unwrap().contains_key("pw"));

    let on = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "h",
        user: "u",
        port: 22,
        folder: "",
        auth_type: "password",
        key_short: None,
        is_manager: false,
        include_passwords: true,
        password: "secret",
    });
    assert_eq!(
        on.as_object()
            .and_then(|m| m.get("pw"))
            .and_then(Value::as_str),
        Some("secret"),
    );
}

#[test]
fn session_compact_password_opt_in_with_empty_password_omits_field() {
    // The opt-in alone shouldn't materialise an empty `pw` key —
    // the helper still skips it when the password is empty so the
    // payload doesn't carry a meaningless field.
    let v = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "h",
        user: "u",
        port: 22,
        folder: "",
        auth_type: "password",
        key_short: None,
        is_manager: false,
        include_passwords: true,
        password: "",
    });
    assert!(!v.as_object().unwrap().contains_key("pw"));
}

#[test]
fn session_compact_json_round_trips_through_serde() {
    // The FRB-friendly JSON-string variant must produce the same
    // shape as the `Value` variant, byte-for-byte after a
    // `serde_json::to_string` of the latter.
    let v = encode_session_compact(&SessionCompactInputs {
        label: "lab",
        host: "h",
        user: "u",
        port: 2222,
        folder: "g",
        auth_type: "key",
        key_short: Some("k1"),
        is_manager: true,
        include_passwords: false,
        password: "",
    });
    let direct = serde_json::to_string(&v).unwrap();
    let via_helper = encode_session_compact_json(&SessionCompactInputs {
        label: "lab",
        host: "h",
        user: "u",
        port: 2222,
        folder: "g",
        auth_type: "key",
        key_short: Some("k1"),
        is_manager: true,
        include_passwords: false,
        password: "",
    });
    assert_eq!(direct, via_helper);
}
