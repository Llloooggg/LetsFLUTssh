//! Import-apply driver — turns a [`PendingImport`] into committed
//! rows on `lfs_core.db`. Companion to the export composer in
//! [`super`]; the two halves bracket the wire-format contract for
//! the `.lfs` archive (and, via [`crate::archive_stage`], the
//! in-memory QR / paste-link / OpenSSH-config import flows).
//!
//! # Modes
//!
//! - **Merge** upserts every entry by id; collisions update
//!   the existing row's mutable columns. Known-hosts upsert by
//!   `(host, port)`; manager keys dedup by public-key fingerprint
//!   so a key already on disk does not double-land under the
//!   archive's id. Folder paths from `sessions.json` flatten into
//!   a per-archive folder tree; ids are minted fresh.
//! - **Replace** runs every stage inside a single sqlite
//!   transaction. For each enabled kind, the existing rows clear
//!   before the archive entries insert; a downstream parse error
//!   rolls the whole transaction back, so a botched import never
//!   leaves the DB half-overwritten. Junctions (`session_tags`,
//!   `session_snippets`) are cleared alongside their owning kinds
//!   (sessions / tags). Manager keys are intentionally NOT wiped
//!   on replace — the user's existing keys stay valid; the
//!   archive's keys merge by fingerprint as in merge mode (mirror
//!   of the Dart impl, kept to avoid surprising the user with
//!   "import lost my generated keys").
//!
//! # Failure model
//!
//! Per-row parse failures land in [`ApplyResult::errors`] and the
//! driver keeps going — a single corrupt session in a 500-host
//! archive does not abort the whole import. Hard sqlite errors
//! (lock contention, disk full) are pushed into the same vec; the
//! caller renders them as a non-blocking notice while the rest of
//! the archive lands.

use std::collections::{HashMap, HashSet};

use rusqlite::Connection;
use serde_json::Value;

use crate::db::{folders, known_hosts, sessions, snippets, ssh_keys, tags};
use crate::error::Error;

use super::iso8601::parse_iso8601_or_now;
use super::PendingImport;

/// Apply mode — `Merge` upserts, `Replace` clears the matching
/// kinds first inside a transaction so a partial failure rolls
/// back cleanly. Mirrors the Dart `ImportMode` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ImportMode {
    #[default]
    Merge,
    Replace,
}

/// What entries the apply driver should commit. Mirrors the
/// Dart `ImportOptions` toggle set; turning a flag off skips
/// every entry of that kind, even if the staged JSON carries it.
#[derive(Debug, Clone, Default)]
pub struct ApplyOptions {
    pub mode: ImportMode,
    pub apply_sessions: bool,
    pub apply_keys: bool,
    pub apply_tags: bool,
    pub apply_snippets: bool,
    pub apply_known_hosts: bool,
}

/// Aggregate counters the apply driver returns. `errors` carries
/// per-entry parse failures encountered along the way — apply
/// keeps going past a bad row so a single corrupt session in a
/// 500-host archive doesn't abort the whole import.
#[derive(Debug, Clone, Default)]
pub struct ApplyResult {
    pub sessions_applied: i64,
    pub keys_applied: i64,
    pub keys_skipped_dedup: i64,
    pub tags_applied: i64,
    pub snippets_applied: i64,
    pub known_hosts_applied: i64,
    pub folders_applied: i64,
    pub session_tags_applied: i64,
    pub session_snippets_applied: i64,
    pub errors: Vec<String>,
}

/// Apply a staged [`PendingImport`]. See module docs for mode
/// semantics; `now_ms` stamps any row that lacks a timestamp in
/// the archive (apply moment as the effective `created_at` /
/// `updated_at`).
pub fn apply_pending_import(
    conn: &mut Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    match options.mode {
        ImportMode::Merge => {
            let mut result = ApplyResult::default();
            run_apply(conn, pending, options, now_ms, &mut result);
            Ok(result)
        }
        ImportMode::Replace => {
            let tx = conn
                .transaction()
                .map_err(|e| Error::Io(format!("apply tx begin: {e}")))?;
            let mut result = ApplyResult::default();
            run_replace_clear(&tx, options, &mut result);
            run_apply(&tx, pending, options, now_ms, &mut result);
            tx.commit()
                .map_err(|e| Error::Io(format!("apply tx commit: {e}")))?;
            Ok(result)
        }
    }
}

