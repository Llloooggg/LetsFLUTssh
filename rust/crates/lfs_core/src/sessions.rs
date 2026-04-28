//! Helper hooks around the sessions / folders DAOs.
//!
//! The canonical session table lives in `lfs_core::db::sessions`
//! (rusqlite + SQLCipher); the Dart `SessionStore` mirrors it as
//! a UI snapshot. This module exposes [`notify_changed`] so the
//! FRB DAO wrappers can publish a single `SessionsChanged` event
//! after every successful write — sessions, folders, M2M
//! junctions, secret-slot updates, all coalesced under one
//! topic the Dart shim subscribes to.
//!
//! No state-bearing struct yet — the manager actor with cache +
//! folder cascade lives behind a separate arc. Today this is
//! the Rust-side push that lets the Dart cache stay in sync
//! without polling.

use std::sync::Arc;

use crate::app::AppState;
use crate::bus::Event;

/// Publish [`Event::SessionsChanged`] on the global bus. Called
/// by the FRB layer after every mutating session / folder DAO so
/// the Dart `SessionStore` re-fetches in one microtask-coalesced
/// reload rather than per-call.
pub fn notify_changed(app: &Arc<AppState>) {
    app.bus.publish(Event::SessionsChanged);
}

/// Searchable subset of a Session — the four fields the UI search
/// bar matches against. Kept small on purpose so callers can
/// project their full Session list once and feed the projection to
/// [`filter_sessions`] without round-tripping credentials over FFI.
#[derive(Debug, Clone)]
pub struct SearchableSession {
    pub id: String,
    pub label: String,
    pub folder: String,
    pub host: String,
    pub user: String,
}

/// Validate the minimum required fields for storage. Returns a
/// human-readable error message string when the session is not
/// storable, `None` when it is.
///
/// Mirrors `Session.validate` Dart-side. Credentials are not part
/// of the check — a session can be stored without a password and
/// completed later (the UI's `isValid` is the connect-time check).
#[must_use]
pub fn validate_session_fields(host: &str, port: u16, user: &str) -> Option<String> {
    if host.trim().is_empty() {
        return Some("Host is required".to_string());
    }
    if !(1..=65535).contains(&port) {
        return Some("Port must be 1-65535".to_string());
    }
    if user.trim().is_empty() {
        return Some("Username is required".to_string());
    }
    None
}

/// Count sessions whose `folder` field equals [`folder_path`] or
/// sits under `{folder_path}/`. Used by the folder context-menu
/// confirm dialog ("Delete folder containing N sessions?") and by
/// the empty-folder reconciliation pass after a bulk import.
#[must_use]
pub fn count_in_folder(session_folders: &[String], folder_path: &str) -> usize {
    if folder_path.is_empty() {
        return session_folders.iter().filter(|f| f.is_empty()).count();
    }
    let prefix = format!("{folder_path}/");
    session_folders
        .iter()
        .filter(|f| f.as_str() == folder_path || f.starts_with(&prefix))
        .count()
}

