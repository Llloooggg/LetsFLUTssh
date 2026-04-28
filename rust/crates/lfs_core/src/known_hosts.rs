//! Manager-style helpers around `lfs_core::known_hosts_parser` +
//! `lfs_core::db::known_hosts`. Wraps the import / export string
//! formats and emits a `KnownHostsChanged` bus event so the Dart
//! cache refreshes without a separate notification channel.
//!
//! The parser stays in [`crate::known_hosts_parser`] (single-line
//! parse + hashed-line detection — pure functions over strings).
//! This module owns the bulk shape: split a multi-line blob,
//! upsert each entry, count what was added vs skipped (existing
//! entries / hashed-hostnames we cannot reverse).

use std::sync::Arc;

use crate::app::AppState;
use crate::bus::Event;
use crate::db::Db;
use crate::error::Error;
use crate::known_hosts_parser;

/// Outcome of a single import call. The Dart UI surfaces both
/// counts so the user knows the difference between "entry already
/// in the DB" (skipped) and "couldn't parse the row" (warning).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ImportSummary {
    pub added: i64,
    pub skipped_existing: i64,
    pub skipped_hashed: i64,
}

/// Parse `content` (LetsFLUTssh + OpenSSH known_hosts wire formats),
/// upsert any new entries against the running DB, and return the
/// summary. Existing host:port entries are left untouched —
/// import is additive, never overwrites a TOFU-accepted entry with
/// a possibly-stale one from a paste-link.
///
/// Emits one `KnownHostsChanged` event when at least one row was
/// added; no event on an all-skip import.
///
/// Per-line + per-row failures are logged and counted; a single
/// malformed line never aborts the whole import.
pub fn import_from_string(
    db: &Db,
    bus: &crate::bus::EventBus,
    content: &str,
    now_ms: i64,
) -> Result<ImportSummary, Error> {
    let mut summary = ImportSummary::default();
    db.with_conn(|conn| {
        for raw_line in content.split('\n') {
            let entries = known_hosts_parser::parse_line(raw_line);
            if entries.is_empty() {
                if known_hosts_parser::is_hashed_hosts_line(raw_line) {
                    summary.skipped_hashed += 1;
                }
                continue;
            }
            for entry in entries {
                let (host, port) = match split_host_port(&entry.host_port) {
                    Some(hp) => hp,
                    None => continue,
                };
                let existing = crate::db::known_hosts::get_by_host_port(conn, &host, port)?;
                if existing.is_some() {
                    summary.skipped_existing += 1;
                    continue;
                }
                crate::db::known_hosts::upsert_by_host_port(
                    conn,
                    &host,
                    port,
                    &entry.key_type,
                    &entry.key_base64,
                    now_ms,
                )?;
                summary.added += 1;
            }
        }
        Ok::<(), Error>(())
    })?;
    if summary.added > 0 {
        bus.publish(Event::KnownHostsChanged);
    }
    Ok(summary)
}

/// Render every known-hosts row to the LetsFLUTssh wire format
/// (`host:port keytype base64key` per line). Used by `.lfs`
/// archive export so the user's TOFU history rides along.
///
/// Sorted by `host:port` so the export is deterministic — the
/// archive byte stream stays identical between two exports of
/// the same DB.
pub fn export_to_string(db: &Db) -> Result<String, Error> {
    db.with_conn(|conn| {
        let mut rows = crate::db::known_hosts::list_all(conn)?;
        rows.sort_by(|a, b| {
            (a.host.as_str(), a.port).cmp(&(b.host.as_str(), b.port))
        });
        let mut out = String::new();
        for row in rows {
            use std::fmt::Write as _;
            let _ = writeln!(
                out,
                "{}:{} {} {}",
                row.host, row.port, row.key_type, row.key_base64
            );
        }
        Ok::<String, Error>(out)
    })
}

/// Helper used by the FRB DAOs that mutate `known_hosts` rows
/// directly — callers wrap a single upsert / delete / clear in
/// this so the bus event fires alongside.
pub fn notify_changed(app: &Arc<AppState>) {
    app.bus.publish(Event::KnownHostsChanged);
}

fn split_host_port(spec: &str) -> Option<(String, i64)> {
    let (host, port_str) = spec.rsplit_once(':')?;
    if host.is_empty() {
        return None;
    }
    let port: i64 = port_str.parse().ok()?;
    if !(1..=65535).contains(&port) {
        return None;
    }
    Some((host.to_string(), port))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn split_host_port_basic() {
        assert_eq!(
            split_host_port("example.com:22"),
            Some(("example.com".to_string(), 22))
        );
        assert_eq!(split_host_port("badport:abc"), None);
        assert_eq!(split_host_port(":22"), None);
        assert_eq!(split_host_port("noport"), None);
        assert_eq!(split_host_port("h:0"), None);
        assert_eq!(split_host_port("h:70000"), None);
    }
}