/// Backwards-compatible alias. Existing callers route through
/// here; the new mode-aware entry point is
/// [`apply_pending_import`].
pub fn apply_pending_import_merge(
    conn: &Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    let mut result = ApplyResult::default();
    run_apply(conn, pending, options, now_ms, &mut result);
    Ok(result)
}

fn run_apply(
    conn: &Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    if options.apply_keys {
        if let Some(json) = pending.keys_json.as_deref() {
            apply_keys(conn, json, now_ms, result);
        }
    }
    // Apply folders + sessions together so session.folder_id
    // resolves through the freshly-inserted folder tree.
    let mut folder_path_to_id: HashMap<String, String> = HashMap::new();
    if options.apply_sessions {
        if let Some(json) = pending.sessions_json.as_deref() {
            folder_path_to_id = apply_folder_tree(conn, json, now_ms, result);
            apply_sessions(conn, json, &folder_path_to_id, now_ms, result);
        }
        if let Some(json) = pending.empty_folders_json.as_deref() {
            apply_empty_folders(conn, json, &mut folder_path_to_id, now_ms, result);
        }
    }
    if options.apply_tags {
        if let Some(json) = pending.tags_json.as_deref() {
            apply_tags(conn, json, now_ms, result);
        }
    }
    if options.apply_sessions && options.apply_tags {
        if let Some(json) = pending.session_tags_json.as_deref() {
            apply_session_tags(conn, json, result);
        }
    }
    if options.apply_snippets {
        if let Some(json) = pending.snippets_json.as_deref() {
            apply_snippets(conn, json, now_ms, result);
        }
    }
    if options.apply_sessions && options.apply_snippets {
        if let Some(json) = pending.session_snippets_json.as_deref() {
            apply_session_snippets(conn, json, result);
        }
    }
    if options.apply_known_hosts {
        if let Some(text) = pending.known_hosts_text.as_deref() {
            apply_known_hosts(conn, text, now_ms, result);
        }
    }
}

fn run_replace_clear(conn: &Connection, options: &ApplyOptions, result: &mut ApplyResult) {
    // Order matters — junctions clear before their owning rows
    // so the FKs stay sane. Each `delete_all` is idempotent on
    // an already-empty table.
    if options.apply_sessions {
        if let Err(e) = sessions::delete_all(conn) {
            result.errors.push(format!("replace clear sessions: {e}"));
        }
        if let Err(e) = folders::delete_all(conn) {
            result.errors.push(format!("replace clear folders: {e}"));
        }
    }
    if options.apply_tags {
        if let Err(e) = tags::delete_all(conn) {
            result.errors.push(format!("replace clear tags: {e}"));
        }
    }
    if options.apply_snippets {
        if let Err(e) = snippets::delete_all(conn) {
            result.errors.push(format!("replace clear snippets: {e}"));
        }
    }
    if options.apply_known_hosts {
        if let Err(e) = known_hosts::clear_all(conn) {
            result
                .errors
                .push(format!("replace clear known_hosts: {e}"));
        }
    }
}

