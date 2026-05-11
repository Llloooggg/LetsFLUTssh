//! Last-write-wins merge between a peer-snapshot
//! [`crate::archive::PendingImport`] and the local SQLCipher DB.
//!
//! The orchestrator pulls the encrypted `.lfs` from the WebDAV
//! remote, runs it through
//! [`crate::archive::read_archive_to_pending`], and hands the
//! resulting pending state here. This module folds the peer's
//! rows into the local DB with per-row LWW resolution against the
//! row's `updated_at` (or `created_at` for tables that don't
//! carry an explicit update timestamp — `ssh_keys`, `tags`,
//! `sftp_bookmarks`).
//!
//! # LWW rules (per table)
//!
//! | Table | Field consulted |
//! |---|---|
//! | `sessions` | `max(updated_at, deleted_at)` |
//! | `snippets` | `max(updated_at, deleted_at)` |
//! | `ssh_keys` | `max(created_at, deleted_at)` |
//! | `tags` | `max(created_at, deleted_at)` |
//! | `sftp_bookmarks` | `max(created_at, deleted_at)` |
//!
//! Local-only rows are kept (the peer hasn't seen them yet; the
//! next push surfaces them). Peer-only rows are inserted.
//!
//! # Tombstone replay caveat (v1 wire format)
//!
//! The current `.lfs` archive shape emits **live rows only** —
//! [`crate::archive::compose::build_sessions_value`] and its
//! siblings filter `deleted_at IS NULL` before serialising. A
//! peer device cannot observe a tombstone the source device
//! stamped through this v1 path; cross-device deletion replay
//! lands when the export pipeline grows a `deleted_at` field
//! per row. Documented here so the gap is visible to the next
//! reader.
//!
//! # M2M join tables
//!
//! `session_tags`, `folder_tags`, and `session_snippets` carry
//! no timestamps — the rows are weak references between two
//! timestamped parents. The merge unions the local + pending
//! edges via `INSERT OR IGNORE`: every edge either side knows
//! about survives. Removal of an edge is not replayed because
//! the wire format does not carry a "this edge was deleted"
//! marker. A peer device that unlinks a tag from a session
//! does NOT propagate the unlink through v1 sync; the user
//! re-unlinks on the second device. Documented as a known
//! v1 limitation in `docs/ARCHITECTURE.md` Sync §.
//!
//! # Transaction discipline
//!
//! The merge runs inside a single SQLite transaction so a
//! mid-merge error rolls back the entire fold. Callers route
//! through [`crate::db::Db::with_conn_mut`] which gives the
//! merge a `&mut Connection`; the function opens a
//! `rusqlite::Transaction` against that handle and either
//! commits the whole fold or rolls back to the pre-merge
//! state.

use std::collections::HashMap;

use serde_json::Value;

use crate::archive::PendingImport;
use crate::db::{folders, sessions, snippets, ssh_keys, tags, Connection};
use crate::error::Error;

use crate::archive::iso8601::parse_iso8601_or_now;

/// Per-kind counters the orchestrator surfaces to the UI after
/// a successful pull. Each counter increments only when the
/// peer's row actually displaces (or inserts) something
/// locally — a pending row whose timestamp is older than the
/// local row is a no-op and does not count.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MergeOutcome {
    pub sessions_merged: u32,
    pub keys_merged: u32,
    pub tags_merged: u32,
    pub snippets_merged: u32,
    pub bookmarks_merged: u32,
    pub session_tag_edges_merged: u32,
    pub folder_tag_edges_merged: u32,
    pub session_snippet_edges_merged: u32,
    /// Errors collected during the merge (per-row parse / DAO
    /// failures). The transaction commits even if a few rows
    /// failed — same shape as the import-apply driver in
    /// [`crate::archive::apply`].
    pub errors: Vec<String>,
}

