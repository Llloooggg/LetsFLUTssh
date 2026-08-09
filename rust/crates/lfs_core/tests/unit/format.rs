/// Unit tests extracted from format.rs
/// Declared via `#[path] mod tests;` in the source file.
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

#[test]
fn format_date_pads_every_field() {
    assert_eq!(format_date(2026, 4, 28), "2026-04-28");
    assert_eq!(format_date(2026, 12, 31), "2026-12-31");
}

#[test]
fn format_clock_hms_pads_every_field() {
    assert_eq!(format_clock_hms(0, 0, 0), "00:00:00");
    assert_eq!(format_clock_hms(9, 5, 1), "09:05:01");
    assert_eq!(format_clock_hms(23, 59, 59), "23:59:59");
}

#[test]
fn filesafe_iso_timestamp_uses_dash_separators() {
    assert_eq!(
        format_filesafe_iso_timestamp(2026, 4, 29, 0, 49, 32),
        "2026-04-29T00-49-32"
    );
}

#[test]
fn filesafe_iso_timestamp_pads_every_field() {
    assert_eq!(
        format_filesafe_iso_timestamp(2026, 1, 1, 0, 0, 0),
        "2026-01-01T00-00-00"
    );
    assert_eq!(
        format_filesafe_iso_timestamp(2026, 12, 31, 23, 59, 59),
        "2026-12-31T23-59-59"
    );
}
