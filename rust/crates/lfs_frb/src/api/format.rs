//! FRB adapter for `lfs_core::format` display helpers.
//!
//! Sync — every formatter is one branch + one `format!` macro,
//! sub-microsecond per call. Dart callers render text widgets
//! against these helpers from the build phase, so an async hop
//! would buy nothing and add a microtask jump.

use lfs_core::format;

/// Human-readable file size (B / KB / MB / GB).
#[flutter_rust_bridge::frb(sync)]
pub fn format_size(bytes: i64) -> String {
    format::format_size(bytes)
}

/// Human-readable duration (ms / s / m / h granularity).
#[flutter_rust_bridge::frb(sync)]
pub fn format_duration(millis: i64) -> String {
    format::format_duration(millis)
}

/// Human-readable file size with IEC binary-prefix labels
/// (B / KiB / MiB / GiB). Used by the recordings browser where
/// the technical context fits "MiB" better than "MB".
#[flutter_rust_bridge::frb(sync)]
pub fn format_size_iec(bytes: i64) -> String {
    format::format_size_iec(bytes)
}

/// Recordings-browser duration shape — fractional seconds below
/// 1 minute, `Nm SSs` below 1 hour, `Nh MMm` above. Distinct from
/// `format_duration` because the asciinema timestamp is f64
/// seconds.
#[flutter_rust_bridge::frb(sync)]
pub fn format_duration_seconds_fractional(seconds: f64) -> String {
    format::format_duration_seconds_fractional(seconds)
}