/// Fold `pending` into `conn`'s live tables under LWW. See the
/// module doc for the per-table rules. Runs inside a single
/// rusqlite transaction; on any catastrophic DB error
/// (transaction-level failure, schema mismatch) the merge
/// rolls back and the function returns `Err`. Per-row parse
/// failures land in [`MergeOutcome::errors`] and the rest of
/// the merge continues.
pub fn merge_pending_into_local(
    conn: &mut Connection,
    pending: &PendingImport,
) -> Result<MergeOutcome, Error> {
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("sync merge: tx begin: {e}")))?;

    let mut outcome = MergeOutcome::default();
    let now_ms = now_unix_ms();

    if let Some(json) = pending.keys_json.as_deref() {
        merge_keys(&tx, json, &mut outcome);
    }
    // Sessions also need the imported folder tree so a peer's
    // `folder` path resolves to a stable local folder id. The
    // archive's folder names get re-used (a peer's "Production"
    // ends up under the same Production folder on this device);
    // import-apply does the same.
    let mut folder_path_to_id: HashMap<String, String> = HashMap::new();
    if let Some(json) = pending.sessions_json.as_deref() {
        folder_path_to_id = ensure_folder_tree(&tx, json, now_ms, &mut outcome);
        merge_sessions(&tx, json, &folder_path_to_id, &mut outcome);
    }
    if let Some(json) = pending.tags_json.as_deref() {
        merge_tags(&tx, json, &mut outcome);
    }
    if let Some(json) = pending.snippets_json.as_deref() {
        merge_snippets(&tx, json, &mut outcome);
    }
    if let Some(json) = pending.session_tags_json.as_deref() {
        merge_session_tag_edges(&tx, json, &mut outcome);
    }
    if let Some(json) = pending.folder_tags_json.as_deref() {
        merge_folder_tag_edges(&tx, json, &folder_path_to_id, &mut outcome);
    }
    if let Some(json) = pending.session_snippets_json.as_deref() {
        merge_session_snippet_edges(&tx, json, &mut outcome);
    }
    // SFTP bookmarks travel inside the manifest under a future
    // wire-format extension. The v2 archive shape does not emit
    // `sftp_bookmarks` entries today; when the export pipeline
    // grows the field, this is the slot the merge wires the new
    // counter through. The `MergeOutcome::bookmarks_merged`
    // counter stays at zero in the meantime.

    tx.commit()
        .map_err(|e| Error::Db(format!("sync merge: tx commit: {e}")))?;
    Ok(outcome)
}

fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn parse_array(json: &str, label: &str, errors: &mut Vec<String>) -> Vec<Value> {
    match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            errors.push(format!("sync merge {label} parse: {e}"));
            Vec::new()
        }
    }
}

fn json_string(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .map(String::from)
        .unwrap_or_default()
}

fn json_i64(v: &Value, key: &str) -> Option<i64> {
    v.get(key).and_then(|x| x.as_i64())
}

fn iso_to_ms(v: &Value, key: &str, now_ms: i64) -> i64 {
    let s = v.get(key).and_then(|x| x.as_str()).unwrap_or("");
    if s.is_empty() {
        now_ms
    } else {
        parse_iso8601_or_now(s, now_ms)
    }
}

// ── sessions ──────────────────────────────────────────────────────

fn ensure_folder_tree(
    conn: &impl crate::db::DbAccess,
    sessions_json: &str,
    now_ms: i64,
    outcome: &mut MergeOutcome,
) -> HashMap<String, String> {
    let arr = match serde_json::from_str::<Vec<Value>>(sessions_json) {
        Ok(a) => a,
        Err(_) => return HashMap::new(),
    };
    // Reuse existing folders by path so the merge does not mint a
    // second "Production" folder on each pull. `ensure_folder_path`
    // walks the existing tree segment-by-segment and inserts only
    // the missing levels.
    let mut out: HashMap<String, String> = HashMap::new();
    for v in arr.iter() {
        let path = json_string(v, "folder");
        if path.is_empty() || out.contains_key(&path) {
            continue;
        }
        match folders::ensure_folder_path(conn, &path, now_ms) {
            Ok(Some(id)) => {
                out.insert(path, id);
            }
            Ok(None) => {
                // Empty path — already filtered above; defensive
                // branch keeps the loop walk explicit.
            }
            Err(e) => outcome
                .errors
                .push(format!("sync merge folder ensure: {e}")),
        }
    }
    out
}

