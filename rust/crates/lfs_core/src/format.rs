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
}