fn apply_folder_tree(
    conn: &Connection,
    sessions_json: &str,
    now_ms: i64,
    result: &mut ApplyResult,
) -> HashMap<String, String> {
    use rand::RngCore;
    let arr = match serde_json::from_str::<Vec<Value>>(sessions_json) {
        Ok(a) => a,
        Err(_) => return HashMap::new(),
    };
    // Collect every distinct folder path from sessions.
    let mut paths: HashSet<String> = HashSet::new();
    for v in &arr {
        if let Some(p) = v.get("folder").and_then(|x| x.as_str()) {
            if !p.is_empty() {
                paths.insert(p.to_string());
            }
        }
    }
    let mut path_to_id: HashMap<String, String> = HashMap::new();
    let mut sort_order: i64 = 0;
    let mut sorted: Vec<String> = paths.into_iter().collect();
    sorted.sort();
    for path in sorted {
        // Walk from root → leaf so each segment's parent_id
        // resolves before the child lands.
        let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        let mut parent_id: Option<String> = None;
        let mut accum = String::new();
        for seg in segments {
            if !accum.is_empty() {
                accum.push('/');
            }
            accum.push_str(seg);
            if let Some(existing) = path_to_id.get(&accum) {
                parent_id = Some(existing.clone());
                continue;
            }
            let mut bytes = [0u8; 16];
            rand::rngs::OsRng.fill_bytes(&mut bytes);
            let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let row = folders::FolderRow {
                id: id.clone(),
                name: seg.to_string(),
                parent_id: parent_id.clone(),
                sort_order,
                collapsed: false,
                created_at_ms: now_ms,
            };
            sort_order += 1;
            match folders::upsert(conn, &row) {
                Ok(_) => {
                    result.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    result.errors.push(format!("folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
    path_to_id
}

fn apply_empty_folders(
    conn: &Connection,
    json: &str,
    path_to_id: &mut HashMap<String, String>,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    use rand::RngCore;
    let arr: Vec<String> = match serde_json::from_str(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("empty_folders parse: {e}"));
            return;
        }
    };
    let mut sort_order: i64 = path_to_id.len() as i64;
    for path in arr {
        if path.is_empty() || path_to_id.contains_key(&path) {
            continue;
        }
        let segments: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
        let mut parent_id: Option<String> = None;
        let mut accum = String::new();
        for seg in segments {
            if !accum.is_empty() {
                accum.push('/');
            }
            accum.push_str(seg);
            if let Some(existing) = path_to_id.get(&accum) {
                parent_id = Some(existing.clone());
                continue;
            }
            let mut bytes = [0u8; 16];
            rand::rngs::OsRng.fill_bytes(&mut bytes);
            let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let row = folders::FolderRow {
                id: id.clone(),
                name: seg.to_string(),
                parent_id: parent_id.clone(),
                sort_order,
                collapsed: false,
                created_at_ms: now_ms,
            };
            sort_order += 1;
            match folders::upsert(conn, &row) {
                Ok(_) => {
                    result.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    result
                        .errors
                        .push(format!("empty_folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
}

fn apply_session_tags(conn: &Connection, json: &str, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("session_tags parse: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        let tag_id = json_string(&v, "tag_id");
        if session_id.is_empty() || tag_id.is_empty() {
            continue;
        }
        match tags::link_session_tag(conn, &session_id, &tag_id) {
            Ok(_) => result.session_tags_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session_tag {session_id}↔{tag_id}: {e}")),
        }
    }
}

fn apply_session_snippets(conn: &Connection, json: &str, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("session_snippets parse: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        let snippet_id = json_string(&v, "snippet_id");
        if session_id.is_empty() || snippet_id.is_empty() {
            continue;
        }
        match snippets::link_session_snippet(conn, &session_id, &snippet_id) {
            Ok(_) => result.session_snippets_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session_snippet {session_id}↔{snippet_id}: {e}")),
        }
    }
}

fn json_string(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string()
}

fn json_i64(v: &Value, key: &str) -> i64 {
    v.get(key).and_then(|x| x.as_i64()).unwrap_or(0)
}

fn apply_sessions(
    conn: &Connection,
    json: &str,
    folder_path_to_id: &HashMap<String, String>,
    now_ms: i64,
    result: &mut ApplyResult,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("sessions parse: {e}"));
            return;
        }
    };
    for v in arr {
        // `via_override` (host/port/user trio) lives as a nested
        // object Dart-side; flatten back into the column trio.
        let (via_host, via_port, via_user) = match v.get("via_override") {
            Some(o) => (
                o.get("host").and_then(|x| x.as_str()).map(String::from),
                o.get("port").and_then(|x| x.as_i64()),
                o.get("user").and_then(|x| x.as_str()).map(String::from),
            ),
            None => (None, None, None),
        };
        let extras = v
            .get("extras")
            .filter(|x| x.is_object())
            .map(|x| x.to_string())
            .unwrap_or_default();
        // Resolve `folder` (path string) → folder_id via the
        // map [`apply_folder_tree`] built moments earlier.
        let folder_id = v
            .get("folder")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .and_then(|p| folder_path_to_id.get(p).cloned());
        let row = sessions::SessionRow {
            id: json_string(&v, "id"),
            label: json_string(&v, "label"),
            folder_id,
            host: json_string(&v, "host"),
            port: json_i64(&v, "port"),
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
            notes: json_string(&v, "notes"),
            last_connected_at_ms: None,
            extras,
            via_session_id: v
                .get("via_session_id")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            via_host,
            via_port,
            via_user,
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
            updated_at_ms: now_ms,
        };
        if row.id.is_empty() {
            result.errors.push("session row missing id".to_string());
            continue;
        }
        match sessions::upsert(conn, &row) {
            Ok(_) => result.sessions_applied += 1,
            Err(e) => result
                .errors
                .push(format!("session {} upsert: {e}", row.id)),
        }
    }
}

fn apply_keys(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("keys parse: {e}"));
            return;
        }
    };
    // Dedup against existing public-key fingerprints — exact
    // dupe lands the archive's id on top of the existing row,
    // but we count it as skipped so the UI summary reads
    // "added N, deduped M".
    let existing = match ssh_keys::list_metadata(conn) {
        Ok(v) => v,
        Err(e) => {
            result.errors.push(format!("keys metadata: {e}"));
            return;
        }
    };
    let existing_fps: HashSet<String> = existing
        .iter()
        .map(|m| m.public_fingerprint.clone())
        .filter(|s| !s.is_empty())
        .collect();
    for v in arr {
        let public_key = json_string(&v, "public_key");
        let fp = key_pub_fingerprint(&public_key);
        if !fp.is_empty() && existing_fps.contains(&fp) {
            result.keys_skipped_dedup += 1;
            continue;
        }
        let row = ssh_keys::SshKeyRow {
            id: json_string(&v, "id"),
            label: json_string(&v, "label"),
            private_key: json_string(&v, "private_key"),
            public_key,
            key_type: json_string(&v, "key_type"),
            is_generated: v
                .get("is_generated")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
        };
        if row.id.is_empty() {
            result.errors.push("key row missing id".to_string());
            continue;
        }
        match ssh_keys::upsert(conn, &row) {
            Ok(_) => result.keys_applied += 1,
            Err(e) => result.errors.push(format!("key {} upsert: {e}", row.id)),
        }
    }
}

fn apply_tags(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("tags parse: {e}"));
            return;
        }
    };
    for v in arr {
        let row = tags::TagRow {
            id: json_string(&v, "id"),
            name: json_string(&v, "name"),
            color: v
                .get("color")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
        };
        if row.id.is_empty() || row.name.is_empty() {
            continue;
        }
        match tags::upsert(conn, &row) {
            Ok(_) => result.tags_applied += 1,
            Err(e) => result.errors.push(format!("tag {} upsert: {e}", row.id)),
        }
    }
}

fn apply_snippets(conn: &Connection, json: &str, now_ms: i64, result: &mut ApplyResult) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            result.errors.push(format!("snippets parse: {e}"));
            return;
        }
    };
    for v in arr {
        let row = snippets::SnippetRow {
            id: json_string(&v, "id"),
            title: json_string(&v, "title"),
            command: json_string(&v, "command"),
            description: json_string(&v, "description"),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
            updated_at_ms: now_ms,
        };
        if row.id.is_empty() || row.title.is_empty() {
            continue;
        }
        match snippets::upsert(conn, &row) {
            Ok(_) => result.snippets_applied += 1,
            Err(e) => result
                .errors
                .push(format!("snippet {} upsert: {e}", row.id)),
        }
    }
}

