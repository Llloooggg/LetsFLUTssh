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
/// (the cached view is preserved); the bus event still fires so
/// the Dart cache reloads even when the registry drift didn't
/// take. Idempotent in the sense that a callsite that fires it
/// twice in a row produces two bus events but identical state.
pub fn reload_and_notify(app: &Arc<AppState>) {
    if let Some(db) = app.db() {
        let _ = app.sessions_registry.reload(&db);
    }
    notify_changed(app);
}

/// Cached read view of the sessions / folders cache. Mirrors what
/// `SessionStore._doLoad` Dart-side builds:
///
/// * `sessions` — every row from `db_sessions_list_all`. Carries
///   credential columns; the Registry keeps them because (a)
///   they live in one process anyway, and (b) the
///   `connect_*_with_secret` path resolves them inside Rust.
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
    /// Per-session-id WebDAV / S3 credential-presence flags
    /// synthesised off the detail-table joins by
    /// [`crate::db::sessions::list_all_with_flags`]. The session-tree
    /// UI reads this map to render the "credentials not set"
    /// warning for incomplete WebDAV / S3 rows without an N+1
    /// lookup hop. Entries are present for every session id in
    /// [`sessions`]; SSH rows still resolve to `{false, false}`
    /// because the LEFT JOIN returns no detail row for them.
    pub credential_flags: BTreeMap<String, crate::db::sessions::SessionCredentialFlags>,
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
            let session_rows = crate::db::sessions::list_all_with_flags(conn)?;
            let folder_rows = crate::db::folders::list_all(conn)?;
            let folders: BTreeMap<String, FolderRow> =
                folder_rows.into_iter().map(|f| (f.id.clone(), f)).collect();
            let used_folder_ids: std::collections::HashSet<String> = session_rows
                .iter()
                .filter_map(|(s, _)| s.folder_id.clone())
                .collect();
            let empty_folders: BTreeSet<String> =
                folder_path::derive_empty_folders(&folders, &used_folder_ids)
                    .into_iter()
                    .collect();
            let collapsed_folders: BTreeSet<String> =
                folder_path::derive_collapsed_folders(&folders)
                    .into_iter()
                    .collect();
            // Unzip the (row, flags) pairs into the two-collection
            // shape the snapshot exposes. The flags map keys by
            // session_id so the Dart consumer can look up a row by
            // id without scanning a parallel Vec.
            let mut sessions = Vec::with_capacity(session_rows.len());
            let mut credential_flags = BTreeMap::new();
            for (row, flags) in session_rows {
                credential_flags.insert(row.id.clone(), flags);
                sessions.push(row);
            }
            Ok::<_, Error>(RegistryView {
                sessions,
                folders,
                empty_folders,
                collapsed_folders,
                credential_flags,
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

/// Session authentication method — the app-side type carried on
/// every saved session. Wire values match the Dart enum names
/// exactly (`"password"`, `"key"`, `"keyWithPassword"`, `"agent"`)
/// so the DB column round-trips byte-identically across the
/// Rust ↔ Dart boundary.
///
/// Note: [`crate::ssh_config::AuthType`] is a different, narrower
/// 2-variant enum used by the OpenSSH `~/.ssh/config` importer —
/// it models the subset of methods that grammar surfaces
/// (password / key) and stays separate so its wire shape never
/// drifts with the app-side enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AuthType {
    /// Plain password — held in `SessionAuth.password`, encrypted at
    /// rest. Default when a row is missing / unknown.
    Password,
    /// SSH key — `keyId` references the key store; `keyPath` may
    /// also carry an on-disk path.
    Key,
    /// SSH key whose unlock requires an additional password — the
    /// `password` field carries the passphrase prompt unlock value
    /// the connect path injects separately from the key bytes.
    KeyWithPassword,
    /// Defer credential discovery to a running ssh-agent — the
    /// session carries no key id / inline PEM / password.
    Agent,
}

impl AuthType {
    /// Wire value persisted in the `sessions.auth_type` column and
    /// the canonical-JSON `auth_type` key. Byte-identical to the
    /// corresponding Dart enum's `.name` getter.
    #[must_use]
    pub fn wire_name(self) -> &'static str {
        match self {
            AuthType::Password => "password",
            AuthType::Key => "key",
            AuthType::KeyWithPassword => "keyWithPassword",
            AuthType::Agent => "agent",
        }
    }

    /// Parse a wire value. Unknown / empty strings fall back to
    /// [`AuthType::Password`] so a future variant added in a newer
    /// build can never brick a legacy row — the row simply renders
    /// as `password` until the build catches up.
    #[must_use]
    pub fn from_wire_name(s: &str) -> Self {
        match s {
            "key" => AuthType::Key,
            "keyWithPassword" => AuthType::KeyWithPassword,
            "agent" => AuthType::Agent,
            _ => AuthType::Password,
        }
    }
}