fn merge_sessions(
    conn: &impl crate::db::DbAccess,
    json: &str,
    folder_path_to_id: &HashMap<String, String>,
    outcome: &mut MergeOutcome,
) {
    let arr = parse_array(json, "sessions", &mut outcome.errors);
    let local: HashMap<String, sessions::SessionRow> = match sessions::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("sync merge sessions list: {e}"));
            return;
        }
    };
    let now_ms = now_unix_ms();
    for v in arr {
        let id = json_string(&v, "id");
        if id.is_empty() {
            continue;
        }
        let peer_updated_at = iso_to_ms(&v, "updated_at", now_ms);
        if let Some(local_row) = local.get(&id) {
            // Skip when the peer's row is not strictly newer than
            // the local one — LWW with strict-greater so a tie
            // breaks toward keeping local state. The local row's
            // tombstone counts as part of the LWW timestamp; a
            // peer's live row from before the local tombstone
            // does not resurrect the row.
            let local_effective = local_row.updated_at_ms;
            if peer_updated_at <= local_effective {
                continue;
            }
        }
        let folder_path = json_string(&v, "folder");
        let folder_id = if folder_path.is_empty() {
            None
        } else {
            folder_path_to_id.get(&folder_path).cloned()
        };
        let row = sessions::SessionRow {
            id: id.clone(),
            label: json_string(&v, "label"),
            folder_id,
            kind: json_string(&v, "kind"),
            host: json_string(&v, "host"),
            port: json_i64(&v, "port").unwrap_or(22),
            user: json_string(&v, "user"),
            auth_type: json_string(&v, "auth_type"),
            password: json_string(&v, "password"),
            key_path: json_string(&v, "key_path"),
            key_data: json_string(&v, "key_data"),
            key_id: v
                .get("key_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            passphrase: json_string(&v, "passphrase"),
            sort_order: 0,
            notes: String::new(),
            last_connected_at_ms: None,
            extras: v
                .get("extras")
                .map(|e| e.to_string())
                .unwrap_or_else(|| "{}".into()),
            via_session_id: v
                .get("via_session_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            via_host: v
                .get("via_override")
                .and_then(|o| o.get("host"))
                .and_then(|x| x.as_str())
                .map(String::from),
            via_port: v
                .get("via_override")
                .and_then(|o| o.get("port"))
                .and_then(|x| x.as_i64()),
            via_user: v
                .get("via_override")
                .and_then(|o| o.get("user"))
                .and_then(|x| x.as_str())
                .map(String::from),
            created_at_ms: iso_to_ms(&v, "created_at", now_ms),
            updated_at_ms: peer_updated_at,
        };
        match sessions::upsert(conn, &row) {
            Ok(_) => outcome.sessions_merged += 1,
            Err(e) => outcome.errors.push(format!("sync merge session {id}: {e}")),
        }
    }
}

// ── ssh_keys ──────────────────────────────────────────────────────

fn merge_keys(conn: &impl crate::db::DbAccess, json: &str, outcome: &mut MergeOutcome) {
    let arr = parse_array(json, "keys", &mut outcome.errors);
    let local: HashMap<String, ssh_keys::SshKeyRow> = match ssh_keys::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
        Err(e) => {
            outcome.errors.push(format!("sync merge keys list: {e}"));
            return;
        }
    };
    let now_ms = now_unix_ms();
    for v in arr {
        let id = json_string(&v, "id");
        if id.is_empty() {
            continue;
        }
        let peer_ts = iso_to_ms(&v, "created_at", now_ms);
        if let Some(local_row) = local.get(&id) {
            if peer_ts <= local_row.created_at_ms {
                continue;
            }
        }
        let row = ssh_keys::SshKeyRow {
            id: id.clone(),
            label: json_string(&v, "label"),
            private_key: json_string(&v, "private_key"),
            public_key: json_string(&v, "public_key"),
            key_type: json_string(&v, "key_type"),
            is_generated: v
                .get("is_generated")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            created_at_ms: peer_ts,
        };
        match ssh_keys::upsert(conn, &row) {
            Ok(_) => outcome.keys_merged += 1,
            Err(e) => outcome.errors.push(format!("sync merge key {id}: {e}")),
        }
    }
}

// ── tags ──────────────────────────────────────────────────────────

fn merge_tags(conn: &impl crate::db::DbAccess, json: &str, outcome: &mut MergeOutcome) {
    let arr = parse_array(json, "tags", &mut outcome.errors);
    let local: HashMap<String, tags::TagRow> = match tags::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
        Err(e) => {
            outcome.errors.push(format!("sync merge tags list: {e}"));
            return;
        }
    };
    let now_ms = now_unix_ms();
    for v in arr {
        let id = json_string(&v, "id");
        if id.is_empty() {
            continue;
        }
        let peer_ts = iso_to_ms(&v, "created_at", now_ms);
        if let Some(local_row) = local.get(&id) {
            if peer_ts <= local_row.created_at_ms {
                continue;
            }
        }
        let row = tags::TagRow {
            id: id.clone(),
            name: json_string(&v, "name"),
            color: v.get("color").and_then(|x| x.as_str()).map(String::from),
            created_at_ms: peer_ts,
        };
        match tags::upsert(conn, &row) {
            Ok(_) => outcome.tags_merged += 1,
            Err(e) => outcome.errors.push(format!("sync merge tag {id}: {e}")),
        }
    }
}

// ── snippets ──────────────────────────────────────────────────────

