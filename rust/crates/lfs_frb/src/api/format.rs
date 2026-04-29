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

/// Render a date/time as `YYYY-MM-DD HH:MM`. Caller supplies the
/// already-extracted local-time fields so the formatter stays
/// pure (no timezone / clock dependency).
#[flutter_rust_bridge::frb(sync)]
pub fn format_timestamp_minute(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> String {
    format::format_timestamp_minute(year, month, day, hour, minute)
}

/// Render a date as `YYYY-MM-DD`. Bare-day variant for surfaces
/// like the key-manager list where the time component would just
/// clutter the row.
#[flutter_rust_bridge::frb(sync)]
pub fn format_date(year: i32, month: u32, day: u32) -> String {
    format::format_date(year, month, day)
}

/// Render a clock time as `HH:MM:SS`. Used by the logger for its
/// per-line timestamp prefix.
#[flutter_rust_bridge::frb(sync)]
pub fn format_clock_hms(hour: u32, minute: u32, second: u32) -> String {
    format::format_clock_hms(hour, minute, second)
}

/// Render a UTC date+time as a filename-safe ISO timestamp:
/// `YYYY-MM-DDTHH-MM-SS`. Drops the colon (illegal on Windows /
/// awkward in shell paths). Used by the recorder file-name path.
#[flutter_rust_bridge::frb(sync)]
pub fn format_filesafe_iso_timestamp(
    year: i32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
) -> String {
    format::format_filesafe_iso_timestamp(year, month, day, hour, minute, second)
}
