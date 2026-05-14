//! FRB adapter for `lfs_core::qr_codec_encode`.
//!
//! Sync — deflate over a few-KiB JSON payload + base64url encode is
//! well under a millisecond on every target. The size-estimation
//! getters in `unified_export_controller` call this from
//! synchronous Riverpod-driven UI rebuilds, so async-jump overhead
//! would render-stutter the live "fits in QR" gauge.

use lfs_core::qr_codec_encode;

/// Deflate + base64url encode the JSON payload, returning the
/// `?d=` query value ready to embed in a `letsflutssh://import?d=…`
/// deeplink. Caller composes the surrounding URI Dart-side.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_codec_compress_to_payload(json: String) -> String {
    qr_codec_encode::compress_to_payload(&json)
}

/// Convenience — returns just the encoded byte count for the
/// live size-estimation getters in the unified export controller.
/// Avoids the round-trip cost of returning the full string when
/// the caller only renders a "fits in QR" gauge against a length.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_codec_compress_to_payload_size(json: String) -> u32 {
    qr_codec_encode::compress_to_payload_size(&json)
}

/// FRB-mirror of [`lfs_core::qr_codec_encode::SessionCompactInputs`].
/// Owned-string fields cross the FRB boundary one copy each — the
/// inner call borrows them as `&str` after assembly.
pub struct QrSessionCompactInputs {
    pub label: String,
    pub host: String,
    pub user: String,
    pub port: u16,
    pub folder: String,
    pub auth_type: String,
    pub key_short: Option<String>,
    pub is_manager: bool,
    pub include_passwords: bool,
    /// Lossy-decoded as UTF-8 inside the shim — invalid sequences
    /// collapse to empty, same fallback shape the prior
    /// `password: String` signature produced for malformed input.
    pub password: Vec<u8>,
}

/// Flat-struct mirror of the v4 QR per-session compact map. Every
/// optional field that the JSON encoder collapses out of the map
/// (`p` / `g` / `a` / `ki` / `mg` / `pw`) rides as `Option<…>`
/// here so the Dart caller pattern-matches typed presence instead
/// of running its own `jsonDecode` + key probe.
///
/// Mirrors the `lfs_core::qr_codec_encode::encode_session_compact`
/// grammar; the JSON-string variant in
/// [`qr_codec_encode_session_compact`] stays in place for callers
/// (production export payload) that splice the map into an outer
/// document. New / pure-test callers should prefer this typed
/// surface.
#[derive(Debug, Clone)]
pub struct DbQrSessionCompact {
    /// `l` — session label (always present).
    pub label: String,
    /// `h` — host.
    pub host: String,
    /// `u` — user.
    pub user: String,
    /// `p` — non-default port (omitted when 22).
    pub port: Option<u16>,
    /// `g` — folder path (omitted when empty).
    pub folder: Option<String>,
    /// `a` — non-default auth type wire-string (omitted for
    /// `"password"`).
    pub auth_type: Option<String>,
    /// `ki` — manager-key short id when the session resolved to one.
    pub key_short: Option<String>,
    /// `mg` — `Some(1)` flag when the keyed session points at a
    /// manager key.
    pub is_manager: Option<u32>,
    /// `pw` — plaintext password (only when the caller opted in
    /// via `include_passwords` and the password is non-empty).
    pub password: Option<String>,
}

/// Typed variant of [`qr_codec_encode_session_compact`]. Routes
/// through the same canonical encoder
/// (`lfs_core::qr_codec_encode::encode_session_compact`) so the
/// field-name grammar lives one place; on the way back out the
/// `Value` map decomposes into the typed struct rather than a JSON
/// string the Dart caller has to re-parse.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_codec_encode_session_compact_typed(inputs: QrSessionCompactInputs) -> DbQrSessionCompact {
    let password = String::from_utf8_lossy(&inputs.password);
    let value = qr_codec_encode::encode_session_compact(&qr_codec_encode::SessionCompactInputs {
        label: &inputs.label,
        host: &inputs.host,
        user: &inputs.user,
        port: inputs.port,
        folder: &inputs.folder,
        auth_type: &inputs.auth_type,
        key_short: inputs.key_short.as_deref(),
        is_manager: inputs.is_manager,
        include_passwords: inputs.include_passwords,
        password: &password,
    });
    let obj = value
        .as_object()
        .expect("encode_session_compact yields object");
    DbQrSessionCompact {
        // `l` / `h` / `u` are always present per the encoder
        // contract — fall back to empty rather than panic if the
        // upstream ever drops one.
        label: obj
            .get("l")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
        host: obj
            .get("h")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
        user: obj
            .get("u")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string(),
        port: obj
            .get("p")
            .and_then(serde_json::Value::as_u64)
            .map(|p| p as u16),
        folder: obj
            .get("g")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        auth_type: obj
            .get("a")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        key_short: obj
            .get("ki")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        is_manager: obj
            .get("mg")
            .and_then(serde_json::Value::as_u64)
            .map(|n| n as u32),
        password: obj
            .get("pw")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
    }
}

