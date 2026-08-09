//! Pure display formatters shared across UI surfaces.
//!
//! Three helpers cover the readable-size + readable-duration
//! display patterns used throughout the app — transfer dialogs,
//! archive size estimates, log entries, recorder rotation
//! reports.
//!
//! These are byte-stable: every formatter produces ASCII output
//! with no locale or l10n dependency. The Dart layer keeps a
//! fallback mirror so flutter_test contexts that don't bootstrap
//! the FRB native lib still render the same strings; production
//! routes through these for one canonical grammar.
//!
//! Why Rust-canonical at all when the strings are tiny: there are
//! ≥4 divergent `formatSize` copies across the Dart codebase
//! (`utils/format.dart`, `unified_export_controller.dart`, ad-hoc
//! inline formatters in transfer dialogs). Picking the Rust
//! version as the canonical site lets the Dart copies retire
//! incrementally without a flag day.

/// Human-readable file size with B / KB / MB / GB units.
///
/// Threshold ladder uses 1024 (binary KiB) but renders with the
/// short labels ("KB" not "KiB") because that's what every Dart
/// caller has shipped to date — switching to SI labels would be
/// a user-visible change and is explicitly out of scope for the
/// canonical-grammar promotion.
///
/// Decimals: 1 for KB / MB, 2 for GB. Below 1 KB the value
/// renders as a bare integer so "999 B" doesn't grow a stray
/// trailing zero.
#[must_use]
pub fn format_size(bytes: i64) -> String {
    let neg = bytes < 0;
    let abs = bytes.unsigned_abs();
    let body = if abs < 1024 {
        format!("{abs} B")
    } else if abs < 1024 * 1024 {
        format!("{:.1} KB", abs as f64 / 1024.0)
    } else if abs < 1024 * 1024 * 1024 {
        format!("{:.1} MB", abs as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.2} GB", abs as f64 / (1024.0 * 1024.0 * 1024.0))
    };
    if neg {
        format!("-{body}")
    } else {
        body
    }
}

/// Human-readable file size with the IEC binary prefix labels
/// (B / KiB / MiB / GiB). Same threshold ladder as
/// [`format_size`] but shows the user the binary-prefix labels —
/// used by the recordings browser where the technical context
/// makes "MiB" read more naturally than "MB".
///
/// Decimals: 1 for KiB / MiB, 2 for GiB. Below 1 KiB the value
/// renders as a bare integer.
#[must_use]
pub fn format_size_iec(bytes: i64) -> String {
    let neg = bytes < 0;
    let abs = bytes.unsigned_abs();
    let body = if abs < 1024 {
        format!("{abs} B")
    } else if abs < 1024 * 1024 {
        format!("{:.1} KiB", abs as f64 / 1024.0)
    } else if abs < 1024 * 1024 * 1024 {
        format!("{:.1} MiB", abs as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.2} GiB", abs as f64 / (1024.0 * 1024.0 * 1024.0))
    };
    if neg {
        format!("-{body}")
    } else {
        body
    }
}

/// Human-readable duration with ms / s / m / h granularity.
///
/// Sub-second → `Nms`. Sub-minute → `Ns`. Sub-hour → `Nm Ss`.
/// Hour or more → `Nh Mm`. Mirrors the existing Dart
/// `formatDuration` shape byte-for-byte (no locale, no plurals).
#[must_use]
pub fn format_duration(millis: i64) -> String {
    if millis < 1000 {
        return format!("{millis}ms");
    }
    let total_seconds = millis / 1000;
    if total_seconds < 60 {
        return format!("{total_seconds}s");
    }
    let total_minutes = total_seconds / 60;
    if total_minutes < 60 {
        let secs = total_seconds % 60;
        return format!("{total_minutes}m {secs}s");
    }
    let total_hours = total_minutes / 60;
    let minutes = total_minutes % 60;
    format!("{total_hours}h {minutes}m")
}

/// Render a date/time as `YYYY-MM-DD HH:MM`. Inputs are the
/// already-extracted local-time fields — the Dart caller supplies
/// `(year, month, day, hour, minute)` from its `DateTime` so the
/// formatter stays pure (no timezone / clock dependency).
#[must_use]
pub fn format_timestamp_minute(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> String {
    format!("{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}")
}

/// Render a date as `YYYY-MM-DD`. Bare-day variant — used by the
/// key-manager list where the time component would just clutter
/// the row.
#[must_use]
pub fn format_date(year: i32, month: u32, day: u32) -> String {
    format!("{year:04}-{month:02}-{day:02}")
}

/// Render a clock time as `HH:MM:SS`. Used by the logger for its
/// per-line timestamp prefix; second-precision is enough for the
/// debug log file.
#[must_use]
pub fn format_clock_hms(hour: u32, minute: u32, second: u32) -> String {
    format!("{hour:02}:{minute:02}:{second:02}")
}

/// Render a UTC date+time as a filename-safe ISO timestamp:
/// `YYYY-MM-DDTHH-MM-SS`. Drops the colon (illegal on Windows /
/// awkward in shell paths) + the fractional second + the
/// timezone suffix. Used by the recorder to mint
/// `<isoTimestamp>.lfsr` paths under the per-session recordings
/// directory.
#[must_use]
pub fn format_filesafe_iso_timestamp(
    year: i32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
) -> String {
    format!("{year:04}-{month:02}-{day:02}T{hour:02}-{minute:02}-{second:02}")
}

/// Recordings-browser duration shape — fractional seconds below
/// 1 minute, `Nm SSs` below 1 hour, `Nh MMm` above. Distinct from
/// [`format_duration`] because the recordings come back from the
/// recorder as `f64` seconds (the asciinema timestamp shape) and
/// the UI shows fractional precision below the minute boundary.
#[must_use]
pub fn format_duration_seconds_fractional(seconds: f64) -> String {
    if seconds < 60.0 {
        return format!("{seconds:.1}s");
    }
    let total_minutes = (seconds / 60.0).floor() as i64;
    let secs = (seconds - (total_minutes as f64) * 60.0).floor() as i64;
    if total_minutes < 60 {
        return format!("{total_minutes}m {secs:02}s");
    }
    let total_hours = total_minutes / 60;
    let minutes = total_minutes - total_hours * 60;
    format!("{total_hours}h {minutes:02}m")
}
#[cfg(test)]
#[path = "../tests/unit/format.rs"]
mod tests;
