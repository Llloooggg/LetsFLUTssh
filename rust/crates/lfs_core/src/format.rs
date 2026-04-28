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
mod tests {
    use super::*;

    #[test]
    fn format_size_renders_bytes_below_1024_as_bare_integer() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(1), "1 B");
        assert_eq!(format_size(1023), "1023 B");
    }

    #[test]
    fn format_size_renders_kb_with_one_decimal() {
        assert_eq!(format_size(1024), "1.0 KB");
        assert_eq!(format_size(1536), "1.5 KB");
    }

    #[test]
    fn format_size_renders_mb_with_one_decimal() {
        assert_eq!(format_size(1024 * 1024), "1.0 MB");
        assert_eq!(format_size(2 * 1024 * 1024 + 512 * 1024), "2.5 MB");
    }

    #[test]
    fn format_size_renders_gb_with_two_decimals() {
        assert_eq!(format_size(1024_i64 * 1024 * 1024), "1.00 GB");
        assert_eq!(
            format_size(1024_i64 * 1024 * 1024 + 256 * 1024 * 1024),
            "1.25 GB"
        );
    }

    #[test]
    fn format_size_handles_negative_bytes_with_leading_minus() {
        // Diff displays in transfer dialogs (estimated vs. actual)
        // can produce small negative deltas; keep the formatter
        // robust against the input rather than panic / return
        // garbage.
        assert_eq!(format_size(-512), "-512 B");
        assert_eq!(format_size(-1024), "-1.0 KB");
    }

    #[test]
    fn format_duration_renders_sub_second_in_milliseconds() {
        assert_eq!(format_duration(0), "0ms");
        assert_eq!(format_duration(999), "999ms");
    }

    #[test]
    fn format_duration_renders_sub_minute_in_seconds() {
        assert_eq!(format_duration(1000), "1s");
        assert_eq!(format_duration(45_000), "45s");
        assert_eq!(format_duration(59_999), "59s");
    }

    #[test]
    fn format_duration_renders_sub_hour_in_minutes_seconds() {
        assert_eq!(format_duration(60_000), "1m 0s");
        assert_eq!(format_duration(125_000), "2m 5s");
        assert_eq!(format_duration(3_599_000), "59m 59s");
    }

    #[test]
    fn format_duration_renders_hour_or_more_in_hours_minutes() {
        assert_eq!(format_duration(3_600_000), "1h 0m");
        assert_eq!(format_duration(7_500_000), "2h 5m");
    }

    #[test]
    fn format_size_iec_renders_binary_prefix_labels() {
        assert_eq!(format_size_iec(1023), "1023 B");
        assert_eq!(format_size_iec(1024), "1.0 KiB");
        assert_eq!(format_size_iec(1024 * 1024), "1.0 MiB");
        assert_eq!(format_size_iec(1024_i64 * 1024 * 1024), "1.00 GiB");
    }

    #[test]
    fn format_size_iec_handles_negative() {
        assert_eq!(format_size_iec(-2048), "-2.0 KiB");
    }

    #[test]
    fn format_duration_seconds_fractional_sub_minute_shows_one_decimal() {
        assert_eq!(format_duration_seconds_fractional(0.0), "0.0s");
        assert_eq!(format_duration_seconds_fractional(1.5), "1.5s");
        assert_eq!(format_duration_seconds_fractional(59.9), "59.9s");
    }

    #[test]
    fn format_duration_seconds_fractional_sub_hour_pads_seconds_to_two_digits() {
        assert_eq!(format_duration_seconds_fractional(60.0), "1m 00s");
        assert_eq!(format_duration_seconds_fractional(125.7), "2m 05s");
        assert_eq!(format_duration_seconds_fractional(3599.9), "59m 59s");
    }

    #[test]
    fn format_duration_seconds_fractional_hour_or_more_pads_minutes() {
        assert_eq!(format_duration_seconds_fractional(3600.0), "1h 00m");
        assert_eq!(format_duration_seconds_fractional(7500.0), "2h 05m");
    }

    #[test]
    fn format_timestamp_minute_zero_pads_every_field() {
        assert_eq!(
            format_timestamp_minute(2026, 4, 28, 9, 5),
            "2026-04-28 09:05"
        );
    }

    #[test]
    fn format_timestamp_minute_handles_two_digit_fields() {
        assert_eq!(
            format_timestamp_minute(2026, 12, 31, 23, 59),
            "2026-12-31 23:59"
        );
    }

    #[test]
    fn format_timestamp_minute_pads_year_below_1000() {
        // Defensive: a misbehaving consumer could pass a 3-digit
        // year; format helpers should not silently lose width.
        assert_eq!(format_timestamp_minute(99, 1, 1, 0, 0), "0099-01-01 00:00");
    }
}