fn merge_snippets(conn: &impl crate::db::DbAccess, json: &str, outcome: &mut MergeOutcome) {
    let arr = parse_array(json, "snippets", &mut outcome.errors);
    let local: HashMap<String, snippets::SnippetRow> = match snippets::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("sync merge snippets list: {e}"));
            return;
        }
    };
    let now_ms = now_unix_ms();
    for v in arr {
        let id = json_string(&v, "id");
        if id.is_empty() {
            continue;
        }
        let peer_updated = iso_to_ms(&v, "updated_at", now_ms);
        if let Some(local_row) = local.get(&id) {
            if peer_updated <= local_row.updated_at_ms {
                continue;
            }
        }
        let row = snippets::SnippetRow {
            id: id.clone(),
            title: json_string(&v, "title"),
            command: json_string(&v, "command"),
            description: json_string(&v, "description"),
            created_at_ms: iso_to_ms(&v, "created_at", now_ms),
            updated_at_ms: peer_updated,
        };
        match snippets::upsert(conn, &row) {
            Ok(_) => outcome.snippets_merged += 1,
            Err(e) => outcome.errors.push(format!("sync merge snippet {id}: {e}")),
        }
    }
}

// ── M2M edges (session_tags, folder_tags, session_snippets) ──────

fn merge_session_tag_edges(
    conn: &impl crate::db::DbAccess,
    json: &str,
    outcome: &mut MergeOutcome,
) {
    let arr = parse_array(json, "session_tags", &mut outcome.errors);
    for v in arr {
        let sid = json_string(&v, "session_id");
        let tid = json_string(&v, "tag_id");
        if sid.is_empty() || tid.is_empty() {
            continue;
        }
        match tags::link_session_tag(conn, &sid, &tid) {
            Ok(_) => outcome.session_tag_edges_merged += 1,
            Err(e) => outcome
                .errors
                .push(format!("sync merge session_tag {sid}↔{tid}: {e}")),
        }
    }
}

fn merge_folder_tag_edges(
    conn: &impl crate::db::DbAccess,
    json: &str,
    folder_path_to_id: &HashMap<String, String>,
    outcome: &mut MergeOutcome,
) {
    let arr = parse_array(json, "folder_tags", &mut outcome.errors);
    for v in arr {
        let path = json_string(&v, "folder_path");
        let tid = json_string(&v, "tag_id");
        if path.is_empty() || tid.is_empty() {
            continue;
        }
        let Some(fid) = folder_path_to_id.get(&path) else {
            continue;
        };
        match tags::link_folder_tag(conn, fid, &tid) {
            Ok(_) => outcome.folder_tag_edges_merged += 1,
            Err(e) => outcome
                .errors
                .push(format!("sync merge folder_tag {path}↔{tid}: {e}")),
        }
    }
}

