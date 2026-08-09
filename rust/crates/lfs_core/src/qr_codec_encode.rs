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
//!   QR JSON shape, then routes through [`compress_to_payload`]
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

/// Build the QR per-session compact map. Single source of truth
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
#[derive(Clone, Debug)]
pub struct SessionCompactInputs<'a> {
    pub label: &'a str,
    pub host: &'a str,
    pub user: &'a str,
    pub port: u16,
    pub folder: &'a str,
    pub auth_type: &'a str,
    pub key_short: Option<&'a str>,
    pub is_manager: bool,
    pub include_passwords: bool,
    pub password: &'a str,
}

#[must_use]
pub fn encode_session_compact(inputs: &SessionCompactInputs<'_>) -> Value {
    let SessionCompactInputs {
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
    } = *inputs;
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
pub fn encode_session_compact_json(inputs: &SessionCompactInputs<'_>) -> String {
    let v = encode_session_compact(inputs);
    serde_json::to_string(&v).expect("Map<String, Value> serialisation cannot fail")
}
#[cfg(test)]
#[path = "../tests/unit/qr_codec_encode.rs"]
mod tests;
