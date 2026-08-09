/// Unit tests extracted from archive/iso8601.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn iso8601_known_value() {
    // 2026-04-26T00:00:00.000Z → ms = 1777161600000
    assert_eq!(
        format_iso8601_utc(1_777_161_600_000),
        "2026-04-26T00:00:00.000Z"
    );
}

#[test]
fn iso8601_handles_millis() {
    assert_eq!(
        format_iso8601_utc(1_777_161_600_123),
        "2026-04-26T00:00:00.123Z"
    );
}

#[test]
fn iso8601_pre_epoch() {
    // -1s → 1969-12-31T23:59:59.000Z
    assert_eq!(format_iso8601_utc(-1_000), "1969-12-31T23:59:59.000Z");
}

#[test]
fn civil_to_unix_round_trips_unix_to_civil() {
    for ms in [
        0i64,
        1_700_000_000_000,
        1_777_161_600_123,
        -1_000,
        946_684_800_000, // 2000-01-01
    ] {
        let secs = ms.div_euclid(1000);
        let millis = ms.rem_euclid(1000);
        let (y, mo, d, hh, mm, ss) = unix_to_civil(secs);
        let back = civil_to_unix_ms(y, mo, d, hh, mm, ss) + millis;
        assert_eq!(back, ms, "round-trip failed for ms={ms}");
    }
}

#[test]
fn parse_iso8601_recovers_round_trip() {
    let ms = 1_777_161_600_123_i64;
    let s = format_iso8601_utc(ms);
    assert_eq!(parse_iso8601_or_now(&s, 0), ms);
}

#[test]
fn parse_iso8601_falls_back_on_garbage() {
    let now = 42;
    assert_eq!(parse_iso8601_or_now("", now), now);
    assert_eq!(parse_iso8601_or_now("nope", now), now);
}

#[test]
fn parse_iso8601_opt_returns_none_for_unparseable() {
    // The sync LWW gate relies on `None` for empty / too-short
    // input so it can default to 0 (lose) instead of `now` (win).
    assert_eq!(parse_iso8601_opt(""), None);
    assert_eq!(parse_iso8601_opt("nope"), None);
    assert_eq!(parse_iso8601_opt("2026-01-01"), None); // < 24 bytes
    let ms = 1_777_161_600_123_i64;
    assert_eq!(parse_iso8601_opt(&format_iso8601_utc(ms)), Some(ms));
}
