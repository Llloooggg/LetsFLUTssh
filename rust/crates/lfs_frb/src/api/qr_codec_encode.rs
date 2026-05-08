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
