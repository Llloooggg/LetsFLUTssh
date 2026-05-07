//! Helper hooks around the sessions / folders DAOs + the
//! Rust-side session registry.
//!
//! The canonical session table lives in `lfs_core::db::sessions`
//! (rusqlite + SQLCipher); [`Registry`] caches the read view
//! (session list + folder map + empty / collapsed paths) so
//! callers can render against a stable snapshot without
//! re-walking the DB on every read.
//!
//! [`notify_changed`] is the Rust-side push that lets the Dart
//! cache stay in sync without polling — the FRB DAO wrappers
//! publish a single `SessionsChanged` event after every
//! successful write (sessions, folders, M2M junctions, secret-
//! slot updates, all coalesced under one topic the Dart shim
//! subscribes to).
//!
//! Both halves coexist with the legacy Dart `SessionStore`
//! during the migration window: Registry hydrates from the same
//! DAOs the Dart store calls, so a future cutover where Dart
//! subscribes to `Registry::view` instead of running its own
//! `_doLoad` is a flip rather than a rewrite.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, RwLock};

use crate::app::AppState;
use crate::bus::Event;
use crate::db::folders::FolderRow;
use crate::db::sessions::SessionRow;
use crate::db::Db;
use crate::error::Error;
use crate::folder_path;

/// Publish [`Event::SessionsChanged`] on the global bus. Called
/// by the FRB layer after every mutating session / folder DAO so
/// the Dart `SessionStore` re-fetches in one microtask-coalesced
/// reload rather than per-call.
pub fn notify_changed(app: &Arc<AppState>) {
    app.bus.publish(Event::SessionsChanged);
}

/// Reload the in-process session registry from disk and publish a
/// [`Event::SessionsChanged`] event on the bus. Best-effort —
/// reload failures are logged via the registry's own contract
/// (the prior view is preserved); the bus event still fires so
/// the Dart cache reloads even when the registry drift didn't
/// take. Idempotent in the sense that a callsite that fires it
/// twice in a row produces two bus events but identical state.
pub fn reload_and_notify(app: &Arc<AppState>) {
    if let Some(db) = app.db() {
        let _ = app.sessions_registry.reload(&db);
    }
    notify_changed(app);
}

/// Wrap a DAO `Result<T, _>` write outcome — when the result is
/// `Ok(_)`, fire [`reload_and_notify`] against the running
/// `AppState`; on `Err` do nothing so a failed write doesn't
/// trigger a downstream re-fetch storm against state that didn't
/// actually change. The FRB DAO shims used to inline the
/// `app::instance()` walk + reload + notify_changed dance at
/// every callsite (15+ sites in `lfs_frb::api::db`) — that's
/// orchestration that belongs in the core, not duplicated
/// through every bridge shim. Lives here so the shim stays a
/// one-liner.
pub fn notify_sessions_on_ok<T>(res: &Result<T, String>) {
    if res.is_ok() {
        reload_and_notify(&crate::app::instance());
    }
}

/// Same shape as [`notify_sessions_on_ok`] but the notify only
/// fires when the wrapped value satisfies a caller-supplied
/// predicate. Used by DAO endpoints that return `0 / N rows
/// affected` — `n > 0` is the typical predicate so a no-op delete
/// (id resolves to nothing) doesn't waste a bus event.
pub fn notify_sessions_on_ok_when<T>(res: &Result<T, String>, when: impl Fn(&T) -> bool) {
    if let Ok(v) = res {
        if when(v) {
            reload_and_notify(&crate::app::instance());
        }
    }
}

/// Cached read view of the sessions / folders cache. Mirrors what
/// `SessionStore._doLoad` Dart-side builds:
///
/// * `sessions` — every row from `db_sessions_list_all`. Carries
///   credential columns; the in-memory Dart cache used to clear
///   them before keeping the row, but the Registry keeps them
///   because (a) they live one process anyway, and (b) the
///   future `connect_*_with_secret` path will want them resolved
///   inside Rust.
/// * `folders` — id → `FolderRow` map; rebuilt on every reload.
/// * `empty_folders` — paths with no sessions pointing at them
///   (UI renders them with a placeholder).
/// * `collapsed_folders` — paths whose row carries `collapsed`.
///
/// Cloned by `Registry::snapshot`; callers receive an owned copy
/// they can read without holding the lock.
#[derive(Debug, Clone, Default)]
pub struct RegistryView {
    pub sessions: Vec<SessionRow>,
    pub folders: BTreeMap<String, FolderRow>,
    pub empty_folders: BTreeSet<String>,
    pub collapsed_folders: BTreeSet<String>,
}

