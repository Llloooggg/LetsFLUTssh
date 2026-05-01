//! ISO-8601 ⇄ unix-millis helpers shared by every archive path.
//!
//! Both the export composer and the import apply driver round-trip
//! timestamps through `YYYY-MM-DDTHH:MM:SS.mmmZ` strings — the
//! format Dart's `DateTime.toIso8601String()` emits when the source
//! is UTC. The staging module (`crate::archive_stage`) calls the
//! same formatters so the staged JSON it hands FRB matches what the
//! orchestrator-built JSON would emit.
//!
//! The body of each routine is Howard Hinnant's date algorithm:
//! pure integer arithmetic, leap-second-free, branch-safe across
//! the 1970 boundary. We keep it in-tree rather than pulling
//! `chrono`/`time` because every other archive concern is already
//! `lfs_core`-owned and these four functions are the only date math
//! the crate needs.

/// Format a unix-millis timestamp as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
/// Matches what `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
/// .toIso8601String()` would emit and parses cleanly through Dart's
/// `DateTime.tryParse`.
pub(crate) fn format_iso8601_utc(ms: i64) -> String {
    let secs_total = ms.div_euclid(1000);
    let millis = ms.rem_euclid(1000) as u32;
    let (year, month, day, hh, mm, ss) = unix_to_civil(secs_total);
    format!("{year:04}-{month:02}-{day:02}T{hh:02}:{mm:02}:{ss:02}.{millis:03}Z")
}

/// Convert unix seconds to `(Y, M, D, h, m, s)` UTC.
pub(crate) fn unix_to_civil(secs: i64) -> (i64, u32, u32, u32, u32, u32) {
    let days = secs.div_euclid(86_400);
    let time_of_day = secs.rem_euclid(86_400) as u32;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = if m <= 2 { y + 1 } else { y };
    let hh = time_of_day / 3600;
    let mm = (time_of_day % 3600) / 60;
    let ss = time_of_day % 60;
    (year, m, d, hh, mm, ss)
}

/// Inverse of [`unix_to_civil`] — used by the import apply driver
/// to round-trip the iso8601 strings the export emits back to
/// unix-millis.
pub(crate) fn civil_to_unix_ms(year: i64, month: u32, day: u32, hh: u32, mm: u32, ss: u32) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400; // 0..399
    let m = month as i64;
    let d = day as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days_since_epoch = era * 146_097 + doe - 719_468;
    let secs = days_since_epoch * 86_400 + (hh as i64) * 3600 + (mm as i64) * 60 + ss as i64;
    secs * 1000
}

/// Iso8601 → unix-millis. Best-effort: drops to `now` on parse
/// failure since the archive's "created_at" is informational only —
/// the row's effective timestamp is the apply moment.
pub(crate) fn parse_iso8601_or_now(s: &str, now_ms: i64) -> i64 {
    if s.is_empty() {
        return now_ms;
    }
    // Match the format we emit: YYYY-MM-DDTHH:MM:SS.mmmZ
    let bytes = s.as_bytes();
    if bytes.len() < 24 {
        return now_ms;
    }
    let parse = |off: usize, len: usize| -> Option<i64> {
        std::str::from_utf8(&bytes[off..off + len])
            .ok()?
            .parse::<i64>()
            .ok()
    };
    let year = parse(0, 4).unwrap_or(1970);
    let month = parse(5, 2).unwrap_or(1);
    let day = parse(8, 2).unwrap_or(1);
    let hh = parse(11, 2).unwrap_or(0);
    let mm = parse(14, 2).unwrap_or(0);
    let ss = parse(17, 2).unwrap_or(0);
    let ms = parse(20, 3).unwrap_or(0);
    civil_to_unix_ms(
        year,
        month as u32,
        day as u32,
        hh as u32,
        mm as u32,
        ss as u32,
    ) + ms
}

#[cfg(test)]
mod tests {
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
}