/// Transport kind — selects between the SSH/SFTP shell + file
/// browser, the WebDAV-backed file browser, and the S3-compatible
/// object-store browser. Wire values match
/// `crate::db::sessions::SESSION_KIND_*` and the Dart `.name`
/// getter on the corresponding enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SessionKind {
    /// SSH + SFTP (default).
    Ssh,
    /// WebDAV (Nextcloud, ownCloud, Apache mod_dav, IIS, Synology
    /// DSM, …).
    Webdav,
    /// S3-compatible object store (AWS S3, MinIO, Wasabi, Backblaze
    /// B2-S3, Cloudflare R2, DigitalOcean Spaces, Scaleway, …).
    S3,
}

impl SessionKind {
    /// Wire value persisted in the `sessions.kind` column and the
    /// canonical-JSON `kind` key. Matches the
    /// `crate::db::sessions::SESSION_KIND_*` constants byte for
    /// byte.
    #[must_use]
    pub fn wire_name(self) -> &'static str {
        match self {
            SessionKind::Ssh => crate::db::sessions::SESSION_KIND_SSH,
            SessionKind::Webdav => crate::db::sessions::SESSION_KIND_WEBDAV,
            SessionKind::S3 => crate::db::sessions::SESSION_KIND_S3,
        }
    }

    /// Parse a wire value. `None`, the empty string, or any
    /// unknown tag falls back to [`SessionKind::Ssh`] so a future
    /// schema bump that adds a kind the current build does not
    /// understand renders the row as SSH until the build catches
    /// up — never bricks the session list.
    #[must_use]
    pub fn from_wire_name(s: Option<&str>) -> Self {
        match s {
            Some(v) if v == crate::db::sessions::SESSION_KIND_WEBDAV => SessionKind::Webdav,
            Some(v) if v == crate::db::sessions::SESSION_KIND_S3 => SessionKind::S3,
            _ => SessionKind::Ssh,
        }
    }
}

/// Validate the minimum required fields for storage. Returns a
/// human-readable error message string when the session is not
/// storable, `None` when it is.
///
/// Sole owner of the storable-field grammar — the Dart caller
/// passes its `Session.port` (`int`) in verbatim and Rust handles
/// the full 1..=65535 range check including out-of-range negatives
/// / overflows. Credentials are not part of the check; a session
/// can be stored without a password and completed later (the UI's
/// `isValid` is the connect-time check).
#[must_use]
pub fn validate_session_fields(host: &str, port: i32, user: &str) -> Option<String> {
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

/// One target parsed from an SSH-style `[user@]host[:port]` string.
/// Backs the session-edit dialog's smart-paste "Connect to" field —
/// the user types `root@example.com:22` (or any subset) and the
/// dialog splits the result into the host / port / user controllers
/// the existing form already drives.
///
/// `user` and `port` are optional because the smart-paste field
/// accepts every legitimate subset: bare host, `host:port`,
/// `user@host`, `user@host:port`, plus bracketed IPv6 literals
/// (`[::1]`, `[::1]:22`). When the parser cannot fill a slot the
/// caller keeps its existing default (port 22, empty user).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SshTarget {
    pub host: String,
    pub port: Option<u16>,
    pub user: Option<String>,
}

/// Parse a smart-paste connect string into its host / port / user
/// components. Returns `None` for inputs that cannot be coerced to a
/// non-empty host with the same validation envelope as
/// [`parse_connect_uri`](crate::deeplink::parse_connect_uri): host
/// length ≤ 253, user length ≤ 256, port in 1..=65535, no `/`, no
/// `\\`, no C0/C1 control characters.
///
/// Bracketed IPv6 literals are recognised verbatim — `[::1]` and
/// `[::1]:22` both parse, with the brackets stripped from the host
/// slot so the connect path stores `::1`.
#[must_use]
pub fn parse_ssh_target(input: &str) -> Option<SshTarget> {
    let s = input.trim();
    if s.is_empty() {
        return None;
    }
    // user@host split — rfind so `user@with@at.example` keeps the
    // last `@` as the separator; OpenSSH rejects `@` inside usernames
    // by convention but the in-app smart-paste only needs the same
    // tolerance as `ssh user@host:port` on the command line.
    let (user, rest) = if let Some(at) = s.rfind('@') {
        let candidate = &s[..at];
        if candidate.is_empty() || candidate.len() > 256 || contains_invalid(candidate) {
            return None;
        }
        (Some(candidate.to_string()), &s[at + 1..])
    } else {
        (None, s)
    };
    let (host, port_part) = split_host_port(rest)?;
    if host.is_empty() || host.len() > 253 || contains_invalid(host) {
        return None;
    }
    let port = match port_part {
        None | Some("") => None,
        Some(p) => match p.parse::<u32>() {
            Ok(n) if (1..=65535).contains(&n) => Some(n as u16),
            _ => return None,
        },
    };
    Some(SshTarget {
        host: host.to_string(),
        port,
        user,
    })
}

