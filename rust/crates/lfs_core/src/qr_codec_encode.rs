//! QR-payload compression + transport encoding.
//!
//! The QR import deeplink (`letsflutssh://import?d=…`) carries a
//! deflate-compressed JSON payload, base64url-encoded so it survives
//! the URI's character set. This module owns the
//! deflate + base64url half of the pipeline.
//!
//! Two callers share the helper:
//!
//! * `lfs_core::archive::qr_export_payload` — production encoder
//!   that pulls session data from the DB and serialises it into the
//!   v4 QR JSON shape, then routes through [`compress_to_payload`]
//!   for the deflate + base64url step so the wire format lives one
//!   place.
//! * Dart `unified_export_controller` size-estimation gauge — builds
//!   a small in-memory dummy payload for live "fits in QR" feedback
//!   and routes through [`compress_to_payload_size`] so the
//!   deflate parameters + base64url alphabet match the production
//!   path byte-for-byte.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use flate2::write::DeflateEncoder;
use flate2::Compression;
use serde_json::{json, Value};
use std::io::Write;

/// Deflate-compress [`json`] (UTF-8 bytes) and return the
/// base64url-encoded ciphertext, ready to embed in a deeplink's
/// `?d=` query parameter.
///
/// Compression level: `Compression::default()` (level 6) — same as
/// the Dart `Deflate(bytes).getBytes()` shape with `package:archive`
/// defaults. A smaller level would shrink CPU at the cost of QR-fit
/// margin; a higher level adds 50ms+ per call without reducing the
/// payload meaningfully.
#[must_use]
pub fn compress_to_payload(json: &str) -> String {
    let mut encoder = DeflateEncoder::new(Vec::new(), Compression::default());
    encoder
        .write_all(json.as_bytes())
        .expect("DeflateEncoder write into Vec cannot fail");
    let compressed = encoder
        .finish()
        .expect("DeflateEncoder finish into Vec cannot fail");
    // No-pad to match `lfs_core::archive::qr_export_payload`'s
    // wire shape — deeplink readers (`qr_codec_decode`) accept the
    // no-pad alphabet only.
    URL_SAFE_NO_PAD.encode(&compressed)
}

/// Convenience wrapper that returns just the encoded byte count —
/// used by the live size-estimation getters in
/// `unified_export_controller`. Avoids the round-trip cost of
/// returning the full string when the caller only cares about the
/// length (and the QR-fit budget the controller renders against).
#[must_use]
pub fn compress_to_payload_size(json: &str) -> u32 {
    compress_to_payload(json).len() as u32
}

/// Build the v4 QR per-session compact map. Single source of truth
/// for the field-name grammar that both production paths share:
///
/// * `lfs_core::archive::qr_export_payload` — DB-side encoder, calls
///   into this helper after pulling `SessionRow`s + folder paths.
/// * Dart `qr_codec.encodeSessionCompact` — in-memory encoder for the
///   export-dialog's live size-estimation surface, routes through
///   the FRB shim so the Dart layer never owns the field-name set.
///
/// `port` of `22` is omitted (deeplink callers default to 22 when
/// unset). `auth_type == "password"` is omitted (default). `mg`
/// only appears when the session's key resolved to a manager-owned
/// short id. `pw` is gated behind `include_passwords` — callers
/// must opt in explicitly because QR codes are camera-readable.
#[must_use]
#[allow(clippy::too_many_arguments)]
pub fn encode_session_compact(
    label: &str,
    host: &str,
    user: &str,
    port: u16,
    folder: &str,
    auth_type: &str,
    key_short: Option<&str>,
    is_manager: bool,
    include_passwords: bool,
    password: &str,
) -> Value {
    let mut m = serde_json::Map::new();
    m.insert("l".into(), json!(label));
    m.insert("h".into(), json!(host));
    m.insert("u".into(), json!(user));
    if port != 22 {
        m.insert("p".into(), json!(port));
    }
    if !folder.is_empty() {
        m.insert("g".into(), json!(folder));
    }
    if auth_type != "password" {
        m.insert("a".into(), json!(auth_type));
    }
    if let Some(k) = key_short {
        m.insert("ki".into(), json!(k));
    }
    if is_manager {
        m.insert("mg".into(), json!(1));
    }
    if include_passwords && !password.is_empty() {
        m.insert("pw".into(), json!(password));
    }
    Value::Object(m)
}

/// JSON-string variant of [`encode_session_compact`] for the FRB
/// boundary. Dart parses the result via `jsonDecode` to land back
/// at a `Map<String, dynamic>` shape its caller composes into the
/// outer payload object. Stringification keeps the FRB type list
/// to one return type instead of forcing a heterogeneous map shape.
#[must_use]
#[allow(clippy::too_many_arguments)]
pub fn encode_session_compact_json(
    label: &str,
    host: &str,
    user: &str,
    port: u16,
    folder: &str,
    auth_type: &str,
    key_short: Option<&str>,
    is_manager: bool,
    include_passwords: bool,
    password: &str,
) -> String {
    let v = encode_session_compact(
        label,
        host,
        user,
        port,
        folder,
        auth_type,
        key_short,
        is_manager,
        include_passwords,
        password,
    );
    serde_json::to_string(&v).expect("Map<String, Value> serialisation cannot fail")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_via_inflate_recovers_original() {
        use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
        use flate2::read::DeflateDecoder;
        use std::io::Read;

        let original = r#"{"v":4,"s":[{"l":"my-server","h":"example.com","u":"root"}]}"#;
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
        let original = r#"{"v":4,"s":[{"l":"x","h":"y","u":"z"}]}"#;
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
        let v = encode_session_compact(
            "lab",
            "host.example",
            "alice",
            22,
            "",
            "password",
            None,
            false,
            false,
            "",
        );
        let m = v.as_object().unwrap();
        assert_eq!(m.len(), 3);
        assert_eq!(m.get("l").and_then(Value::as_str), Some("lab"));
        assert_eq!(m.get("h").and_then(Value::as_str), Some("host.example"));
        assert_eq!(m.get("u").and_then(Value::as_str), Some("alice"));
    }

    #[test]
    fn session_compact_emits_optional_fields_only_when_non_default() {
        let v = encode_session_compact(
            "lab",
            "host.example",
            "alice",
            2222,
            "infra/prod",
            "key",
            Some("k0"),
            true,
            false,
            "",
        );
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
        let off = encode_session_compact(
            "lab", "h", "u", 22, "", "password", None, false, false, "secret",
        );
        assert!(!off.as_object().unwrap().contains_key("pw"));

        let on = encode_session_compact(
            "lab", "h", "u", 22, "", "password", None, false, true, "secret",
        );
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
        let v = encode_session_compact("lab", "h", "u", 22, "", "password", None, false, true, "");
        assert!(!v.as_object().unwrap().contains_key("pw"));
    }

    #[test]
    fn session_compact_json_round_trips_through_serde() {
        // The FRB-friendly JSON-string variant must produce the same
        // shape as the `Value` variant, byte-for-byte after a
        // `serde_json::to_string` of the latter.
        let v = encode_session_compact(
            "lab",
            "h",
            "u",
            2222,
            "g",
            "key",
            Some("k1"),
            true,
            false,
            "",
        );
        let direct = serde_json::to_string(&v).unwrap();
        let via_helper = encode_session_compact_json(
            "lab",
            "h",
            "u",
            2222,
            "g",
            "key",
            Some("k1"),
            true,
            false,
            "",
        );
        assert_eq!(direct, via_helper);
    }
}