/// Build the v4 QR per-session compact map and return it as a
/// JSON-encoded string. The Dart caller decodes it into a
/// `Map<String, dynamic>` and inserts it under the outer
/// payload's `"s"` array — same shape the production
/// `lfs_core::archive::qr_export_payload` writer emits, so both
/// halves of the in-memory and DB-backed encoders agree on the
/// field-name grammar (`l` / `h` / `u` / `p` / `g` / `a` / `ki`
/// / `mg` / `pw`).
///
/// `port == 22`, `auth_type == "password"`, empty `folder`, and
/// missing `key_short` collapse out of the map (default-omit). The
/// `pw` field is gated behind `include_passwords` because QR
/// codes are camera-readable and silently embedding plaintext
/// passwords would be a security regression.
#[flutter_rust_bridge::frb(sync)]
pub fn qr_codec_encode_session_compact(inputs: QrSessionCompactInputs) -> String {
    // QR payload JSON is UTF-8; non-UTF-8 input bytes route
    // through `from_utf8_lossy` so the user still gets a session
    // that pastes back. The previous `unwrap_or_default()` would
    // silently drop the password entirely on a non-UTF-8 byte
    // (typically a paste from a legacy Latin-1 source) and ship
    // an "empty password" QR that imports as auth-failed.
    let password = String::from_utf8_lossy(&inputs.password);
    qr_codec_encode::encode_session_compact_json(&qr_codec_encode::SessionCompactInputs {
        label: &inputs.label,
        host: &inputs.host,
        user: &inputs.user,
        port: inputs.port,
        folder: &inputs.folder,
        auth_type: &inputs.auth_type,
        key_short: inputs.key_short.as_deref(),
        is_manager: inputs.is_manager,
        include_passwords: inputs.include_passwords,
        password: &password,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_inputs() -> QrSessionCompactInputs {
        QrSessionCompactInputs {
            label: "edge".into(),
            host: "edge.example".into(),
            user: "deploy".into(),
            port: 22,
            folder: "".into(),
            auth_type: "password".into(),
            key_short: None,
            is_manager: false,
            include_passwords: false,
            password: vec![],
        }
    }

    #[test]
    fn compress_to_payload_round_trips_size_to_byte_count() {
        // The size getter must agree with the full encoder's
        // length to a byte — UI gauges read the size directly to
        // decide "fits in QR" before the user commits to a write.
        let payload = qr_codec_compress_to_payload("{\"k\":\"v\"}".into());
        let size = qr_codec_compress_to_payload_size("{\"k\":\"v\"}".into());
        assert_eq!(payload.len() as u32, size);
    }

    #[test]
    fn encode_session_compact_emits_required_keys() {
        let json = qr_codec_encode_session_compact(default_inputs());
        // Required keys: label, host, user. Default port (22),
        // password auth, empty folder, and missing key collapse
        // out per the compact-export contract.
        assert!(json.contains("\"l\""));
        assert!(json.contains("\"h\""));
        assert!(json.contains("\"u\""));
        // Default-omit fields stay absent.
        assert!(!json.contains("\"p\""), "default port must collapse");
        assert!(!json.contains("\"g\""), "empty folder must collapse");
        assert!(!json.contains("\"a\""), "default auth must collapse");
        assert!(
            !json.contains("\"pw\""),
            "password gated by include_passwords"
        );
    }

    #[test]
    fn encode_session_compact_omits_password_unless_opt_in() {
        let mut inputs = default_inputs();
        inputs.password = b"hunter2".to_vec();
        // include_passwords stays false → pw must NOT surface.
        let json = qr_codec_encode_session_compact(inputs);
        assert!(!json.contains("hunter2"));
        assert!(!json.contains("\"pw\""));
    }

    #[test]
    fn encode_session_compact_includes_password_when_opted_in() {
        let mut inputs = default_inputs();
        inputs.password = b"hunter2".to_vec();
        inputs.include_passwords = true;
        let json = qr_codec_encode_session_compact(inputs);
        assert!(json.contains("hunter2"));
        assert!(json.contains("\"pw\""));
    }

    #[test]
    fn encode_session_compact_preserves_invalid_utf8_lossy() {
        let mut inputs = default_inputs();
        inputs.password = vec![0xFF, b'a', b'b'];
        inputs.include_passwords = true;
        let json = qr_codec_encode_session_compact(inputs);
        // The lossy decoder folds the leading non-UTF-8 byte to
        // U+FFFD; the trailing valid bytes survive. Without this
        // path a malformed paste would silently strip the entire
        // password.
        assert!(json.contains("ab"));
    }

    #[test]
    fn encode_session_compact_surfaces_non_default_port() {
        let mut inputs = default_inputs();
        inputs.port = 2222;
        let json = qr_codec_encode_session_compact(inputs);
        assert!(json.contains("\"p\""));
        assert!(json.contains("2222"));
    }
}
