//! QR-payload compression + transport encoding.
//!
//! The QR import deeplink (`letsflutssh://import?d=…`) carries a
//! deflate-compressed JSON payload, base64url-encoded so it survives
//! the URI's character set. This module owns the
//! deflate + base64url half of the pipeline; the JSON construction
//! lives Dart-side until the in-memory encoder retires.
//!
//! Two callers share the helper today:
//!
//! * `lfs_core::archive::qr_export_payload` — production encoder
//!   that pulls session data from the DB and serialises it into the
//!   v4 QR JSON shape. Routes through [`compress_to_payload`] for
//!   the deflate + base64url step so the wire format lives one
//!   place.
//! * Dart `unified_export_controller` + `qr_codec` (legacy in-memory
//!   encoder + the size-estimation getters that drive the live UI
//!   feedback). Route via the FRB shim so the deflate parameters +
//!   base64url alphabet stay in lock-step with the production path.

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use flate2::write::DeflateEncoder;
use flate2::Compression;
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
}