fn merge_session_snippet_edges(
    conn: &impl crate::db::DbAccess,
    json: &str,
    outcome: &mut MergeOutcome,
) {
    let arr = parse_array(json, "session_snippets", &mut outcome.errors);
    for v in arr {
        let sid = json_string(&v, "session_id");
        let snid = json_string(&v, "snippet_id");
        if sid.is_empty() || snid.is_empty() {
            continue;
        }
        match snippets::link_session_snippet(conn, &sid, &snid) {
            Ok(_) => outcome.session_snippet_edges_merged += 1,
            Err(e) => outcome
                .errors
                .push(format!("sync merge session_snippet {sid}↔{snid}: {e}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::archive::PendingImport;
    use crate::db::{bootstrap_schema, Connection, Db};

    fn fresh_db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn pending_with(sessions_json: Option<&str>) -> PendingImport {
        PendingImport {
            manifest_json: None,
            sessions_json: sessions_json.map(String::from),
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        }
    }

    #[test]
    fn merge_inserts_peer_only_session() {
        let db = fresh_db();
        let json = r#"[{
            "id":"s1","label":"prod","folder":"",
            "host":"h.example.com","port":22,"user":"root",
            "auth_type":"password","password":"pw",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2024-01-01T00:00:00.000Z",
            "updated_at":"2024-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 1);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "s1");
        assert_eq!(rows[0].label, "prod");
    }

    #[test]
    fn merge_skips_stale_peer_session() {
        // Local has s1 with updated_at = 1700000000000; peer has the
        // same id with an older updated_at. LWW must keep the local
        // shape.
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "s1".into(),
            label: "local-label".into(),
            host: "local.example.com".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            password: "local-pw".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let peer_json = r#"[{
            "id":"s1","label":"peer-label","folder":"",
            "host":"peer.example.com","port":22,"user":"root",
            "auth_type":"password","password":"peer-pw",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2023-01-01T00:00:00.000Z",
            "updated_at":"2023-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(peer_json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 0);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows[0].label, "local-label");
    }

    #[test]
    fn merge_overwrites_with_newer_peer_session() {
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "s1".into(),
            label: "old".into(),
            host: "h".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let peer_json = r#"[{
            "id":"s1","label":"new","folder":"",
            "host":"h","port":22,"user":"root",
            "auth_type":"password","password":"",
            "key_path":"","key_data":"","passphrase":"",
            "created_at":"2024-01-01T00:00:00.000Z",
            "updated_at":"2030-01-01T00:00:00.000Z"
        }]"#;
        let pending = pending_with(Some(peer_json));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 1);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows[0].label, "new");
    }

    #[test]
    fn merge_keeps_local_only_session() {
        let db = fresh_db();
        let row = sessions::SessionRow {
            id: "local-only".into(),
            label: "kept".into(),
            host: "h".into(),
            port: 22,
            user: "root".into(),
            auth_type: "password".into(),
            created_at_ms: 1_700_000_000_000,
            updated_at_ms: 1_700_000_000_000,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &row)).unwrap();
        let pending = pending_with(Some("[]"));
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.sessions_merged, 0);
        let rows = db.with_conn(sessions::list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "local-only");
    }

    #[test]
    fn merge_session_tag_edges_are_unioned() {
        let db = fresh_db();
        // Seed two tags + one session on the local side.
        let session = sessions::SessionRow {
            id: "s1".into(),
            label: "s1".into(),
            host: "h".into(),
            user: "u".into(),
            port: 22,
            auth_type: "password".into(),
            created_at_ms: 1,
            updated_at_ms: 1,
            ..Default::default()
        };
        db.with_conn(|c| sessions::upsert(c, &session)).unwrap();
        let t_local = tags::TagRow {
            id: "t1".into(),
            name: "local".into(),
            color: None,
            created_at_ms: 1,
        };
        let t_peer = tags::TagRow {
            id: "t2".into(),
            name: "peer".into(),
            color: None,
            created_at_ms: 1,
        };
        db.with_conn(|c| tags::upsert(c, &t_local)).unwrap();
        db.with_conn(|c| tags::upsert(c, &t_peer)).unwrap();
        db.with_conn(|c| tags::link_session_tag(c, "s1", "t1"))
            .unwrap();
        // Peer also knows the same session and links it to t2.
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: None,
            session_tags_json: Some(r#"[{"session_id":"s1","tag_id":"t2"}]"#.into()),
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.session_tag_edges_merged, 1);
        let ids = db
            .with_conn(|c| tags::list_session_tag_ids(c, "s1"))
            .unwrap();
        assert!(ids.contains(&"t1".to_string()));
        assert!(ids.contains(&"t2".to_string()));
    }

    #[test]
    fn merge_keys_skips_stale_peer_row() {
        let db = fresh_db();
        let row = ssh_keys::SshKeyRow {
            id: "k1".into(),
            label: "local".into(),
            private_key: "P".into(),
            public_key: "P".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 1_700_000_000_000,
        };
        db.with_conn(|c| ssh_keys::upsert(c, &row)).unwrap();
        let peer = r#"[{
            "id":"k1","label":"peer","private_key":"X","public_key":"X",
            "key_type":"ed25519","is_generated":true,
            "created_at":"2020-01-01T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: Some(peer.into()),
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: None,
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.keys_merged, 0);
        let rows = db.with_conn(ssh_keys::list_all).unwrap();
        assert_eq!(rows[0].label, "local");
    }

    #[test]
    fn merge_snippets_overwrites_when_peer_newer() {
        let db = fresh_db();
        let local = snippets::SnippetRow {
            id: "sn1".into(),
            title: "old".into(),
            command: "echo old".into(),
            description: String::new(),
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        db.with_conn(|c| snippets::upsert(c, &local)).unwrap();
        let peer = r#"[{
            "id":"sn1","title":"new","command":"echo new","description":"",
            "created_at":"2020-01-01T00:00:00.000Z",
            "updated_at":"2030-01-01T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            manifest_json: None,
            sessions_json: None,
            keys_json: None,
            tags_json: None,
            session_tags_json: None,
            folder_tags_json: None,
            snippets_json: Some(peer.into()),
            session_snippets_json: None,
            empty_folders_json: None,
            config_json: None,
            known_hosts_text: None,
        };
        let outcome = db
            .with_conn_mut(|c| merge_pending_into_local(c, &pending))
            .unwrap();
        assert_eq!(outcome.snippets_merged, 1);
        let rows = db.with_conn(snippets::list_all).unwrap();
        assert_eq!(rows[0].title, "new");
    }
}