/// Pull host + optional port out of the post-`@` remainder. Splits
/// on the last `:` for plain hosts (so `host:22` works); recognises
/// bracketed IPv6 literals (`[::1]`, `[::1]:22`) by stripping the
/// brackets and inspecting the trailing `:` only after the closing
/// `]` so the colons inside the address are not mistaken for the
/// host/port separator.
fn split_host_port(rest: &str) -> Option<(&str, Option<&str>)> {
    if let Some(stripped) = rest.strip_prefix('[') {
        let close = stripped.find(']')?;
        let host = &stripped[..close];
        let tail = &stripped[close + 1..];
        if tail.is_empty() {
            return Some((host, None));
        }
        let port = tail.strip_prefix(':')?;
        Some((host, Some(port)))
    } else if let Some(colon) = rest.rfind(':') {
        Some((&rest[..colon], Some(&rest[colon + 1..])))
    } else {
        Some((rest, None))
    }
}

/// Reject any byte that would corrupt downstream storage / shell
/// interpolation: C0/C1 control chars (`\0`, CR, LF, BEL, ESC),
/// path separators (`/`, `\\`). Mirrors the deeplink parser's
/// `contains_control_char` envelope so the smart-paste field and
/// the deep-link connect path share one validation contract.
fn contains_invalid(s: &str) -> bool {
    s.bytes()
        .any(|b| b < 0x20 || (0x7F..=0x9F).contains(&b) || b == b'/' || b == b'\\')
}

/// One vertex in the session-edit dialog's ProxyJump-cycle probe.
/// Carries the session id and its current `via_session_id` (the
/// "saved-session" bastion target) so [`detect_proxy_cycle`] can
/// walk the chain forward without re-reading the DB. Sessions with
/// no saved bastion carry `via_session_id = None`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProxyRef {
    pub session_id: String,
    pub via_session_id: Option<String>,
}