/// Case-insensitive substring search across [`label`, `folder`,
/// `host`, `user`]. Returns matched ids in input order, so callers
/// can re-key their domain list and preserve the user's sort.
///
/// Empty query returns every id. The grammar is the canonical
/// version of the predicate three callers used to maintain
/// (`SessionStore.search`, `sessionListProvider`, ad-hoc filter in
/// the QR-export dialog) — keep new search surfaces routing here so
/// the four-field rule does not drift.
#[must_use]
pub fn filter_sessions(items: &[SearchableSession], query: &str) -> Vec<String> {
    if query.is_empty() {
        return items.iter().map(|s| s.id.clone()).collect();
    }
    let q = query.to_lowercase();
    items
        .iter()
        .filter(|s| {
            s.label.to_lowercase().contains(&q)
                || s.folder.to_lowercase().contains(&q)
                || s.host.to_lowercase().contains(&q)
                || s.user.to_lowercase().contains(&q)
        })
        .map(|s| s.id.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make(id: &str, label: &str, folder: &str, host: &str, user: &str) -> SearchableSession {
        SearchableSession {
            id: id.to_string(),
            label: label.to_string(),
            folder: folder.to_string(),
            host: host.to_string(),
            user: user.to_string(),
        }
    }

    #[test]
    fn empty_query_returns_every_id_in_order() {
        let items = vec![
            make("a", "Frontend", "Production", "1.2.3.4", "root"),
            make("b", "Backend", "Production", "5.6.7.8", "deploy"),
        ];
        assert_eq!(filter_sessions(&items, ""), vec!["a", "b"]);
    }

    #[test]
    fn matches_label_case_insensitively() {
        let items = vec![
            make("a", "Frontend Web", "Production/EU", "x", "u"),
            make("b", "API Backend", "Production/US", "x", "u"),
        ];
        assert_eq!(filter_sessions(&items, "frontend"), vec!["a"]);
        assert_eq!(filter_sessions(&items, "FRONTEND"), vec!["a"]);
    }

    #[test]
    fn matches_folder() {
        let items = vec![
            make("a", "x", "Production/EU", "x", "u"),
            make("b", "x", "Production/US", "x", "u"),
        ];
        assert_eq!(filter_sessions(&items, "us"), vec!["b"]);
    }

    #[test]
    fn matches_host() {
        let items = vec![
            make("a", "x", "y", "alpha.example.com", "u"),
            make("b", "x", "y", "beta.example.com", "u"),
        ];
        assert_eq!(filter_sessions(&items, "alpha"), vec!["a"]);
    }

    #[test]
    fn matches_user() {
        let items = vec![
            make("a", "x", "y", "h", "deploy"),
            make("b", "x", "y", "h", "root"),
        ];
        assert_eq!(filter_sessions(&items, "deploy"), vec!["a"]);
    }

    #[test]
    fn returns_all_matches_in_input_order() {
        let items = vec![
            make("a", "alpha", "y", "h", "u"),
            make("b", "beta", "y", "h", "u"),
            make("c", "alpha-2", "y", "h", "u"),
        ];
        assert_eq!(filter_sessions(&items, "alpha"), vec!["a", "c"]);
    }

    #[test]
    fn returns_empty_when_no_match() {
        let items = vec![make("a", "foo", "bar", "baz", "qux")];
        assert!(filter_sessions(&items, "missing").is_empty());
    }

    #[test]
    fn validate_accepts_well_formed_session() {
        assert!(validate_session_fields("example.com", 22, "root").is_none());
    }

    #[test]
    fn validate_rejects_blank_host() {
        assert_eq!(
            validate_session_fields("   ", 22, "root").as_deref(),
            Some("Host is required")
        );
    }

    #[test]
    fn validate_rejects_blank_user() {
        assert_eq!(
            validate_session_fields("h", 22, "  ").as_deref(),
            Some("Username is required")
        );
    }

    #[test]
    fn validate_rejects_zero_port() {
        assert_eq!(
            validate_session_fields("h", 0, "u").as_deref(),
            Some("Port must be 1-65535")
        );
    }

    #[test]
    fn validate_accepts_port_at_max_boundary() {
        assert!(validate_session_fields("h", 65535, "u").is_none());
    }

    #[test]
    fn count_in_folder_matches_exact() {
        let folders = vec![
            "Production".to_string(),
            "Production".to_string(),
            "Staging".to_string(),
        ];
        assert_eq!(count_in_folder(&folders, "Production"), 2);
    }

    #[test]
    fn count_in_folder_includes_children_under_prefix() {
        let folders = vec![
            "Production".to_string(),
            "Production/EU".to_string(),
            "Production/US".to_string(),
            "Staging".to_string(),
        ];
        assert_eq!(count_in_folder(&folders, "Production"), 3);
    }

    #[test]
    fn count_in_folder_skips_partial_prefix_matches() {
        // "ProductionExtra" must not count when we ask about
        // "Production" — the slash boundary matters.
        let folders = vec!["Production".to_string(), "ProductionExtra".to_string()];
        assert_eq!(count_in_folder(&folders, "Production"), 1);
    }

    #[test]
    fn count_in_folder_root_path_counts_root_sessions() {
        let folders = vec![String::new(), "Production".to_string(), String::new()];
        assert_eq!(count_in_folder(&folders, ""), 2);
    }
}