fn apply_known_hosts(conn: &Connection, text: &str, now_ms: i64, result: &mut ApplyResult) {
    // Format: "host[:port] keytype key_base64" per line. Comments
    // (`#` lines) and blanks skipped. Default port 22 when the
    // host omits the colon — same fallback the Dart importer uses.
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.splitn(3, char::is_whitespace);
        let (Some(host_port), Some(key_type), Some(key_base64)) =
            (parts.next(), parts.next(), parts.next())
        else {
            continue;
        };
        let (host, port) = match host_port.rsplit_once(':') {
            Some((h, p)) => match p.parse::<i64>() {
                Ok(n) => (h, n),
                Err(_) => (host_port, 22),
            },
            None => (host_port, 22),
        };
        match known_hosts::upsert_by_host_port(conn, host, port, key_type, key_base64, now_ms) {
            Ok(_) => result.known_hosts_applied += 1,
            Err(e) => result.errors.push(format!("known_host {host}:{port}: {e}")),
        }
    }
}

/// Mirror the SHA-256-of-normalised-PEM fingerprint the
/// `ssh_keys::list_metadata` path computes — keep both sides
/// of the dedup compare reading the same hash. Empty input →
/// empty fingerprint so missing-public-key rows do not
/// false-match the dedup set.
fn key_pub_fingerprint(s: &str) -> String {
    use sha2::{Digest, Sha256};
    let normalised = s.replace("\r\n", "\n");
    let trimmed = normalised.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(trimmed.as_bytes());
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(digest.len() * 2);
    for b in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_db() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
        crate::db::bootstrap_schema(&conn).unwrap();
        conn
    }

    fn merge_all_options() -> ApplyOptions {
        ApplyOptions {
            mode: ImportMode::Merge,
            apply_sessions: true,
            apply_keys: true,
            apply_tags: true,
            apply_snippets: true,
            apply_known_hosts: true,
        }
    }

    fn empty_pending() -> PendingImport {
        PendingImport {
            manifest_json: None,
            sessions_json: None,
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
    fn apply_keys_inserts_fresh_row() {
        let conn = fresh_db();
        let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k1","label":"lap","private_key":"PRIV","public_key":"ssh-ed25519 AAAA","key_type":"ssh-ed25519","is_generated":true,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 1);
        let on_disk = ssh_keys::get(&conn, "k1").unwrap().unwrap();
        assert_eq!(on_disk.label, "lap");
        assert!(on_disk.is_generated);
    }

    #[test]
    fn apply_keys_dedups_existing_fingerprint() {
        let conn = fresh_db();
        // Pre-seed with a key whose public_key matches what the
        // archive carries — apply path should skip the dupe.
        ssh_keys::upsert(
            &conn,
            &ssh_keys::SshKeyRow {
                id: "existing".into(),
                label: "Existing".into(),
                private_key: "OLD".into(),
                public_key: "ssh-ed25519 AAAADUPE".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k_new","label":"Fresh","private_key":"NEW","public_key":"ssh-ed25519 AAAADUPE","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 0);
        assert_eq!(result.keys_skipped_dedup, 1);
        // Existing row stayed; the dupe import never landed under
        // its archive id.
        assert!(ssh_keys::get(&conn, "k_new").unwrap().is_none());
    }

    #[test]
    fn apply_sessions_parses_via_override_and_extras() {
        let conn = fresh_db();
        let json = r#"[{
            "id":"s1",
            "label":"prod",
            "host":"a.example",
            "port":22,
            "user":"deploy",
            "auth_type":"password",
            "password":"hunter2",
            "key_path":"",
            "key_data":"",
            "passphrase":"",
            "extras":{"foo":"bar"},
            "via_override":{"host":"bastion","port":2222,"user":"jump"},
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
        let pending = PendingImport {
            sessions_json: Some(json.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.sessions_applied, 1);
        let row = sessions::get(&conn, "s1").unwrap().unwrap();
        assert_eq!(row.via_host.as_deref(), Some("bastion"));
        assert_eq!(row.via_port, Some(2222));
        assert_eq!(row.via_user.as_deref(), Some("jump"));
        assert!(row.extras.contains("foo"));
        assert!(row.folder_id.is_none(), "folder hierarchy not yet wired");
    }

    #[test]
    fn apply_known_hosts_appends_lines() {
        let conn = fresh_db();
        let pending = PendingImport {
            known_hosts_text: Some(
                "# leading comment\nfoo.example ssh-ed25519 AAAA\nbar.example:2222 ssh-rsa BBBB\n"
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.known_hosts_applied, 2);
        let foo = known_hosts::get_by_host_port(&conn, "foo.example", 22)
            .unwrap()
            .unwrap();
        assert_eq!(foo.key_type, "ssh-ed25519");
        let bar = known_hosts::get_by_host_port(&conn, "bar.example", 2222)
            .unwrap()
            .unwrap();
        assert_eq!(bar.key_type, "ssh-rsa");
    }

    #[test]
    fn apply_tags_and_snippets_round_trip() {
        let conn = fresh_db();
        let pending = PendingImport {
            tags_json: Some(
                r##"[{"id":"t1","name":"prod","color":"#ff0000","created_at":"2026-04-26T00:00:00.000Z"}]"##
                    .to_string(),
            ),
            snippets_json: Some(
                r#"[{"id":"sn1","title":"ll","command":"ls -la","description":"long list","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.tags_applied, 1);
        assert_eq!(result.snippets_applied, 1);
        assert_eq!(tags::list_all(&conn).unwrap().len(), 1);
        assert_eq!(snippets::list_all(&conn).unwrap().len(), 1);
    }

    #[test]
    fn apply_does_not_abort_on_partial_parse_failure() {
        let conn = fresh_db();
        // Bad sessions JSON should not stop the keys stage.
        let pending = PendingImport {
            sessions_json: Some("not-json".to_string()),
            keys_json: Some(
                r#"[{"id":"k1","label":"good","private_key":"P","public_key":"ssh-ed25519 X","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.keys_applied, 1);
        assert_eq!(result.sessions_applied, 0);
        assert!(!result.errors.is_empty());
    }
}