/// Return `true` when picking `candidate_id` as the ProxyJump
/// bastion for the session identified by `seed_id` would create a
/// cycle through the saved-session graph.
///
/// Walks the chain forward from `candidate_id` (each step follows
/// the candidate's own `via_session_id`); a cycle exists when the
/// walk reaches `seed_id` before terminating. A pre-existing cycle
/// in the data unrelated to `seed_id` (`A → B → A` already on disk)
/// returns `false` so the probe stays a tight "would THIS edit
/// introduce a loop through me" question — orphan loops are the
/// connect path's concern at dial time.
///
/// `seed_id = None` is the new-session branch: a session that does
/// not exist yet cannot be re-entered, so every candidate is safe.
/// Direct self-reference (`candidate_id == seed_id`) is the
/// shortest cycle and trips on the first iteration.
#[must_use]
pub fn detect_proxy_cycle(seed_id: Option<&str>, candidate_id: &str, chain: &[ProxyRef]) -> bool {
    let Some(seed) = seed_id else {
        return false;
    };
    let lookup: std::collections::HashMap<&str, Option<&str>> = chain
        .iter()
        .map(|r| (r.session_id.as_str(), r.via_session_id.as_deref()))
        .collect();
    let mut visited = std::collections::HashSet::new();
    let mut current = Some(candidate_id);
    while let Some(node) = current {
        if !visited.insert(node) {
            return false;
        }
        if node == seed {
            return true;
        }
        current = lookup.get(node).copied().flatten();
    }
    false
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
/// Empty query returns every id. Single owner of the search
/// predicate — `SessionStore.search`, `sessionListProvider`, and
/// the QR-export filter all route through here so the four-field
/// rule does not drift.
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
    fn auth_type_wire_round_trip_every_variant() {
        for v in [
            AuthType::Password,
            AuthType::Key,
            AuthType::KeyWithPassword,
            AuthType::Agent,
        ] {
            assert_eq!(AuthType::from_wire_name(v.wire_name()), v);
        }
    }

    #[test]
    fn auth_type_unknown_wire_falls_back_to_password() {
        assert_eq!(AuthType::from_wire_name(""), AuthType::Password);
        assert_eq!(
            AuthType::from_wire_name("does-not-exist"),
            AuthType::Password
        );
    }

    #[test]
    fn auth_type_wire_names_match_dart_enum_dot_name() {
        // Byte-identity guard — these strings round-trip the DB
        // column and the canonical-JSON payload, so a typo would
        // brick every saved row.
        assert_eq!(AuthType::Password.wire_name(), "password");
        assert_eq!(AuthType::Key.wire_name(), "key");
        assert_eq!(AuthType::KeyWithPassword.wire_name(), "keyWithPassword");
        assert_eq!(AuthType::Agent.wire_name(), "agent");
    }

    #[test]
    fn session_kind_wire_round_trip_every_variant() {
        for v in [SessionKind::Ssh, SessionKind::Webdav, SessionKind::S3] {
            assert_eq!(SessionKind::from_wire_name(Some(v.wire_name())), v);
        }
    }

    #[test]
    fn session_kind_unknown_wire_falls_back_to_ssh() {
        assert_eq!(SessionKind::from_wire_name(None), SessionKind::Ssh);
        assert_eq!(SessionKind::from_wire_name(Some("")), SessionKind::Ssh);
        assert_eq!(
            SessionKind::from_wire_name(Some("future-tag")),
            SessionKind::Ssh
        );
    }

    #[test]
    fn session_kind_wire_names_match_db_constants() {
        assert_eq!(
            SessionKind::Ssh.wire_name(),
            crate::db::sessions::SESSION_KIND_SSH
        );
        assert_eq!(
            SessionKind::Webdav.wire_name(),
            crate::db::sessions::SESSION_KIND_WEBDAV
        );
        assert_eq!(
            SessionKind::S3.wire_name(),
            crate::db::sessions::SESSION_KIND_S3
        );
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
    fn validate_rejects_negative_port() {
        // Out-of-range negatives surface the same message a zero
        // port does — the grammar tolerates the full `i32` range
        // and the user sees one consistent verdict regardless of
        // how the misuse got there.
        assert_eq!(
            validate_session_fields("h", -1, "u").as_deref(),
            Some("Port must be 1-65535")
        );
    }

    #[test]
    fn validate_rejects_port_above_max() {
        assert_eq!(
            validate_session_fields("h", 70_000, "u").as_deref(),
            Some("Port must be 1-65535")
        );
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
        use crate::db::{bootstrap_schema, Connection};
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
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
                    kind: crate::db::sessions::SESSION_KIND_SSH.into(),
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
                        kind: crate::db::sessions::SESSION_KIND_SSH.into(),
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
                        kind: crate::db::sessions::SESSION_KIND_SSH.into(),
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

    #[test]
    fn parse_ssh_target_bare_host_returns_host_only() {
        let t = parse_ssh_target("example.com").expect("bare host parses");
        assert_eq!(t.host, "example.com");
        assert_eq!(t.user, None);
        assert_eq!(t.port, None);
    }

    #[test]
    fn parse_ssh_target_user_at_host() {
        let t = parse_ssh_target("root@example.com").expect("user@host parses");
        assert_eq!(t.host, "example.com");
        assert_eq!(t.user.as_deref(), Some("root"));
        assert_eq!(t.port, None);
    }

    #[test]
    fn parse_ssh_target_host_colon_port() {
        let t = parse_ssh_target("example.com:2222").expect("host:port parses");
        assert_eq!(t.host, "example.com");
        assert_eq!(t.user, None);
        assert_eq!(t.port, Some(2222));
    }

    #[test]
    fn parse_ssh_target_full_form() {
        let t = parse_ssh_target("alice@example.com:2222").expect("full form parses");
        assert_eq!(t.host, "example.com");
        assert_eq!(t.user.as_deref(), Some("alice"));
        assert_eq!(t.port, Some(2222));
    }

    #[test]
    fn parse_ssh_target_ipv6_bracketed_no_port() {
        let t = parse_ssh_target("[::1]").expect("bracketed IPv6 parses");
        assert_eq!(t.host, "::1");
        assert_eq!(t.port, None);
    }

    #[test]
    fn parse_ssh_target_ipv6_bracketed_with_port() {
        let t = parse_ssh_target("root@[2001:db8::1]:22").expect("user + IPv6 + port");
        assert_eq!(t.host, "2001:db8::1");
        assert_eq!(t.user.as_deref(), Some("root"));
        assert_eq!(t.port, Some(22));
    }

    #[test]
    fn parse_ssh_target_trims_surrounding_whitespace() {
        let t = parse_ssh_target("  root@example.com:22  ").expect("trimmed input parses");
        assert_eq!(t.host, "example.com");
        assert_eq!(t.user.as_deref(), Some("root"));
        assert_eq!(t.port, Some(22));
    }

    #[test]
    fn parse_ssh_target_rejects_empty() {
        assert!(parse_ssh_target("").is_none());
        assert!(parse_ssh_target("   ").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_zero_and_overflow_port() {
        assert!(parse_ssh_target("h:0").is_none());
        assert!(parse_ssh_target("h:65536").is_none());
        assert!(parse_ssh_target("h:99999999").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_non_numeric_port() {
        assert!(parse_ssh_target("h:abc").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_control_chars_in_host() {
        assert!(parse_ssh_target("evil\rhost").is_none());
        assert!(parse_ssh_target("evil\nhost").is_none());
        assert!(parse_ssh_target("evil\0host").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_path_separators_in_host() {
        assert!(parse_ssh_target("a/b").is_none());
        assert!(parse_ssh_target("a\\b").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_empty_user_part() {
        assert!(parse_ssh_target("@host").is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_oversize_host() {
        let host = "a".repeat(254);
        assert!(parse_ssh_target(&host).is_none());
    }

    #[test]
    fn parse_ssh_target_rejects_oversize_user() {
        let user = "u".repeat(257);
        let input = format!("{}@host", user);
        assert!(parse_ssh_target(&input).is_none());
    }

    fn pr(id: &str, via: Option<&str>) -> ProxyRef {
        ProxyRef {
            session_id: id.to_string(),
            via_session_id: via.map(str::to_string),
        }
    }

    #[test]
    fn detect_proxy_cycle_new_session_never_loops() {
        // No seed id (new-session branch) — every candidate is safe.
        let chain = vec![pr("a", None), pr("b", Some("a"))];
        assert!(!detect_proxy_cycle(None, "a", &chain));
        assert!(!detect_proxy_cycle(None, "b", &chain));
    }

    #[test]
    fn detect_proxy_cycle_direct_self_trips() {
        let chain = vec![pr("a", None)];
        assert!(detect_proxy_cycle(Some("a"), "a", &chain));
    }

    #[test]
    fn detect_proxy_cycle_two_step_cycle_trips() {
        // Editing A; A wants to go via B; B already goes via A.
        let chain = vec![pr("a", None), pr("b", Some("a"))];
        assert!(detect_proxy_cycle(Some("a"), "b", &chain));
    }

    #[test]
    fn detect_proxy_cycle_three_step_cycle_trips() {
        // A → B → C → A: picking C while editing A trips the probe
        // because the chain walks C → A which is the seed.
        let chain = vec![pr("a", None), pr("b", Some("a")), pr("c", Some("b"))];
        assert!(detect_proxy_cycle(Some("a"), "c", &chain));
    }

    #[test]
    fn detect_proxy_cycle_safe_chain_does_not_trip() {
        // A → B → C, picking C while editing A is fine — chain
        // walks C, then None (C has no via).
        let chain = vec![pr("a", Some("b")), pr("b", Some("c")), pr("c", None)];
        assert!(!detect_proxy_cycle(Some("a"), "c", &chain));
    }

    #[test]
    fn detect_proxy_cycle_orphan_loop_does_not_trip_for_unrelated_seed() {
        // Pre-existing loop B → C → B in the data; editing A wants
        // to go via B. The probe is asking "would THIS edit close a
        // loop through me" — orphan loops elsewhere stay the connect
        // path's problem, not the dialog's.
        let chain = vec![pr("a", None), pr("b", Some("c")), pr("c", Some("b"))];
        assert!(!detect_proxy_cycle(Some("a"), "b", &chain));
    }

    #[test]
    fn detect_proxy_cycle_missing_via_target_is_safe() {
        // Candidate's via points at a deleted session — the chain
        // terminates with None lookup. Not a cycle.
        let chain = vec![pr("b", Some("ghost"))];
        assert!(!detect_proxy_cycle(Some("a"), "b", &chain));
    }
}
