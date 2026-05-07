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
//!
//! [`PromptRegistry`] adds the TOFU prompt protocol: russh's
//! `check_server_key` consults the DB, fires a
//! `KnownHostPromptRequest` event when the host is unknown or the
//! offered key changed, and awaits a `KnownHostPromptResponse`
//! command via a per-prompt `tokio::sync::oneshot`. The Dart UI
//! subscribes to the `KnownHosts` topic, surfaces the host-key
//! dialog, and dispatches the response back. The handler then
//! persists the entry (when accepted) and resumes the handshake.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::Mutex;

use tokio::sync::oneshot;

use crate::app::AppState;
use crate::bus::{Event, KnownHostPromptKind};
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
        rows.sort_by(|a, b| (a.host.as_str(), a.port).cmp(&(b.host.as_str(), b.port)));
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

/// Process-singleton registry of pending TOFU prompts, keyed by
/// caller-allocated prompt id (UUIDv4). Owned by [`AppState`].
/// The russh handler creates a oneshot, parks the receiver under
/// the prompt id, publishes the request event, and awaits the
/// receiver. The Dart UI dispatches the response command; the
/// FRB layer's command dispatcher wakes the receiver via
/// [`PromptRegistry::resolve`].
pub struct PromptRegistry {
    inner: Mutex<HashMap<String, oneshot::Sender<bool>>>,
}

impl PromptRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(HashMap::new()),
        }
    }

    /// Park a fresh oneshot under `prompt_id` and return the
    /// receiver. Caller awaits the receiver after publishing the
    /// matching `KnownHostPromptRequest` event.
    pub fn register(&self, prompt_id: String) -> oneshot::Receiver<bool> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(prompt_id, tx);
        rx
    }

    /// Resolve a pending prompt with the user's `accepted` choice.
    /// Idempotent — a missing prompt id (already resolved, or the
    /// awaiting side timed out) is a no-op. Returns `true` when a
    /// receiver was actually woken.
    pub fn resolve(&self, prompt_id: &str, accepted: bool) -> bool {
        let sender = self
            .inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(prompt_id);
        match sender {
            Some(tx) => tx.send(accepted).is_ok(),
            None => false,
        }
    }

    /// Drop a pending prompt without resolving — used by handlers
    /// that abandon the await (timeout, peer drop, shutdown).
    pub fn cancel(&self, prompt_id: &str) {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(prompt_id);
    }

    pub fn pending_count(&self) -> usize {
        self.inner.lock().unwrap_or_else(|e| e.into_inner()).len()
    }
}

impl Default for PromptRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Outcome of [`check_host`] — what the russh handler should do
/// next. `Accepted` means the offered key matched the stored
/// entry; `Unknown` / `Changed` should escalate to a TOFU prompt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HostCheckResult {
    Accepted,
    Unknown,
    Changed { stored_key_b64: String },
}

/// Look up `(host, port)` in the known_hosts table and compare
/// against the offered (`key_type`, `key_base64`).  Pure read —
/// callers persist the new entry separately after the user's
/// response if they accept.
pub fn check_host(
    db: &Db,
    host: &str,
    port: i64,
    key_type: &str,
    key_base64: &str,
) -> Result<HostCheckResult, Error> {
    db.with_conn(|conn| {
        let row = crate::db::known_hosts::get_by_host_port(conn, host, port)?;
        let result = match row {
            None => HostCheckResult::Unknown,
            Some(r) if r.key_type == key_type && r.key_base64 == key_base64 => {
                HostCheckResult::Accepted
            }
            Some(r) => HostCheckResult::Changed {
                stored_key_b64: r.key_base64,
            },
        };
        Ok::<HostCheckResult, Error>(result)
    })
}

/// Map a [`HostCheckResult`] mismatch to the matching
/// [`KnownHostPromptKind`] for the bus event.
pub fn prompt_kind_for(result: &HostCheckResult) -> Option<KnownHostPromptKind> {
    match result {
        HostCheckResult::Unknown => Some(KnownHostPromptKind::NewHost),
        HostCheckResult::Changed { .. } => Some(KnownHostPromptKind::KeyChanged),
        HostCheckResult::Accepted => None,
    }
}

/// Split the canonical wire-format `host:port` (or `[ipv6]:port`)
/// into the `(host, port)` pair populated into `known_hosts.host`
/// and `known_hosts.port` columns. Brackets are stripped on the
/// IPv6 branch so the DB row stores the bare host literal — a
/// connect-time lookup for `host="::1", port=2222` (russh hands us
/// the unbracketed form) hits the right row. See
/// [`crate::known_hosts_parser::normalise_host_spec`] for the
/// matching writer.
fn split_host_port(spec: &str) -> Option<(String, i64)> {
    let (host_part, port_str) = if let Some(rest) = spec.strip_prefix('[') {
        // Bracketed IPv6 — `[host]:port`. The right-most `]` ends
        // the host segment; the tail must be `:port`. Do NOT use
        // `rsplit_once(':')` here — IPv6 literals contain colons
        // and the rightmost one inside the brackets would beat
        // the port separator.
        let close = rest.find(']')?;
        let host = &rest[..close];
        let tail = &rest[close + 1..];
        let port_str = tail.strip_prefix(':')?;
        (host.to_string(), port_str)
    } else {
        let (host, port_str) = spec.rsplit_once(':')?;
        (host.to_string(), port_str)
    };
    if host_part.is_empty() {
        return None;
    }
    let port: i64 = port_str.parse().ok()?;
    if !(1..=65535).contains(&port) {
        return None;
    }
    Some((host_part, port))
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

    #[test]
    fn split_host_port_ipv6_bracketed() {
        // Regression: `[::1]:2222` must round-trip as `(::1, 2222)`.
        // Pre-fix the writer emitted `::1:2222` and `rsplit_once(':')`
        // produced `(":1", 2222)` — orphaning every IPv6 known-hosts
        // row at connect time.
        assert_eq!(
            split_host_port("[::1]:2222"),
            Some(("::1".to_string(), 2222))
        );
        assert_eq!(
            split_host_port("[2001:db8::1]:22"),
            Some(("2001:db8::1".to_string(), 22))
        );
    }

    #[test]
    fn split_host_port_ipv6_rejects_unclosed_bracket() {
        assert_eq!(split_host_port("[::1:2222"), None);
        assert_eq!(split_host_port("[::1]"), None);
        assert_eq!(split_host_port("[::1]:abc"), None);
    }
}
