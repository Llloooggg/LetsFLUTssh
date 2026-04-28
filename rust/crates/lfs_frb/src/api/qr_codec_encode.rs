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
