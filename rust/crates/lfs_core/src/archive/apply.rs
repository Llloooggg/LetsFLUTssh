//! Import-apply driver — turns a [`PendingImport`] into committed
//! rows on `letsflutssh.db`. Companion to the export composer in
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

    // ── Per-field session round-trip ────────────────────────────

    #[test]
    fn apply_sessions_lands_every_field_on_disk() {
        let conn = fresh_db();
        let json = r#"[{
            "id":"s1",
            "label":"prod-server",
            "folder":"",
            "host":"host.example",
            "port":2222,
            "user":"deploy",
            "auth_type":"key",
            "password":"pw-1",
            "key_path":"/home/u/.ssh/id_rsa",
            "key_data":"PRIV-PEM",
            "key_id":"k-ext",
            "passphrase":"kpass",
            "notes":"important box",
            "extras":{"shell":"zsh"},
            "via_session_id":"bastion-1",
            "via_override":{"host":"bastion","port":2200,"user":"jump"},
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
        // Seed bastion target so via_session_id FK passes,
        // and the manager key so key_id FK passes.
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "bastion-1".into(),
                label: "bastion".into(),
                host: "b".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                created_at_ms: 0,
                updated_at_ms: 0,
                ..Default::default()
            },
        )
        .unwrap();
        ssh_keys::upsert(
            &conn,
            &ssh_keys::SshKeyRow {
                id: "k-ext".into(),
                label: "ext".into(),
                private_key: "P".into(),
                public_key: "ssh-ed25519 X".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            sessions_json: Some(json.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.sessions_applied, 1);
        let row = sessions::get(&conn, "s1").unwrap().unwrap();
        // Every json_string mapping verified.
        assert_eq!(row.label, "prod-server");
        assert_eq!(row.host, "host.example");
        assert_eq!(row.port, 2222);
        assert_eq!(row.user, "deploy");
        assert_eq!(row.auth_type, "key");
        assert_eq!(row.password, "pw-1");
        assert_eq!(row.key_path, "/home/u/.ssh/id_rsa");
        assert_eq!(row.key_data, "PRIV-PEM");
        assert_eq!(row.key_id.as_deref(), Some("k-ext"));
        assert_eq!(row.passphrase, "kpass");
        assert_eq!(row.notes, "important box");
        assert!(row.extras.contains("zsh"));
        assert_eq!(row.via_session_id.as_deref(), Some("bastion-1"));
        assert_eq!(row.via_host.as_deref(), Some("bastion"));
        assert_eq!(row.via_port, Some(2200));
        assert_eq!(row.via_user.as_deref(), Some("jump"));
    }

    #[test]
    fn apply_session_skips_row_with_blank_id() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"","label":"x","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.sessions_applied, 0);
        assert!(result.errors.iter().any(|e| e.contains("missing id")));
    }

    #[test]
    fn apply_session_uses_created_at_iso_when_provided() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"x","host":"a","port":22,"user":"u","auth_type":"password","created_at":"2024-01-01T00:00:00.000Z","updated_at":"2024-01-01T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 9_999_000_000_000)
                .unwrap();
        assert_eq!(result.sessions_applied, 1);
        let row = sessions::get(&conn, "s1").unwrap().unwrap();
        // 2024-01-01T00:00:00Z = 1704067200000 ms.
        assert_eq!(row.created_at_ms, 1_704_067_200_000);
        // updated_at_ms is always now_ms (the apply moment).
        assert_eq!(row.updated_at_ms, 9_999_000_000_000);
    }

    // ── Folder tree from session.folder paths ──────────────────

    #[test]
    fn apply_folder_tree_builds_nested_hierarchy_and_assigns_ids() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[
                    {"id":"s1","label":"l1","folder":"Prod/Web","host":"a","port":22,"user":"u","auth_type":"password"},
                    {"id":"s2","label":"l2","folder":"Prod/DB","host":"b","port":22,"user":"u","auth_type":"password"},
                    {"id":"s3","label":"l3","folder":"Staging","host":"c","port":22,"user":"u","auth_type":"password"}
                ]"#
                .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        // Folders: Prod, Prod/Web, Prod/DB, Staging = 4 distinct
        // folder rows.
        assert_eq!(result.folders_applied, 4);
        let all = folders::list_all(&conn).unwrap();
        let names: HashSet<&str> = all.iter().map(|f| f.name.as_str()).collect();
        assert!(names.contains("Prod"));
        assert!(names.contains("Web"));
        assert!(names.contains("DB"));
        assert!(names.contains("Staging"));
        // Web's parent is Prod, DB's parent is Prod, Staging is root.
        let prod = all.iter().find(|f| f.name == "Prod").unwrap();
        let web = all.iter().find(|f| f.name == "Web").unwrap();
        let db = all.iter().find(|f| f.name == "DB").unwrap();
        let staging = all.iter().find(|f| f.name == "Staging").unwrap();
        assert!(prod.parent_id.is_none());
        assert_eq!(web.parent_id.as_deref(), Some(prod.id.as_str()));
        assert_eq!(db.parent_id.as_deref(), Some(prod.id.as_str()));
        assert!(staging.parent_id.is_none());
        // Sessions land with the resolved folder_id of their leaf.
        let s1 = sessions::get(&conn, "s1").unwrap().unwrap();
        assert_eq!(s1.folder_id.as_deref(), Some(web.id.as_str()));
        let s2 = sessions::get(&conn, "s2").unwrap().unwrap();
        assert_eq!(s2.folder_id.as_deref(), Some(db.id.as_str()));
        let s3 = sessions::get(&conn, "s3").unwrap().unwrap();
        assert_eq!(s3.folder_id.as_deref(), Some(staging.id.as_str()));
    }

    #[test]
    fn apply_folder_tree_skips_when_folder_path_blank() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l1","folder":"","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.folders_applied, 0);
        let s1 = sessions::get(&conn, "s1").unwrap().unwrap();
        assert!(s1.folder_id.is_none());
    }

    #[test]
    fn apply_empty_folders_creates_rows_for_paths_with_no_sessions() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some("[]".to_string()),
            empty_folders_json: Some(r#"["A/B","C"]"#.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        // A, A/B, C = 3 folder rows.
        assert_eq!(result.folders_applied, 3);
        let all = folders::list_all(&conn).unwrap();
        assert_eq!(all.len(), 3);
    }

    #[test]
    fn apply_empty_folders_dedups_against_session_folders() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"A","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            // "A" already exists from sessions_json — must not double-create.
            empty_folders_json: Some(r#"["A","B"]"#.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        // 2 folders: A (from sessions) + B (from empty_folders).
        assert_eq!(result.folders_applied, 2);
    }

    #[test]
    fn apply_empty_folders_skips_blank_paths() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some("[]".to_string()),
            empty_folders_json: Some(r#"["","A"]"#.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.folders_applied, 1);
    }

    // ── Per-toggle gating ──────────────────────────────────────

    #[test]
    fn apply_keys_off_skips_keys_stage_entirely() {
        let conn = fresh_db();
        let pending = PendingImport {
            keys_json: Some(
                r#"[{"id":"k1","label":"l","private_key":"P","public_key":"ssh-ed25519 X","key_type":"ssh-ed25519","is_generated":false,"created_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        let mut opts = merge_all_options();
        opts.apply_keys = false;
        let result =
            apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.keys_applied, 0);
        assert!(ssh_keys::get(&conn, "k1").unwrap().is_none());
    }

    #[test]
    fn apply_session_tags_requires_both_sessions_and_tags_toggles() {
        let conn = fresh_db();
        // Pre-seed session + tag so the link target exists.
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "s1".into(),
                label: "l".into(),
                host: "a".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                created_at_ms: 0,
                updated_at_ms: 0,
                ..Default::default()
            },
        )
        .unwrap();
        tags::upsert(
            &conn,
            &tags::TagRow {
                id: "t1".into(),
                name: "n".into(),
                color: None,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            session_tags_json: Some(r#"[{"session_id":"s1","tag_id":"t1"}]"#.to_string()),
            ..empty_pending()
        };
        // Tags off → link skipped.
        let mut opts = merge_all_options();
        opts.apply_tags = false;
        let result =
            apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_tags_applied, 0);
        // Sessions off → also skipped.
        let mut opts = merge_all_options();
        opts.apply_sessions = false;
        let result =
            apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_tags_applied, 0);
        // Both on → link applied.
        let result = apply_pending_import_merge(
            &conn,
            &pending,
            &merge_all_options(),
            1_700_000_000_000,
        )
        .unwrap();
        assert_eq!(result.session_tags_applied, 1);
        assert_eq!(tags::list_session_tag_ids(&conn, "s1").unwrap(), vec!["t1"]);
    }

    #[test]
    fn apply_session_snippets_requires_both_sessions_and_snippets_toggles() {
        let conn = fresh_db();
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "s1".into(),
                label: "l".into(),
                host: "a".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                created_at_ms: 0,
                updated_at_ms: 0,
                ..Default::default()
            },
        )
        .unwrap();
        snippets::upsert(
            &conn,
            &snippets::SnippetRow {
                id: "sn1".into(),
                title: "t".into(),
                command: "c".into(),
                description: "".into(),
                created_at_ms: 0,
                updated_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            session_snippets_json: Some(r#"[{"session_id":"s1","snippet_id":"sn1"}]"#.to_string()),
            ..empty_pending()
        };
        let mut opts = merge_all_options();
        opts.apply_snippets = false;
        let result =
            apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_snippets_applied, 0);
        let mut opts = merge_all_options();
        opts.apply_sessions = false;
        let result =
            apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_snippets_applied, 0);
        let result = apply_pending_import_merge(
            &conn,
            &pending,
            &merge_all_options(),
            1_700_000_000_000,
        )
        .unwrap();
        assert_eq!(result.session_snippets_applied, 1);
    }

    #[test]
    fn apply_session_link_skips_blank_ids() {
        let conn = fresh_db();
        let pending = PendingImport {
            session_tags_json: Some(
                r#"[{"session_id":"","tag_id":"t1"},{"session_id":"s1","tag_id":""}]"#.to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.session_tags_applied, 0);
        assert!(result.errors.is_empty(), "blank-id rows skip silently");
    }

    // ── Replace mode ──────────────────────────────────────────

    #[test]
    fn replace_mode_clears_existing_sessions_and_tags() {
        let mut conn = fresh_db();
        // Pre-seed live data.
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "old-s".into(),
                label: "old".into(),
                host: "a".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                created_at_ms: 0,
                updated_at_ms: 0,
                ..Default::default()
            },
        )
        .unwrap();
        tags::upsert(
            &conn,
            &tags::TagRow {
                id: "old-t".into(),
                name: "old".into(),
                color: None,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"new-s","label":"new","host":"b","port":22,"user":"u","auth_type":"password","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            tags_json: Some(
                r##"[{"id":"new-t","name":"new","color":"#fff","created_at":"2026-04-26T00:00:00.000Z"}]"##
                    .to_string(),
            ),
            ..empty_pending()
        };
        let mut opts = merge_all_options();
        opts.mode = ImportMode::Replace;
        let result = apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.sessions_applied, 1);
        assert_eq!(result.tags_applied, 1);
        // Old rows cleared, new ones present.
        assert!(sessions::get(&conn, "old-s").unwrap().is_none());
        assert!(sessions::get(&conn, "new-s").unwrap().is_some());
        let all_tags = tags::list_all(&conn).unwrap();
        assert_eq!(all_tags.len(), 1);
        assert_eq!(all_tags[0].id, "new-t");
    }

    #[test]
    fn replace_mode_does_not_wipe_manager_keys() {
        let mut conn = fresh_db();
        ssh_keys::upsert(
            &conn,
            &ssh_keys::SshKeyRow {
                id: "user-k".into(),
                label: "mine".into(),
                private_key: "P".into(),
                public_key: "ssh-ed25519 USERKEY".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
            },
        )
        .unwrap();
        let pending = empty_pending();
        let mut opts = merge_all_options();
        opts.mode = ImportMode::Replace;
        apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
        // Manager key untouched — replace intentionally skips ssh_keys.
        assert!(ssh_keys::get(&conn, "user-k").unwrap().is_some());
    }

    #[test]
    fn replace_mode_clears_known_hosts_when_toggle_on() {
        let mut conn = fresh_db();
        known_hosts::upsert_by_host_port(&conn, "old.example", 22, "ssh-rsa", "OLD", 0).unwrap();
        let pending = PendingImport {
            known_hosts_text: Some("new.example ssh-ed25519 NEW".to_string()),
            ..empty_pending()
        };
        let mut opts = merge_all_options();
        opts.mode = ImportMode::Replace;
        apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();
        // Old host gone, new host present.
        assert!(known_hosts::get_by_host_port(&conn, "old.example", 22)
            .unwrap()
            .is_none());
        assert!(known_hosts::get_by_host_port(&conn, "new.example", 22)
            .unwrap()
            .is_some());
    }

    // ── known_hosts parsing ───────────────────────────────────

    #[test]
    fn apply_known_hosts_default_port_22_when_omitted() {
        let conn = fresh_db();
        let pending = PendingImport {
            known_hosts_text: Some("h.example ssh-ed25519 KEY".to_string()),
            ..empty_pending()
        };
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
        // Default port is 22 — entry must land at (h.example, 22).
        assert!(known_hosts::get_by_host_port(&conn, "h.example", 22)
            .unwrap()
            .is_some());
    }

    #[test]
    fn apply_known_hosts_parses_explicit_port() {
        let conn = fresh_db();
        let pending = PendingImport {
            known_hosts_text: Some("h.example:9000 ssh-rsa KEY".to_string()),
            ..empty_pending()
        };
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
        assert!(known_hosts::get_by_host_port(&conn, "h.example", 9000)
            .unwrap()
            .is_some());
    }

    #[test]
    fn apply_known_hosts_skips_comments_and_blanks() {
        let conn = fresh_db();
        let text = "\n# comment line\n\n  \nh1 ssh-rsa A\n# another comment\nh2 ssh-rsa B\n";
        let pending = PendingImport {
            known_hosts_text: Some(text.into()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.known_hosts_applied, 2);
    }

    #[test]
    fn apply_known_hosts_skips_lines_with_too_few_columns() {
        let conn = fresh_db();
        let text = "incomplete line\nh ssh-rsa KEY";
        let pending = PendingImport {
            known_hosts_text: Some(text.into()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.known_hosts_applied, 1);
    }

    // ── port + json_i64 ───────────────────────────────────────

    #[test]
    fn apply_session_port_round_trips_actual_value() {
        let conn = fresh_db();
        let pending = PendingImport {
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","host":"h","port":12345,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
        let row = sessions::get(&conn, "s1").unwrap().unwrap();
        // json_i64 mutants would replace the value with 0 / 1 / -1.
        assert_eq!(row.port, 12345);
    }

    // ── tags / snippets content ───────────────────────────────

    #[test]
    fn apply_tags_lands_color_and_name_per_row() {
        let conn = fresh_db();
        let pending = PendingImport {
            tags_json: Some(
                r##"[
                    {"id":"t1","name":"prod","color":"#ff0000","created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t2","name":"staging","color":"","created_at":"2026-04-26T00:00:00.000Z"}
                ]"##
                .to_string(),
            ),
            ..empty_pending()
        };
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
        let all = tags::list_all(&conn).unwrap();
        let t1 = all.iter().find(|t| t.id == "t1").unwrap();
        let t2 = all.iter().find(|t| t.id == "t2").unwrap();
        assert_eq!(t1.name, "prod");
        assert_eq!(t1.color.as_deref(), Some("#ff0000"));
        // Empty color string stored as None.
        assert!(t2.color.is_none());
    }

    #[test]
    fn apply_tags_skips_row_with_blank_id_or_name() {
        let conn = fresh_db();
        let pending = PendingImport {
            tags_json: Some(
                r##"[
                    {"id":"","name":"x","color":null,"created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t1","name":"","color":null,"created_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"t2","name":"good","color":null,"created_at":"2026-04-26T00:00:00.000Z"}
                ]"##
                .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.tags_applied, 1);
        assert!(tags::list_all(&conn)
            .unwrap()
            .iter()
            .any(|t| t.id == "t2"));
    }

    #[test]
    fn apply_snippets_lands_command_and_description() {
        let conn = fresh_db();
        let pending = PendingImport {
            snippets_json: Some(
                r#"[{"id":"sn1","title":"list","command":"ls -la","description":"long","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}]"#
                    .to_string(),
            ),
            ..empty_pending()
        };
        apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
            .unwrap();
        let all = snippets::list_all(&conn).unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].command, "ls -la");
        assert_eq!(all[0].description, "long");
    }

    #[test]
    fn apply_snippets_skips_row_with_blank_title_or_id() {
        let conn = fresh_db();
        let pending = PendingImport {
            snippets_json: Some(
                r#"[
                    {"id":"","title":"x","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"sn1","title":"","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"},
                    {"id":"sn2","title":"good","command":"c","description":"","created_at":"2026-04-26T00:00:00.000Z","updated_at":"2026-04-26T00:00:00.000Z"}
                ]"#
                .to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.snippets_applied, 1);
    }
}