/// Process-singleton sessions registry. Wraps a [`RegistryView`]
/// behind an `RwLock` so reads (UI snapshots) don't block other
/// reads. Only the FRB layer + the future `SessionsChanged`
/// dispatcher touch the writer.
///
/// Read-side only at this slice — no mutating helpers; all
/// writes still go through the existing
/// `db_sessions_*` / `db_folders_*` FRB endpoints, which call
/// `notify_changed` and schedule a `reload(db)` here on the next
/// hand-off slice.
pub struct Registry {
    inner: RwLock<RegistryView>,
}

impl Default for Registry {
    fn default() -> Self {
        Self::new()
    }
}

impl Registry {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(RegistryView::default()),
        }
    }

    /// Rebuild the cached view from the live DB. Walks
    /// `sessions::list_all` + `folders::list_all` once, then
    /// derives `empty_folders` + `collapsed_folders` via the
    /// pure helpers in `lfs_core::folder_path`.
    ///
    /// On error the existing view is preserved — callers see
    /// stale state rather than an empty cache + a fault.
    pub fn reload(&self, db: &Db) -> Result<(), Error> {
        let view = db.with_conn(|conn| {
            let sessions = crate::db::sessions::list_all(conn)?;
            let folder_rows = crate::db::folders::list_all(conn)?;
            let folders: BTreeMap<String, FolderRow> =
                folder_rows.into_iter().map(|f| (f.id.clone(), f)).collect();
            let used_folder_ids: std::collections::HashSet<String> = sessions
                .iter()
                .filter_map(|s| s.folder_id.clone())
                .collect();
            let empty_folders: BTreeSet<String> =
                folder_path::derive_empty_folders(&folders, &used_folder_ids)
                    .into_iter()
                    .collect();
            let collapsed_folders: BTreeSet<String> =
                folder_path::derive_collapsed_folders(&folders)
                    .into_iter()
                    .collect();
            Ok::<_, Error>(RegistryView {
                sessions,
                folders,
                empty_folders,
                collapsed_folders,
            })
        })?;
        let mut g = self.inner.write().unwrap_or_else(|e| e.into_inner());
        *g = view;
        Ok(())
    }

    /// Cheap snapshot — clones the current view so the caller can
    /// read without holding the read lock. The clone cost scales
    /// linearly with session / folder count; in practice the user
    /// session list is bounded at ≤1k entries so the clone runs
    /// in microseconds.
    #[must_use]
    pub fn snapshot(&self) -> RegistryView {
        self.inner.read().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Number of sessions cached. Cheap — read lock only, no clone.
    #[must_use]
    pub fn session_count(&self) -> usize {
        self.inner
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .sessions
            .len()
    }

    /// Cached session ids whose folder path equals [`folder_path`]
    /// **exactly** (no prefix match — use [`count_in_folder`] for
    /// the prefix-aware count). Empty path yields root-level
    /// sessions. Reads off the cached view; no DB round-trip.
    #[must_use]
    pub fn ids_by_exact_folder(&self, folder_path: &str) -> Vec<String> {
        let view = self.inner.read().unwrap_or_else(|e| e.into_inner());
        view.sessions
            .iter()
            .filter(|s| {
                let path = match &s.folder_id {
                    Some(fid) => folder_path::build_folder_path(fid, &view.folders),
                    None => String::new(),
                };
                path == folder_path
            })
            .map(|s| s.id.clone())
            .collect()
    }

    /// Distinct, sorted folder paths referenced by any cached
    /// session. Drops empty paths (sessions at root). Reads off
    /// the cached view; no DB round-trip.
    #[must_use]
    pub fn distinct_folders(&self) -> Vec<String> {
        let view = self.inner.read().unwrap_or_else(|e| e.into_inner());
        let folders: Vec<String> = view
            .sessions
            .iter()
            .map(|s| match &s.folder_id {
                Some(fid) => folder_path::build_folder_path(fid, &view.folders),
                None => String::new(),
            })
            .collect();
        distinct_folders(&folders)
    }

    /// Filter cached session ids using the four-field substring
    /// search predicate (label / folder / host / user, case-
    /// insensitive). Reads off the cached view; no DB round-trip
    /// and no Dart-side projection round-trip.
    ///
    /// Returns matched ids in the cache's natural order so the
    /// Dart caller can re-key its display list against the
    /// returned set without sorting.
    #[must_use]
    pub fn filter_ids(&self, query: &str) -> Vec<String> {
        let view = self.inner.read().unwrap_or_else(|e| e.into_inner());
        let projected: Vec<SearchableSession> = view
            .sessions
            .iter()
            .map(|s| SearchableSession {
                id: s.id.clone(),
                label: s.label.clone(),
                folder: match &s.folder_id {
                    Some(fid) => folder_path::build_folder_path(fid, &view.folders),
                    None => String::new(),
                },
                host: s.host.clone(),
                user: s.user.clone(),
            })
            .collect();
        filter_sessions(&projected, query)
    }

    /// Count sessions whose folder path equals [`folder_path`] or
    /// sits under `{folder_path}/`. Empty path counts root-level
    /// sessions. Reads off the cached view — no DB round-trip.
    ///
    /// The folder paths come from walking the cached folder map,
    /// so the count reflects the live snapshot the FRB writers
    /// already kept current.
    #[must_use]
    pub fn count_in_folder(&self, folder_path: &str) -> usize {
        let view = self.inner.read().unwrap_or_else(|e| e.into_inner());
        let folders: Vec<String> = view
            .sessions
            .iter()
            .map(|s| match &s.folder_id {
                Some(fid) => folder_path::build_folder_path(fid, &view.folders),
                None => String::new(),
            })
            .collect();
        count_in_folder(&folders, folder_path)
    }
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

/// Distinct, sorted folder names referenced by [`session_folders`].
/// Drops empty paths (sessions at root) — only named folders
/// surface. Used by the SessionStore.folders() accessor and any
/// future "folder picker" autocomplete that needs the live set.
#[must_use]
pub fn distinct_folders(session_folders: &[String]) -> Vec<String> {
    let mut set: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for f in session_folders {
        if !f.is_empty() {
            set.insert(f.clone());
        }
    }
    set.into_iter().collect()
}

/// Generate a label that does not collide with any entry in
/// [`taken`]. Returns [`base`] when free; otherwise tries
/// `"{base} (copy)"`, then `"{base} (copy 2)"`, `"{base} (copy 3)"`,
/// … until a free slot is found.
///
/// Empty [`base`] passes through unchanged — callers (the duplicate-
/// key importer, the duplicate-session path) expect "no label" to
/// stay empty rather than growing a `(copy)` tag onto nothing.
///
/// Mirrors `KeyStore._uniqueLabel` Dart-side and is the canonical
/// source-of-truth for the dedup grammar that also appears in the
/// session-duplicate / snippet-duplicate flows.
#[must_use]
pub fn unique_label(base: &str, taken: &std::collections::HashSet<String>) -> String {
    if base.is_empty() || !taken.contains(base) {
        return base.to_string();
    }
    let copy = format!("{base} (copy)");
    if !taken.contains(&copy) {
        return copy;
    }
    let mut n = 2_u32;
    loop {
        let candidate = format!("{base} (copy {n})");
        if !taken.contains(&candidate) {
            return candidate;
        }
        n += 1;
    }
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

    #[test]
    fn unique_label_passes_through_when_base_is_free() {
        let taken: std::collections::HashSet<String> = ["foo".into()].into();
        assert_eq!(unique_label("bar", &taken), "bar");
    }

    #[test]
    fn unique_label_appends_copy_marker_when_base_taken() {
        let taken: std::collections::HashSet<String> = ["foo".into()].into();
        assert_eq!(unique_label("foo", &taken), "foo (copy)");
    }

    #[test]
    fn unique_label_appends_copy_n_when_copy_taken() {
        let taken: std::collections::HashSet<String> = ["foo".into(), "foo (copy)".into()].into();
        assert_eq!(unique_label("foo", &taken), "foo (copy 2)");
    }

    #[test]
    fn unique_label_walks_until_free_slot_found() {
        let taken: std::collections::HashSet<String> = [
            "foo".into(),
            "foo (copy)".into(),
            "foo (copy 2)".into(),
            "foo (copy 3)".into(),
        ]
        .into();
        assert_eq!(unique_label("foo", &taken), "foo (copy 4)");
    }

    #[test]
    fn unique_label_keeps_empty_base_empty() {
        // The duplicate-key import path passes through entries with
        // no label; `unique_label("", _)` must not produce
        // " (copy)" — empty in, empty out.
        let taken: std::collections::HashSet<String> = ["foo".into()].into();
        assert_eq!(unique_label("", &taken), "");
    }

    #[test]
    fn distinct_folders_drops_empty_dedups_and_sorts() {
        let folders = vec![
            "Production".to_string(),
            String::new(),
            "Staging".to_string(),
            "Production".to_string(),
            String::new(),
            "Production/EU".to_string(),
        ];
        assert_eq!(
            distinct_folders(&folders),
            vec![
                "Production".to_string(),
                "Production/EU".to_string(),
                "Staging".to_string(),
            ]
        );
    }

    #[test]
    fn distinct_folders_returns_empty_when_every_session_is_at_root() {
        let folders = vec![String::new(), String::new()];
        assert!(distinct_folders(&folders).is_empty());
    }

    fn build_in_memory_db() -> Db {
        use crate::db::bootstrap_schema;
        use rusqlite::Connection as RusqliteConn;
        let conn = RusqliteConn::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    #[test]
    fn registry_starts_with_empty_view() {
        let r = Registry::new();
        let view = r.snapshot();
        assert!(view.sessions.is_empty());
        assert!(view.folders.is_empty());
        assert!(view.empty_folders.is_empty());
        assert!(view.collapsed_folders.is_empty());
        assert_eq!(r.session_count(), 0);
    }

    #[test]
    fn registry_reload_hydrates_session_and_folder_view() {
        let db = build_in_memory_db();
        // Folder + child session.
        db.with_conn(|c| {
            crate::db::folders::upsert(
                c,
                &FolderRow {
                    id: "f1".into(),
                    name: "Production".into(),
                    parent_id: None,
                    sort_order: 0,
                    collapsed: false,
                    created_at_ms: 0,
                },
            )?;
            crate::db::folders::upsert(
                c,
                &FolderRow {
                    id: "f2".into(),
                    name: "EU".into(),
                    parent_id: Some("f1".into()),
                    sort_order: 0,
                    collapsed: true,
                    created_at_ms: 0,
                },
            )?;
            crate::db::sessions::upsert(
                c,
                &SessionRow {
                    id: "s1".into(),
                    label: "web".into(),
                    folder_id: Some("f1".into()),
                    host: "h".into(),
                    port: 22,
                    user: "u".into(),
                    auth_type: "password".into(),
                    password: String::new(),
                    key_path: String::new(),
                    key_data: String::new(),
                    key_id: None,
                    passphrase: String::new(),
                    sort_order: 0,
                    notes: String::new(),
                    last_connected_at_ms: None,
                    extras: "{}".into(),
                    via_session_id: None,
                    via_host: None,
                    via_port: None,
                    via_user: None,
                    created_at_ms: 0,
                    updated_at_ms: 0,
                },
            )?;
            Ok::<_, Error>(())
        })
        .unwrap();

        let r = Registry::new();
        r.reload(&db).unwrap();
        let view = r.snapshot();

        assert_eq!(view.sessions.len(), 1);
        assert_eq!(view.sessions[0].id, "s1");
        assert_eq!(view.folders.len(), 2);
        // f1 has a session — should not appear in empty_folders.
        // f2 has no session — should appear as "Production/EU".
        assert!(!view.empty_folders.contains("Production"));
        assert!(view.empty_folders.contains("Production/EU"));
        // f2 is collapsed.
        assert!(view.collapsed_folders.contains("Production/EU"));
    }

    #[test]
    fn registry_reload_preserves_view_on_subsequent_calls() {
        let db = build_in_memory_db();
        let r = Registry::new();
        // Empty DB → empty view; reload a couple times to confirm
        // idempotence on the empty case.
        r.reload(&db).unwrap();
        r.reload(&db).unwrap();
        assert_eq!(r.session_count(), 0);
    }

    #[test]
    fn registry_filter_ids_uses_four_field_predicate_against_cache() {
        let db = build_in_memory_db();
        db.with_conn(|c| {
            crate::db::folders::upsert(
                c,
                &FolderRow {
                    id: "f1".into(),
                    name: "Production".into(),
                    parent_id: None,
                    sort_order: 0,
                    collapsed: false,
                    created_at_ms: 0,
                },
            )?;
            for (id, label, folder, host, user) in [
                ("a", "Frontend", Some("f1"), "alpha.example.com", "root"),
                ("b", "Backend", None, "beta.example.com", "deploy"),
            ] {
                crate::db::sessions::upsert(
                    c,
                    &SessionRow {
                        id: id.into(),
                        label: label.into(),
                        folder_id: folder.map(String::from),
                        host: host.into(),
                        port: 22,
                        user: user.into(),
                        auth_type: "password".into(),
                        password: String::new(),
                        key_path: String::new(),
                        key_data: String::new(),
                        key_id: None,
                        passphrase: String::new(),
                        sort_order: 0,
                        notes: String::new(),
                        last_connected_at_ms: None,
                        extras: "{}".into(),
                        via_session_id: None,
                        via_host: None,
                        via_port: None,
                        via_user: None,
                        created_at_ms: 0,
                        updated_at_ms: 0,
                    },
                )?;
            }
            Ok::<_, Error>(())
        })
        .unwrap();

        let r = Registry::new();
        r.reload(&db).unwrap();

        // Match by label.
        assert_eq!(r.filter_ids("frontend"), vec!["a"]);
        // Match by folder (only `a` is under Production).
        assert_eq!(r.filter_ids("production"), vec!["a"]);
        // Match by host substring.
        assert_eq!(r.filter_ids("beta"), vec!["b"]);
        // Match by user.
        assert_eq!(r.filter_ids("deploy"), vec!["b"]);
        // Empty query returns every id.
        let all = r.filter_ids("");
        assert!(all.contains(&"a".to_string()) && all.contains(&"b".to_string()));
    }

    #[test]
    fn registry_count_in_folder_walks_cached_view() {
        let db = build_in_memory_db();
        db.with_conn(|c| {
            crate::db::folders::upsert(
                c,
                &FolderRow {
                    id: "f_prod".into(),
                    name: "Production".into(),
                    parent_id: None,
                    sort_order: 0,
                    collapsed: false,
                    created_at_ms: 0,
                },
            )?;
            crate::db::folders::upsert(
                c,
                &FolderRow {
                    id: "f_eu".into(),
                    name: "EU".into(),
                    parent_id: Some("f_prod".into()),
                    sort_order: 0,
                    collapsed: false,
                    created_at_ms: 0,
                },
            )?;
            for (id, folder) in [
                ("s_root", None),
                ("s_prod", Some("f_prod")),
                ("s_eu", Some("f_eu")),
            ] {
                crate::db::sessions::upsert(
                    c,
                    &SessionRow {
                        id: id.into(),
                        label: id.into(),
                        folder_id: folder.map(String::from),
                        host: "h".into(),
                        port: 22,
                        user: "u".into(),
                        auth_type: "password".into(),
                        password: String::new(),
                        key_path: String::new(),
                        key_data: String::new(),
                        key_id: None,
                        passphrase: String::new(),
                        sort_order: 0,
                        notes: String::new(),
                        last_connected_at_ms: None,
                        extras: "{}".into(),
                        via_session_id: None,
                        via_host: None,
                        via_port: None,
                        via_user: None,
                        created_at_ms: 0,
                        updated_at_ms: 0,
                    },
                )?;
            }
            Ok::<_, Error>(())
        })
        .unwrap();

        let r = Registry::new();
        r.reload(&db).unwrap();
        // Production includes its child + the EU child = 2 entries.
        assert_eq!(r.count_in_folder("Production"), 2);
        // Empty path → root-level only.
        assert_eq!(r.count_in_folder(""), 1);
        // Unknown path → 0.
        assert_eq!(r.count_in_folder("Staging"), 0);
    }
}
