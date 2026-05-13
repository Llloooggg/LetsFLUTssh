//! Import-apply driver — turns a [`PendingImport`] into committed
//! rows on `letsflutssh.db`. Companion to the export composer in
//! [`super`]; the two halves bracket the wire-format contract for
//! the `.lfs` archive (and, via [`crate::archive_stage`], the
//! in-memory QR / paste-link / OpenSSH-config import flows).
//!
//! # Modes
//!
//! The canonical entry point is [`apply_pending_to_db`]; pick a
//! variant of [`ApplyMode`]:
//!
//! - [`ApplyMode::ArchiveImport`] `{ replace_mode: false }` — Merge.
//!   Upserts every entry by id; collisions update the existing row's
//!   mutable columns. Known-hosts upsert by `(host, port)`; manager
//!   keys dedup by public-key fingerprint so a key already on disk
//!   does not double-land under the archive's id. Folder paths from
//!   `sessions.json` flatten into a per-archive folder tree; ids are
//!   minted fresh.
//! - [`ApplyMode::ArchiveImport`] `{ replace_mode: true }` — Replace.
//!   Runs every stage inside a single sqlite transaction. For each
//!   enabled kind, the existing rows clear before the archive entries
//!   insert; a downstream parse error rolls the whole transaction back,
//!   so a botched import never leaves the DB half-overwritten.
//!   Junctions (`session_tags`, `session_snippets`) are cleared
//!   alongside their owning kinds (sessions / tags). Manager keys are
//!   intentionally NOT wiped on replace — the user's existing keys
//!   stay valid; the archive's keys merge by fingerprint as in merge
//!   mode (mirror of the Dart impl, kept to avoid surprising the user
//!   with "import lost my generated keys").
//! - [`ApplyMode::Sync`] — last-writer-wins over `created_at` /
//!   `updated_at`. Folder tree is reused by path (`folders::ensure_folder_path`)
//!   rather than minted fresh. Keys/sessions/snippets/tags resolved
//!   by id with a strict-greater LWW gate so a tie keeps the local
//!   row; M2M edges (`session_tags`, `folder_tags`, `session_snippets`)
//!   union via `INSERT OR IGNORE`. Hardware-bound key columns are
//!   per-device and never overwrite — sync rows land as `software`
//!   stubs (matches the v2 wire shape; Stage 3 adds backend-typed
//!   stubs).
//!
//! # Failure model
//!
//! Per-row parse failures land in [`ApplyOutcome::errors`] and the
//! driver keeps going — a single corrupt session in a 500-host
//! archive does not abort the whole import. Hard sqlite errors
//! (lock contention, disk full) are pushed into the same vec; the
//! caller renders them as a non-blocking notice while the rest of
//! the archive lands.
//!
//! [`ApplyResult`] (archive entry counters) and
//! [`crate::sync::merge::MergeOutcome`] (sync entry counters) are
//! per-mode views projected from [`ApplyOutcome`]; both legacy
//! entry points ([`apply_pending_import`],
//! [`apply_pending_import_merge`], [`crate::sync::merge::merge_pending_into_local`])
//! route through [`apply_pending_to_db`].

use std::collections::{HashMap, HashSet};

use serde_json::Value;

use crate::db::{
    folders, known_hosts, port_forwards, s3_sessions, sessions, sftp_bookmarks, snippets,
    ssh_key_certificates, ssh_keys, tags, webdav_sessions, Connection,
};
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

/// Canonical mode for [`apply_pending_to_db`]. The unified entry
/// point replaces the two pre-unification codepaths
/// (`archive::apply::apply_pending` and
/// `sync::merge::merge_pending_into_local`).
///
/// - [`ApplyMode::ArchiveImport`] — `.lfs` file import. `replace_mode`
///   flips between the Merge / Replace semantics from the legacy
///   `ImportMode` enum (see the module docs).
/// - [`ApplyMode::Sync`] — WebDAV sync pull. Tombstone-aware
///   last-writer-wins on `created_at` / `updated_at`; foreign-device
///   per-key preferences (`agent_policy`) backfill to `Ask` so a peer
///   device's mute / always-allow setting does not silently authorise
///   the receiving host's ssh-agent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApplyMode {
    ArchiveImport { replace_mode: bool },
    Sync,
}

impl ApplyMode {
    /// `true` when the mode is `ArchiveImport { replace_mode: false }`
    /// or `ArchiveImport { replace_mode: true }` — i.e. the apply is
    /// driven by a user-initiated `.lfs` import flow. Used to gate
    /// per-mode toggle checks (sync ignores `ApplyOptions` toggles
    /// and always applies every entry the peer carried).
    fn is_archive(self) -> bool {
        matches!(self, Self::ArchiveImport { .. })
    }

    fn is_sync(self) -> bool {
        matches!(self, Self::Sync)
    }
}

/// Unified counters surfaced by [`apply_pending_to_db`]. Carries
/// every metric both legacy codepaths used to report on their own
/// (`ApplyResult` from archive import, `MergeOutcome` from sync
/// merge). Projection helpers ([`ApplyOutcome::to_apply_result`] /
/// [`ApplyOutcome::to_merge_outcome`]) build the per-mode views the
/// legacy callers still consume.
#[derive(Debug, Clone, Default)]
pub struct ApplyOutcome {
    pub sessions_applied: i64,
    pub keys_applied: i64,
    pub keys_skipped_dedup: i64,
    pub tags_applied: i64,
    pub snippets_applied: i64,
    pub known_hosts_applied: i64,
    pub folders_applied: i64,
    pub session_tags_applied: i64,
    pub folder_tags_applied: i64,
    pub session_snippets_applied: i64,
    pub ssh_key_certificates_applied: i64,
    pub webdav_session_details_applied: i64,
    pub s3_session_details_applied: i64,
    pub sftp_bookmarks_applied: i64,
    pub port_forward_rules_applied: i64,
    pub errors: Vec<String>,
    /// Soft warnings the apply driver emits for filtered or skipped
    /// rows that are still "well-formed" — e.g. a cert row whose
    /// parent key did not land for any reason. Distinct from `errors`
    /// because they do not trigger replace-mode rollback.
    pub warnings: Vec<String>,
    /// Replace-mode-only flag — set when the per-row apply
    /// produced one or more errors and the transaction rolled
    /// back. The `applied` counters reflect what *would* have
    /// committed had the import succeeded; the caller MUST treat
    /// this as a hard failure (display errors, leave existing
    /// data untouched) rather than a partial success.
    pub rolled_back: bool,
}

impl ApplyOutcome {
    /// Project the unified outcome onto the archive-import shape so
    /// `apply_pending_import` callers keep their existing field set.
    pub fn to_apply_result(&self) -> ApplyResult {
        ApplyResult {
            sessions_applied: self.sessions_applied,
            keys_applied: self.keys_applied,
            keys_skipped_dedup: self.keys_skipped_dedup,
            tags_applied: self.tags_applied,
            snippets_applied: self.snippets_applied,
            known_hosts_applied: self.known_hosts_applied,
            folders_applied: self.folders_applied,
            session_tags_applied: self.session_tags_applied,
            folder_tags_applied: self.folder_tags_applied,
            session_snippets_applied: self.session_snippets_applied,
            errors: self.errors.clone(),
            rolled_back: self.rolled_back,
        }
    }
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
/// per-entry parse failures encountered along the way — Merge
/// mode keeps going past a bad row so a single corrupt session
/// in a 500-host archive doesn't abort the whole import. Replace
/// mode rolls the transaction back when `errors` is non-empty
/// (see [`rolled_back`]) so the user's pre-import state survives.
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
    pub folder_tags_applied: i64,
    pub session_snippets_applied: i64,
    pub errors: Vec<String>,
    /// Replace-mode-only flag — set when the per-row apply
    /// produced one or more errors and the transaction rolled
    /// back. The `applied` counters reflect what *would* have
    /// committed had the import succeeded; the caller MUST treat
    /// this as a hard failure (display errors, leave existing
    /// data untouched) rather than a partial success.
    pub rolled_back: bool,
}

/// Apply a staged [`PendingImport`] under archive-import semantics.
/// Thin wrapper around [`apply_pending_to_db`] that builds the
/// matching [`ApplyMode::ArchiveImport`] variant and projects the
/// unified [`ApplyOutcome`] onto the legacy [`ApplyResult`] shape.
/// `now_ms` stamps any row that lacks a timestamp in the archive.
pub fn apply_pending_import(
    conn: &mut Connection,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    let replace_mode = matches!(options.mode, ImportMode::Replace);
    let mut outcome = ApplyOutcome::default();
    apply_pending_to_db(
        conn,
        pending,
        ApplyMode::ArchiveImport { replace_mode },
        options,
        now_ms,
        &mut outcome,
    )?;
    Ok(outcome.to_apply_result())
}

/// Backwards-compatible alias for the merge-only archive-import
/// path that does NOT need a `&mut Connection` (used by callers
/// that already hold a `&impl DbAccess`, like the QR / OpenSSH-config
/// stage path). Routes through the unified entry's no-transaction
/// arm so behaviour stays bit-identical to the standalone shape
/// the function had before unification.
pub fn apply_pending_import_merge(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    options: &ApplyOptions,
    now_ms: i64,
) -> Result<ApplyResult, Error> {
    let mut outcome = ApplyOutcome::default();
    run_apply(
        conn,
        pending,
        ApplyMode::ArchiveImport {
            replace_mode: false,
        },
        Some(options),
        now_ms,
        &mut outcome,
    );
    Ok(outcome.to_apply_result())
}

/// Canonical apply driver. Both `.lfs` import and WebDAV sync pull
/// route through this entry; pick [`ApplyMode::ArchiveImport`] or
/// [`ApplyMode::Sync`] to select the per-mode semantics described
/// in the module docs.
///
/// `options` gates which kinds the apply touches. `ApplyMode::Sync`
/// ignores the toggles and always applies every entry the peer
/// shipped (the sync orchestrator owns the toggle set on its end);
/// for archive-import callers `options` mirrors the Dart import-dialog
/// checkboxes.
///
/// `now_ms` stamps the apply moment so rows lacking a timestamp in
/// the staged JSON land with a coherent `created_at` / `updated_at`.
///
/// Sync mode always wraps the apply in a single sqlite transaction
/// so a mid-merge error rolls back cleanly; archive-import mode
/// only opens a transaction when `replace_mode == true` (Merge mode
/// commits per-row so a single corrupt session does not abort the
/// whole import — see the module docs).
pub fn apply_pending_to_db(
    conn: &mut Connection,
    pending: &PendingImport,
    mode: ApplyMode,
    options: &ApplyOptions,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) -> Result<(), Error> {
    match mode {
        ApplyMode::ArchiveImport {
            replace_mode: false,
        } => {
            run_apply(conn, pending, mode, Some(options), now_ms, outcome);
            Ok(())
        }
        ApplyMode::ArchiveImport { replace_mode: true } => {
            let tx = conn
                .inner_mut()
                .transaction()
                .map_err(|e| Error::Archive(format!("apply tx begin: {e}")))?;
            run_replace_clear(&tx, options, outcome);
            run_apply(&tx, pending, mode, Some(options), now_ms, outcome);
            // Replace mode is all-or-nothing — wiping the user's
            // existing rows and then committing a partially-failed
            // import would leave them with their original data
            // gone and the new data incomplete. Rolling back here
            // preserves the pre-import state; the caller surfaces
            // `errors` to the user so they can fix the archive
            // and retry.
            if !outcome.errors.is_empty() {
                tx.rollback()
                    .map_err(|e| Error::Archive(format!("apply tx rollback: {e}")))?;
                outcome.rolled_back = true;
                return Ok(());
            }
            tx.commit()
                .map_err(|e| Error::Archive(format!("apply tx commit: {e}")))?;
            Ok(())
        }
        ApplyMode::Sync => {
            // Sync wraps the whole merge in a single transaction so
            // a catastrophic mid-merge failure rolls the local DB
            // back to the pre-pull snapshot. Per-row parse failures
            // still collect into `outcome.errors` without aborting.
            let tx = conn
                .inner_mut()
                .transaction()
                .map_err(|e| Error::Db(format!("sync apply: tx begin: {e}")))?;
            run_apply(&tx, pending, mode, None, now_ms, outcome);
            tx.commit()
                .map_err(|e| Error::Db(format!("sync apply: tx commit: {e}")))?;
            Ok(())
        }
    }
}

fn run_apply(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    mode: ApplyMode,
    options: Option<&ApplyOptions>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    // Sync ignores `options` — the orchestrator always ships every
    // entry the peer carried. Archive-import callers gate per-kind
    // through the toggle set.
    let want_keys = options.is_none_or(|o| o.apply_keys);
    let want_sessions = options.is_none_or(|o| o.apply_sessions);
    let want_tags = options.is_none_or(|o| o.apply_tags);
    let want_snippets = options.is_none_or(|o| o.apply_snippets);
    let want_known_hosts = options.is_none_or(|o| o.apply_known_hosts);

    if want_keys {
        if let Some(json) = pending.keys_json.as_deref() {
            apply_keys(conn, json, mode, now_ms, outcome);
        }
    }
    // Apply folders + sessions together so session.folder_id
    // resolves through the imported folder tree.
    let mut folder_path_to_id: HashMap<String, String> = HashMap::new();
    if want_sessions {
        if let Some(json) = pending.sessions_json.as_deref() {
            folder_path_to_id = apply_folder_tree(conn, json, mode, now_ms, outcome);
            apply_sessions(conn, json, mode, &folder_path_to_id, now_ms, outcome);
        }
        if let Some(json) = pending.empty_folders_json.as_deref() {
            apply_empty_folders(conn, json, &mut folder_path_to_id, now_ms, outcome);
        }
    }
    if want_tags {
        if let Some(json) = pending.tags_json.as_deref() {
            apply_tags(conn, json, mode, now_ms, outcome);
        }
    }
    if want_sessions && want_tags {
        if let Some(json) = pending.session_tags_json.as_deref() {
            apply_session_tags(conn, json, outcome);
        }
        if let Some(json) = pending.folder_tags_json.as_deref() {
            apply_folder_tags(conn, json, &folder_path_to_id, outcome);
        }
    }
    if want_snippets {
        if let Some(json) = pending.snippets_json.as_deref() {
            apply_snippets(conn, json, mode, now_ms, outcome);
        }
    }
    if want_sessions && want_snippets {
        if let Some(json) = pending.session_snippets_json.as_deref() {
            apply_session_snippets(conn, json, outcome);
        }
    }
    if want_known_hosts {
        if let Some(text) = pending.known_hosts_text.as_deref() {
            apply_known_hosts(conn, text, now_ms, outcome);
        }
    }
    // New-table apply arms. Each is no-op when its JSON entry is
    // absent from the pending bundle, which is the v1/v2 archive
    // shape (`SchemaVersions::ARCHIVE` v3 adds the entries).
    if want_keys {
        if let Some(json) = pending.ssh_key_certificates_json.as_deref() {
            apply_ssh_key_certificates(conn, json, outcome);
        }
    }
    if want_sessions {
        if let Some(json) = pending.webdav_session_details_json.as_deref() {
            apply_webdav_session_details(conn, json, mode, now_ms, outcome);
        }
        if let Some(json) = pending.s3_session_details_json.as_deref() {
            apply_s3_session_details(conn, json, mode, now_ms, outcome);
        }
        if let Some(json) = pending.sftp_bookmarks_json.as_deref() {
            apply_sftp_bookmarks(conn, json, mode, now_ms, outcome);
        }
        if let Some(json) = pending.port_forward_rules_json.as_deref() {
            apply_port_forward_rules(conn, json, mode, now_ms, outcome);
        }
    }
}

fn run_replace_clear(
    conn: &impl crate::db::DbAccess,
    options: &ApplyOptions,
    outcome: &mut ApplyOutcome,
) {
    // Order matters — child tables clear before their parents so
    // FK enforcement stays happy. Each `delete_all` / `clear_all`
    // is idempotent on an already-empty table.
    if options.apply_sessions {
        // Child tables that hang off `sessions` go first.
        if let Err(e) = sftp_bookmarks::delete_all(conn) {
            outcome
                .errors
                .push(format!("replace clear sftp_bookmarks: {e}"));
        }
        if let Err(e) = port_forwards::delete_all(conn) {
            outcome
                .errors
                .push(format!("replace clear port_forward_rules: {e}"));
        }
        if let Err(e) = webdav_sessions::delete_all(conn) {
            outcome
                .errors
                .push(format!("replace clear webdav_session_details: {e}"));
        }
        if let Err(e) = s3_sessions::delete_all(conn) {
            outcome
                .errors
                .push(format!("replace clear s3_session_details: {e}"));
        }
        if let Err(e) = sessions::delete_all(conn) {
            outcome.errors.push(format!("replace clear sessions: {e}"));
        }
        if let Err(e) = folders::delete_all(conn) {
            outcome.errors.push(format!("replace clear folders: {e}"));
        }
    }
    if options.apply_tags {
        if let Err(e) = tags::delete_all(conn) {
            outcome.errors.push(format!("replace clear tags: {e}"));
        }
    }
    if options.apply_snippets {
        if let Err(e) = snippets::delete_all(conn) {
            outcome.errors.push(format!("replace clear snippets: {e}"));
        }
    }
    if options.apply_known_hosts {
        if let Err(e) = known_hosts::clear_all(conn) {
            outcome
                .errors
                .push(format!("replace clear known_hosts: {e}"));
        }
    }
}

fn apply_folder_tree(
    conn: &impl crate::db::DbAccess,
    sessions_json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
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
    // Sync mode reuses local folders by path (so a peer's
    // "Production" doesn't mint a duplicate folder on every pull).
    // Archive import always inserts fresh ids — that's the
    // pre-unification behaviour, kept because import is a
    // user-initiated bulk operation that the user has reviewed.
    if mode.is_sync() {
        let mut out: HashMap<String, String> = HashMap::new();
        let mut sorted: Vec<String> = paths.into_iter().collect();
        sorted.sort();
        for path in sorted {
            if path.is_empty() || out.contains_key(&path) {
                continue;
            }
            match folders::ensure_folder_path(conn, &path, now_ms) {
                Ok(Some(id)) => {
                    out.insert(path, id);
                }
                Ok(None) => {}
                Err(e) => outcome
                    .errors
                    .push(format!("sync merge folder ensure: {e}")),
            }
        }
        return out;
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
                    outcome.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    outcome.errors.push(format!("folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
    path_to_id
}

fn apply_empty_folders(
    conn: &impl crate::db::DbAccess,
    json: &str,
    path_to_id: &mut HashMap<String, String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    use rand::RngCore;
    let arr: Vec<String> = match serde_json::from_str(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("empty_folders parse: {e}"));
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
                    outcome.folders_applied += 1;
                    path_to_id.insert(accum.clone(), id.clone());
                    parent_id = Some(id);
                }
                Err(e) => {
                    outcome
                        .errors
                        .push(format!("empty_folder {accum} upsert: {e}"));
                    parent_id = None;
                }
            }
        }
    }
}

fn apply_session_tags(conn: &impl crate::db::DbAccess, json: &str, outcome: &mut ApplyOutcome) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("session_tags parse: {e}"));
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
            Ok(_) => outcome.session_tags_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("session_tag {session_id}↔{tag_id}: {e}")),
        }
    }
}

/// Apply `folder_tags.json` — `[{folder_path, tag_id}]` — by
/// resolving each `folder_path` against the freshly-built
/// `path_to_id` map (populated by [`apply_folder_tree`] +
/// [`apply_empty_folders`]) and calling `tags::link_folder_tag`.
///
/// Folders unknown to `path_to_id` (path not present in the
/// imported sessions or empty-folders payload) are skipped — the
/// archive carries the path verbatim so a partial import that
/// drops the parent folder must not silently re-anchor the tag
/// to a stale id; the link is dropped instead, which the user can
/// rebuild from the Tag Manager.
fn apply_folder_tags(
    conn: &impl crate::db::DbAccess,
    json: &str,
    path_to_id: &HashMap<String, String>,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("folder_tags parse: {e}"));
            return;
        }
    };
    for v in arr {
        let folder_path = json_string(&v, "folder_path");
        let tag_id = json_string(&v, "tag_id");
        if folder_path.is_empty() || tag_id.is_empty() {
            continue;
        }
        let Some(folder_id) = path_to_id.get(&folder_path) else {
            // Path was not materialised this import — sessions for
            // it weren't applied and it wasn't in empty_folders.
            // Skip silently: the link belongs to a folder the user
            // chose not to import.
            continue;
        };
        match tags::link_folder_tag(conn, folder_id, &tag_id) {
            Ok(_) => outcome.folder_tags_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("folder_tag {folder_path}↔{tag_id}: {e}")),
        }
    }
}

fn apply_session_snippets(conn: &impl crate::db::DbAccess, json: &str, outcome: &mut ApplyOutcome) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("session_snippets parse: {e}"));
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
            Ok(_) => outcome.session_snippets_applied += 1,
            Err(e) => outcome
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
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    folder_path_to_id: &HashMap<String, String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("sessions parse: {e}"));
            return;
        }
    };
    // Sync mode pre-loads the local table so the LWW gate can
    // compare each peer row's `updated_at` against the local stamp.
    // Archive imports always upsert, so the local snapshot is not
    // needed.
    let local: HashMap<String, sessions::SessionRow> = if mode.is_sync() {
        match sessions::list_all(conn) {
            Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
            Err(e) => {
                outcome
                    .errors
                    .push(format!("sync merge sessions list: {e}"));
                return;
            }
        }
    } else {
        HashMap::new()
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
        let kind = v
            .get("kind")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(String::from)
            .unwrap_or_else(|| sessions::SESSION_KIND_SSH.to_string());
        let id = json_string(&v, "id");
        if id.is_empty() {
            // Archive imports report; sync skips silently (peer ships
            // garbage shouldn't block the rest of the merge).
            if mode.is_archive() {
                outcome.errors.push("session row missing id".to_string());
            }
            continue;
        }
        let peer_updated_at = if mode.is_sync() {
            parse_iso8601_or_now(
                v.get("updated_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            )
        } else {
            now_ms
        };
        if mode.is_sync() {
            if let Some(local_row) = local.get(&id) {
                // Strict-greater so a tie keeps local state; the
                // local row's tombstone counts as part of the LWW
                // timestamp via `updated_at_ms`.
                if peer_updated_at <= local_row.updated_at_ms {
                    continue;
                }
            }
        }
        let row = sessions::SessionRow {
            id: id.clone(),
            label: json_string(&v, "label"),
            folder_id,
            kind,
            host: json_string(&v, "host"),
            port: if mode.is_sync() {
                json_i64_opt(&v, "port").unwrap_or(22)
            } else {
                json_i64(&v, "port")
            },
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
            // Sync mode doesn't ship `notes` in v2 archives; archive
            // imports do. Keep both behaviours faithful: archive
            // reads the field, sync leaves it empty.
            notes: if mode.is_sync() {
                String::new()
            } else {
                json_string(&v, "notes")
            },
            last_connected_at_ms: None,
            extras: if mode.is_sync() {
                v.get("extras")
                    .map(|e| e.to_string())
                    .unwrap_or_else(|| "{}".into())
            } else {
                extras
            },
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
            updated_at_ms: peer_updated_at,
        };
        match sessions::upsert(conn, &row) {
            Ok(_) => outcome.sessions_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("session {} upsert: {e}", row.id)),
        }
    }
}

fn json_i64_opt(v: &Value, key: &str) -> Option<i64> {
    v.get(key).and_then(|x| x.as_i64())
}

fn apply_keys(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("keys parse: {e}"));
            return;
        }
    };
    if mode.is_sync() {
        return apply_keys_sync(conn, arr, now_ms, outcome);
    }
    // Archive-import path. Dedup against existing public-key
    // fingerprints — an exact dupe leaves the existing row alone
    // but counts as skipped so the UI summary reads
    // "added N, deduped M".
    let existing = match ssh_keys::list_metadata(conn) {
        Ok(v) => v,
        Err(e) => {
            outcome.errors.push(format!("keys metadata: {e}"));
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
            outcome.keys_skipped_dedup += 1;
            continue;
        }
        let row = match build_key_row(&v, now_ms) {
            Ok(r) => r,
            Err(msg) => {
                outcome.errors.push(msg);
                continue;
            }
        };
        if row.id.is_empty() {
            outcome.errors.push("key row missing id".to_string());
            continue;
        }
        match ssh_keys::upsert(conn, &row) {
            Ok(_) => outcome.keys_applied += 1,
            Err(e) => outcome.errors.push(format!("key {} upsert: {e}", row.id)),
        }
    }
}

/// Sync-mode key fold. LWW on `created_at`; ties keep the local
/// row. Backend / pkcs11 / hardware-bound columns stay per-device
/// (sync never overwrites them) — every incoming row lands as
/// `software` for v2 wire payloads, or as a typed stub when the
/// peer shipped a v3 backend payload (Stage 3).
fn apply_keys_sync(
    conn: &impl crate::db::DbAccess,
    arr: Vec<Value>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let local: HashMap<String, ssh_keys::SshKeyRow> = match ssh_keys::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
        Err(e) => {
            outcome.errors.push(format!("sync merge keys list: {e}"));
            return;
        }
    };
    for v in arr {
        let id = json_string(&v, "id");
        if id.is_empty() {
            continue;
        }
        let peer_ts = parse_iso8601_or_now(
            v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
            now_ms,
        );
        if let Some(local_row) = local.get(&id) {
            if peer_ts <= local_row.created_at_ms {
                continue;
            }
        }
        let row = match build_key_row(&v, now_ms) {
            Ok(mut r) => {
                r.id = id.clone();
                r.created_at_ms = peer_ts;
                r
            }
            Err(msg) => {
                outcome.errors.push(format!("sync merge key {id}: {msg}"));
                continue;
            }
        };
        match ssh_keys::upsert(conn, &row) {
            Ok(_) => outcome.keys_applied += 1,
            Err(e) => outcome.errors.push(format!("sync merge key {id}: {e}")),
        }
    }
}

/// Build an `SshKeyRow` from the wire-format JSON value. The current
/// implementation pins every cross-device row to
/// [`ssh_keys::KeyBackend::Software`] (matches the v2 archive shape).
/// Stage 3 rewrites this to honour the v3 backend discriminator and
/// per-backend payload (stub rows for device-bound backends, full
/// metadata for FIDO2 / PKCS#11).
fn build_key_row(v: &Value, now_ms: i64) -> Result<ssh_keys::SshKeyRow, String> {
    let public_key = json_string(v, "public_key");
    let id = json_string(v, "id");
    let backend_raw = v
        .get("backend")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    let backend = match backend_raw.as_deref() {
        Some(name) => ssh_keys::KeyBackend::from_db(name),
        None => ssh_keys::KeyBackend::Software,
    };
    // Device-bound backends travel as stubs — the private side is
    // bound to the source device's hardware and cannot reconstruct
    // on the receiving device. The user picks "Re-generate here"
    // off the stub row to mint a fresh hardware-backed key with
    // the same label.
    let is_stub = matches!(
        backend,
        ssh_keys::KeyBackend::Enclave
            | ssh_keys::KeyBackend::Hello
            | ssh_keys::KeyBackend::Tpm
            | ssh_keys::KeyBackend::Keystore
    );
    let private_key = if is_stub {
        String::new()
    } else {
        json_string(v, "private_key")
    };
    let credential_id = v
        .get("credential_id")
        .and_then(|x| x.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|b| b.as_u64().map(|n| n as u8))
                .collect()
        });
    let application_string = v
        .get("application_string")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    let has_user_verification = v
        .get("has_user_verification")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);
    let (pkcs11_uri, pkcs11_token_serial, pkcs11_object_id, pkcs11_object_label) =
        if matches!(backend, ssh_keys::KeyBackend::Pkcs11) {
            (
                v.get("pkcs11_uri")
                    .and_then(|x| x.as_str())
                    .map(|s| s.to_string()),
                v.get("pkcs11_token_serial")
                    .and_then(|x| x.as_str())
                    .map(|s| s.to_string()),
                v.get("pkcs11_object_id")
                    .and_then(|x| x.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|b| b.as_u64().map(|n| n as u8))
                            .collect()
                    }),
                v.get("pkcs11_object_label")
                    .and_then(|x| x.as_str())
                    .map(|s| s.to_string()),
            )
        } else {
            (None, None, None, None)
        };
    Ok(ssh_keys::SshKeyRow {
        id,
        label: json_string(v, "label"),
        private_key,
        public_key,
        key_type: json_string(v, "key_type"),
        is_generated: v
            .get("is_generated")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
        created_at_ms: parse_iso8601_or_now(
            v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
            now_ms,
        ),
        credential_id,
        application_string,
        has_user_verification,
        // Cross-device apply always lands `'ask'` so the receiving
        // host's ssh-agent endpoint surfaces a confirmation dialog
        // until the local operator promotes the row.
        agent_policy: ssh_keys::AgentPolicy::Ask,
        backend,
        pkcs11_uri,
        // Module path is per-host install location; never on the wire.
        // Resolved locally on first use via `well_known_paths` keyed
        // on `pkcs11_token_serial`; see ARCHITECTURE.md §3.9.
        pkcs11_module_path: None,
        pkcs11_token_serial,
        pkcs11_object_id,
        pkcs11_object_label,
        // Device-bound material columns stay None — the private
        // side never travels.
        enclave_tag: None,
        hello_credential_name: None,
        tpm_blob: None,
        tpm_handle: None,
        tpm_provider: None,
        tpm_pin_required: false,
        cng_key_name: None,
        keystore_alias: None,
        keystore_strongbox: false,
        keystore_user_auth_required: false,
        keystore_platform: None,
        imported_as_stub: is_stub,
    })
}

fn apply_tags(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("tags parse: {e}"));
            return;
        }
    };
    // LWW on `created_at` for sync mode (tags carry no
    // `updated_at` column).
    let local: HashMap<String, tags::TagRow> = if mode.is_sync() {
        match tags::list_all(conn) {
            Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
            Err(e) => {
                outcome.errors.push(format!("sync merge tags list: {e}"));
                return;
            }
        }
    } else {
        HashMap::new()
    };
    for v in arr {
        let id = json_string(&v, "id");
        let name = json_string(&v, "name");
        let peer_ts = parse_iso8601_or_now(
            v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
            now_ms,
        );
        if id.is_empty() || (!mode.is_sync() && name.is_empty()) {
            continue;
        }
        // Sync also requires name; the empty case is just skipped.
        if mode.is_sync() && name.is_empty() {
            continue;
        }
        if mode.is_sync() {
            if let Some(local_row) = local.get(&id) {
                if peer_ts <= local_row.created_at_ms {
                    continue;
                }
            }
        }
        let row = tags::TagRow {
            id,
            name,
            color: v
                .get("color")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(String::from),
            created_at_ms: peer_ts,
        };
        match tags::upsert(conn, &row) {
            Ok(_) => outcome.tags_applied += 1,
            Err(e) => outcome.errors.push(format!("tag {} upsert: {e}", row.id)),
        }
    }
}

fn apply_snippets(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("snippets parse: {e}"));
            return;
        }
    };
    let local: HashMap<String, snippets::SnippetRow> = if mode.is_sync() {
        match snippets::list_all(conn) {
            Ok(rows) => rows.into_iter().map(|r| (r.id.clone(), r)).collect(),
            Err(e) => {
                outcome
                    .errors
                    .push(format!("sync merge snippets list: {e}"));
                return;
            }
        }
    } else {
        HashMap::new()
    };
    for v in arr {
        let id = json_string(&v, "id");
        let title = json_string(&v, "title");
        if id.is_empty() {
            continue;
        }
        if !mode.is_sync() && title.is_empty() {
            continue;
        }
        let peer_updated = parse_iso8601_or_now(
            v.get("updated_at").and_then(|x| x.as_str()).unwrap_or(""),
            now_ms,
        );
        if mode.is_sync() {
            if let Some(local_row) = local.get(&id) {
                if peer_updated <= local_row.updated_at_ms {
                    continue;
                }
            }
        }
        let row = snippets::SnippetRow {
            id: id.clone(),
            title,
            command: json_string(&v, "command"),
            description: json_string(&v, "description"),
            created_at_ms: parse_iso8601_or_now(
                v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
                now_ms,
            ),
            updated_at_ms: if mode.is_sync() { peer_updated } else { now_ms },
        };
        match snippets::upsert(conn, &row) {
            Ok(_) => outcome.snippets_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("snippet {} upsert: {e}", row.id)),
        }
    }
}

fn apply_known_hosts(
    conn: &impl crate::db::DbAccess,
    text: &str,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
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
            Ok(_) => outcome.known_hosts_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("known_host {host}:{port}: {e}")),
        }
    }
}

// ── v3 child-table apply arms ─────────────────────────────────────
//
// Each helper accepts the same shape the matching composer emits and
// upserts straight through the DAO. Sync mode reuses the same arm —
// the child tables have no LWW gate of their own; the parent's LWW
// (sessions / ssh_keys) decides whether the row stays. Missing
// parents are filtered with a warning rather than an error so a
// partial pull doesn't roll back the whole sync transaction.

fn apply_ssh_key_certificates(
    conn: &impl crate::db::DbAccess,
    json: &str,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome
                .errors
                .push(format!("ssh_key_certificates parse: {e}"));
            return;
        }
    };
    // Cache the live key id set once so the per-row parent lookup
    // is O(1). A cert row whose parent didn't land (filtered out
    // for any reason — dedup, replace-mode wipe, future-version
    // skip) drops with a warning.
    let live_keys: HashSet<String> = match ssh_keys::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| r.id).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("ssh_key_certificates list keys: {e}"));
            return;
        }
    };
    for v in arr {
        let key_id = json_string(&v, "key_id");
        if key_id.is_empty() {
            continue;
        }
        if !live_keys.contains(&key_id) {
            outcome
                .warnings
                .push(format!("ssh_key_certificate {key_id}: parent key absent"));
            continue;
        }
        let certificate = v
            .get("certificate")
            .and_then(|x| x.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|b| b.as_u64().map(|n| n as u8))
                    .collect()
            })
            .unwrap_or_default();
        let valid_after = json_i64(&v, "valid_after");
        let valid_before = json_i64(&v, "valid_before");
        let principals = v
            .get("principals")
            .map(|x| {
                if x.is_string() {
                    x.as_str().unwrap_or("[]").to_string()
                } else {
                    x.to_string()
                }
            })
            .unwrap_or_else(|| "[]".into());
        let critical_options = v
            .get("critical_options")
            .map(|x| {
                if x.is_string() {
                    x.as_str().unwrap_or("{}").to_string()
                } else {
                    x.to_string()
                }
            })
            .unwrap_or_else(|| "{}".into());
        let fingerprint = json_string(&v, "fingerprint");
        let rec = ssh_key_certificates::CertRecord {
            key_id: key_id.clone(),
            certificate,
            valid_after,
            valid_before,
            principals,
            critical_options,
            fingerprint,
        };
        match ssh_key_certificates::upsert(conn, &rec) {
            Ok(_) => outcome.ssh_key_certificates_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("ssh_key_certificate {key_id} upsert: {e}")),
        }
    }
}

fn apply_webdav_session_details(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome
                .errors
                .push(format!("webdav_session_details parse: {e}"));
            return;
        }
    };
    let live_sessions: HashSet<String> = match sessions::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| r.id).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("webdav_session_details list sessions: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        if session_id.is_empty() {
            continue;
        }
        let is_tombstone = v
            .get("tombstone")
            .and_then(|x| x.as_bool())
            .unwrap_or(false);
        // Archive imports never carry tombstones — they're a sync-
        // protocol concern. Drop the row silently rather than apply
        // it as a fake revival.
        if is_tombstone && mode.is_archive() {
            continue;
        }
        if is_tombstone {
            let deleted_at_ms = json_i64_opt(&v, "deleted_at_ms").unwrap_or(now_ms);
            match webdav_sessions::apply_tombstone(conn, &session_id, deleted_at_ms) {
                Ok(_) => outcome.webdav_session_details_applied += 1,
                Err(e) => outcome.errors.push(format!(
                    "webdav_session_details {session_id} tombstone: {e}"
                )),
            }
            continue;
        }
        if !live_sessions.contains(&session_id) {
            outcome.warnings.push(format!(
                "webdav_session_details {session_id}: parent session absent"
            ));
            continue;
        }
        if mode.is_sync() {
            let peer_updated_at = json_i64_opt(&v, "updated_at_ms").unwrap_or(now_ms);
            // LWW gate: skip when the local stamp is at least as
            // fresh as the peer's. The tombstone branch above uses
            // its own gate inside `apply_tombstone`.
            if let Some(local_updated) = webdav_sessions::get_updated_at(conn, &session_id)
                .ok()
                .flatten()
            {
                if peer_updated_at <= local_updated {
                    continue;
                }
            }
        }
        let row = webdav_sessions::WebDavSessionRow {
            session_id: session_id.clone(),
            base_url: json_string(&v, "base_url"),
            username: json_string(&v, "username"),
            auth_method: json_string(&v, "auth_method"),
            self_signed_fingerprint: v
                .get("self_signed_fingerprint")
                .and_then(|x| x.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string()),
        };
        let result = if mode.is_sync() {
            let peer_updated_at = json_i64_opt(&v, "updated_at_ms").unwrap_or(now_ms);
            webdav_sessions::upsert_with_stamp(conn, &row, peer_updated_at)
        } else {
            webdav_sessions::upsert(conn, &row)
        };
        match result {
            Ok(_) => outcome.webdav_session_details_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("webdav_session_details {session_id} upsert: {e}")),
        }
    }
}

fn apply_s3_session_details(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome
                .errors
                .push(format!("s3_session_details parse: {e}"));
            return;
        }
    };
    let live_sessions: HashSet<String> = match sessions::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| r.id).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("s3_session_details list sessions: {e}"));
            return;
        }
    };
    for v in arr {
        let session_id = json_string(&v, "session_id");
        if session_id.is_empty() {
            continue;
        }
        let is_tombstone = v
            .get("tombstone")
            .and_then(|x| x.as_bool())
            .unwrap_or(false);
        if is_tombstone && mode.is_archive() {
            continue;
        }
        if is_tombstone {
            let deleted_at_ms = json_i64_opt(&v, "deleted_at_ms").unwrap_or(now_ms);
            match s3_sessions::apply_tombstone(conn, &session_id, deleted_at_ms) {
                Ok(_) => outcome.s3_session_details_applied += 1,
                Err(e) => outcome
                    .errors
                    .push(format!("s3_session_details {session_id} tombstone: {e}")),
            }
            continue;
        }
        if !live_sessions.contains(&session_id) {
            outcome.warnings.push(format!(
                "s3_session_details {session_id}: parent session absent"
            ));
            continue;
        }
        if mode.is_sync() {
            let peer_updated_at = json_i64_opt(&v, "updated_at_ms").unwrap_or(now_ms);
            if let Some(local_updated) = s3_sessions::get_updated_at(conn, &session_id)
                .ok()
                .flatten()
            {
                if peer_updated_at <= local_updated {
                    continue;
                }
            }
        }
        let row = s3_sessions::S3SessionRow {
            session_id: session_id.clone(),
            access_key_id: json_string(&v, "access_key_id"),
            region: json_string(&v, "region"),
            endpoint: json_string(&v, "endpoint"),
            path_style: v
                .get("path_style")
                .and_then(|x| x.as_bool())
                .unwrap_or(false),
            default_bucket: json_string(&v, "default_bucket"),
            default_prefix: json_string(&v, "default_prefix"),
        };
        let result = if mode.is_sync() {
            let peer_updated_at = json_i64_opt(&v, "updated_at_ms").unwrap_or(now_ms);
            s3_sessions::upsert_with_stamp(conn, &row, peer_updated_at)
        } else {
            s3_sessions::upsert(conn, &row)
        };
        match result {
            Ok(_) => outcome.s3_session_details_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("s3_session_details {session_id} upsert: {e}")),
        }
    }
}

fn apply_sftp_bookmarks(
    conn: &impl crate::db::DbAccess,
    json: &str,
    _mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome.errors.push(format!("sftp_bookmarks parse: {e}"));
            return;
        }
    };
    let live_sessions: HashSet<String> = match sessions::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| r.id).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("sftp_bookmarks list sessions: {e}"));
            return;
        }
    };
    for v in arr {
        let id = json_string(&v, "id");
        let session_id = json_string(&v, "session_id");
        if id.is_empty() || session_id.is_empty() {
            continue;
        }
        if !live_sessions.contains(&session_id) {
            outcome.warnings.push(format!(
                "sftp_bookmark {id}: parent session {session_id} absent"
            ));
            continue;
        }
        let created_at_ms = parse_iso8601_or_now(
            v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
            now_ms,
        );
        let row = sftp_bookmarks::SftpBookmarkRow {
            id: id.clone(),
            session_id,
            remote_path: json_string(&v, "remote_path"),
            label: json_string(&v, "label"),
            created_at_ms,
        };
        match sftp_bookmarks::upsert(conn, &row) {
            Ok(_) => outcome.sftp_bookmarks_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("sftp_bookmark {id} upsert: {e}")),
        }
    }
}

fn apply_port_forward_rules(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let arr = match serde_json::from_str::<Vec<Value>>(json) {
        Ok(a) => a,
        Err(e) => {
            outcome
                .errors
                .push(format!("port_forward_rules parse: {e}"));
            return;
        }
    };
    let live_sessions: HashSet<String> = match sessions::list_all(conn) {
        Ok(rows) => rows.into_iter().map(|r| r.id).collect(),
        Err(e) => {
            outcome
                .errors
                .push(format!("port_forward_rules list sessions: {e}"));
            return;
        }
    };
    // Pre-load local rows for the LWW gate in sync mode. The DAO
    // does not expose a per-id `get_updated_at` because
    // `list_all_with_tombstones` already shapes the column for the
    // composer; reuse it here so the apply path has exactly one
    // source of truth for the local timestamp.
    let local_updated_at: HashMap<String, i64> = if mode.is_sync() {
        match port_forwards::list_all_with_tombstones(conn) {
            Ok(rows) => rows
                .into_iter()
                .map(|(r, _)| (r.id.clone(), r.updated_at_ms))
                .collect(),
            Err(e) => {
                outcome
                    .errors
                    .push(format!("port_forward_rules local snapshot: {e}"));
                return;
            }
        }
    } else {
        HashMap::new()
    };
    for v in arr {
        let id = json_string(&v, "id");
        let session_id = json_string(&v, "session_id");
        if id.is_empty() || session_id.is_empty() {
            continue;
        }
        let is_tombstone = v
            .get("tombstone")
            .and_then(|x| x.as_bool())
            .unwrap_or(false);
        if is_tombstone && mode.is_archive() {
            continue;
        }
        if is_tombstone {
            let deleted_at_ms = json_i64_opt(&v, "deleted_at_ms").unwrap_or(now_ms);
            match port_forwards::apply_tombstone(conn, &id, deleted_at_ms) {
                Ok(_) => outcome.port_forward_rules_applied += 1,
                Err(e) => outcome
                    .errors
                    .push(format!("port_forward_rule {id} tombstone: {e}")),
            }
            continue;
        }
        if !live_sessions.contains(&session_id) {
            outcome.warnings.push(format!(
                "port_forward_rule {id}: parent session {session_id} absent"
            ));
            continue;
        }
        let peer_updated_at = if mode.is_sync() {
            json_i64_opt(&v, "updated_at_ms").unwrap_or(now_ms)
        } else {
            now_ms
        };
        if mode.is_sync() {
            if let Some(local) = local_updated_at.get(&id) {
                if peer_updated_at <= *local {
                    continue;
                }
            }
        }
        let row = port_forwards::PortForwardRuleRow {
            id: id.clone(),
            session_id,
            kind: json_string(&v, "kind"),
            bind_host: json_string(&v, "bind_host"),
            bind_port: json_i64(&v, "bind_port"),
            remote_host: json_string(&v, "remote_host"),
            remote_port: json_i64(&v, "remote_port"),
            description: json_string(&v, "description"),
            enabled: v.get("enabled").and_then(|x| x.as_bool()).unwrap_or(true),
            sort_order: json_i64(&v, "sort_order"),
            created_at_ms: json_i64(&v, "created_at_ms"),
            updated_at_ms: peer_updated_at,
        };
        let result = if mode.is_sync() {
            port_forwards::upsert_with_stamp(conn, &row, peer_updated_at)
        } else {
            port_forwards::upsert(conn, &row)
        };
        match result {
            Ok(_) => outcome.port_forward_rules_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("port_forward_rule {id} upsert: {e}")),
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
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
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
            ssh_key_certificates_json: None,
            webdav_session_details_json: None,
            s3_session_details_json: None,
            sftp_bookmarks_json: None,
            port_forward_rules_json: None,
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
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
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
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
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
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
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
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_tags_applied, 0);
        // Sessions off → also skipped.
        let mut opts = merge_all_options();
        opts.apply_sessions = false;
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_tags_applied, 0);
        // Both on → link applied.
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.session_tags_applied, 1);
        assert_eq!(tags::list_session_tag_ids(&conn, "s1").unwrap(), vec!["t1"]);
    }

    #[test]
    fn apply_folder_tags_resolves_paths_against_freshly_built_folder_tree() {
        let conn = fresh_db();
        // Tag must exist on the receiving side; the import may have
        // staged it via tags.json (gated by apply_tags) and the
        // folder must materialise via sessions.json or
        // empty_folders.json so the path → id map carries it.
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
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"Work/Prod","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            folder_tags_json: Some(
                r#"[{"folder_path":"Work/Prod","tag_id":"t1"}]"#.to_string(),
            ),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.folder_tags_applied, 1);
        // The freshly-minted folder id for "Work/Prod" must carry
        // the tag now.
        let folder_id = folders::list_all(&conn)
            .unwrap()
            .into_iter()
            .find(|f| f.name == "Prod")
            .map(|f| f.id)
            .expect("Prod folder created");
        assert_eq!(
            tags::list_folder_tag_ids(&conn, &folder_id).unwrap(),
            vec!["t1"],
        );
    }

    #[test]
    fn apply_folder_tags_skips_unknown_paths() {
        let conn = fresh_db();
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
        // No sessions / empty_folders ⇒ Work/Prod never materialises;
        // the tag link must be silently dropped, not error.
        let pending = PendingImport {
            folder_tags_json: Some(r#"[{"folder_path":"Work/Prod","tag_id":"t1"}]"#.to_string()),
            ..empty_pending()
        };
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.folder_tags_applied, 0);
        assert!(result.errors.is_empty(), "errors: {:?}", result.errors);
    }

    #[test]
    fn apply_folder_tags_requires_both_sessions_and_tags_toggles() {
        let conn = fresh_db();
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
            sessions_json: Some(
                r#"[{"id":"s1","label":"l","folder":"Work","host":"a","port":22,"user":"u","auth_type":"password"}]"#
                    .to_string(),
            ),
            folder_tags_json: Some(
                r#"[{"folder_path":"Work","tag_id":"t1"}]"#.to_string(),
            ),
            ..empty_pending()
        };
        // Tags off → link skipped.
        let mut opts = merge_all_options();
        opts.apply_tags = false;
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.folder_tags_applied, 0);
        // Sessions off → also skipped (the folder never materialises).
        let mut opts = merge_all_options();
        opts.apply_sessions = false;
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.folder_tags_applied, 0);
        // Both on → link applied.
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
                .unwrap();
        assert_eq!(result.folder_tags_applied, 1);
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
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_snippets_applied, 0);
        let mut opts = merge_all_options();
        opts.apply_sessions = false;
        let result = apply_pending_import_merge(&conn, &pending, &opts, 1_700_000_000_000).unwrap();
        assert_eq!(result.session_snippets_applied, 0);
        let result =
            apply_pending_import_merge(&conn, &pending, &merge_all_options(), 1_700_000_000_000)
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
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
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

    /// Replace mode is all-or-nothing — a per-row apply error
    /// MUST roll the transaction back so the user does not end up
    /// with their original data wiped + a partially-imported new
    /// state on top. Pre-fix shape kept the wipe (and the rows
    /// that did succeed) committed; this test pins the rollback
    /// guarantee on `errors.is_empty() == false`.
    #[test]
    fn replace_mode_rolls_back_on_per_row_apply_error() {
        let mut conn = fresh_db();
        // Pre-seed a session + tag the user must keep on a failed
        // import.
        sessions::upsert(
            &conn,
            &sessions::SessionRow {
                id: "keep-s".into(),
                label: "keep".into(),
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
                id: "keep-t".into(),
                name: "keep".into(),
                color: None,
                created_at_ms: 0,
            },
        )
        .unwrap();

        // Hand the apply driver an unparseable sessions JSON so
        // `apply_sessions` records an error. Replace mode must
        // surface that as a rollback.
        let pending = PendingImport {
            sessions_json: Some("not valid json".to_string()),
            ..empty_pending()
        };
        let mut opts = merge_all_options();
        opts.mode = ImportMode::Replace;
        let result = apply_pending_import(&mut conn, &pending, &opts, 1_700_000_000_000).unwrap();

        assert!(
            result.rolled_back,
            "expected rolled_back flag, got: {result:?}",
        );
        assert!(!result.errors.is_empty(), "errors must propagate");

        // Pre-import data survives — the rollback restored the
        // wipe step too.
        assert!(
            sessions::get(&conn, "keep-s").unwrap().is_some(),
            "pre-import session lost on rollback",
        );
        let surviving_tags = tags::list_all(&conn).unwrap();
        assert!(
            surviving_tags.iter().any(|t| t.id == "keep-t"),
            "pre-import tag lost on rollback",
        );
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
        assert!(tags::list_all(&conn).unwrap().iter().any(|t| t.id == "t2"));
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

    // ── v3 child-table round-trips (archive + sync) ────────────

    /// Seed a session row so child-table FK parents exist before
    /// the round-trip test calls the unified apply driver. Kept
    /// inside the test module so the per-table tests below don't
    /// reach into the prod `db::sessions` constructors directly.
    fn seed_session_id(conn: &Connection, id: &str) {
        sessions::upsert(
            conn,
            &sessions::SessionRow {
                id: id.into(),
                label: id.into(),
                host: "h".into(),
                port: 22,
                user: "u".into(),
                auth_type: "password".into(),
                ..Default::default()
            },
        )
        .unwrap();
    }

    fn seed_key_id(conn: &Connection, id: &str) {
        ssh_keys::upsert(
            conn,
            &ssh_keys::SshKeyRow {
                id: id.into(),
                label: id.into(),
                private_key: "PRIV".into(),
                public_key: "ssh-ed25519 AAAA".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
                pkcs11_uri: None,
                pkcs11_module_path: None,
                pkcs11_token_serial: None,
                pkcs11_object_id: None,
                pkcs11_object_label: None,
                enclave_tag: None,
                hello_credential_name: None,
                tpm_blob: None,
                tpm_handle: None,
                tpm_provider: None,
                tpm_pin_required: false,
                cng_key_name: None,
                keystore_alias: None,
                keystore_strongbox: false,
                keystore_user_auth_required: false,
                keystore_platform: None,
                imported_as_stub: false,
            },
        )
        .unwrap();
    }

    #[test]
    fn apply_ssh_key_certificates_round_trip_under_archive_import_mode() {
        let mut conn = fresh_db();
        seed_key_id(&conn, "k1");
        let pending = PendingImport {
            ssh_key_certificates_json: Some(
                r#"[{
                    "key_id":"k1",
                    "certificate":[1,2,3,4],
                    "valid_after":1700000000,
                    "valid_before":1700086400,
                    "principals":"[\"alice\"]",
                    "critical_options":"{}",
                    "fingerprint":"SHA256:abc"
                }]"#
                .to_string(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.ssh_key_certificates_applied, 1);
        let row = crate::db::ssh_key_certificates::get(&conn, "k1")
            .unwrap()
            .expect("cert landed");
        assert_eq!(row.certificate, vec![1, 2, 3, 4]);
        assert_eq!(row.valid_after, 1_700_000_000);
        assert_eq!(row.fingerprint, "SHA256:abc");
    }

    #[test]
    fn apply_ssh_key_certificates_drops_with_warning_when_parent_absent() {
        // Sync mode through unified entry — parent key NOT seeded so
        // the cert lands on the warning channel, not the error
        // channel (per the plan: a partial pull doesn't roll back).
        let mut conn = fresh_db();
        let pending = PendingImport {
            ssh_key_certificates_json: Some(
                r#"[{"key_id":"orphan","certificate":[0],"valid_after":0,"valid_before":0,"principals":"[]","critical_options":"{}","fingerprint":"x"}]"#.into(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::Sync,
            &ApplyOptions::default(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.ssh_key_certificates_applied, 0);
        assert!(outcome.errors.is_empty());
        assert!(
            outcome
                .warnings
                .iter()
                .any(|w| w.contains("orphan") && w.contains("parent key absent")),
            "warnings: {:?}",
            outcome.warnings,
        );
    }

    #[test]
    fn apply_webdav_session_details_round_trip() {
        let mut conn = fresh_db();
        seed_session_id(&conn, "s1");
        let pending = PendingImport {
            webdav_session_details_json: Some(
                r#"[{"session_id":"s1","base_url":"https://example.com/dav/","username":"alice","auth_method":"basic","credential_secret_id":"session.webdav.s1"}]"#.into(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.webdav_session_details_applied, 1);
        let row = crate::db::webdav_sessions::get(&conn, "s1")
            .unwrap()
            .expect("webdav detail row landed");
        assert_eq!(row.base_url, "https://example.com/dav/");
        assert_eq!(row.auth_method, "basic");
    }

    #[test]
    fn apply_s3_session_details_round_trip() {
        let mut conn = fresh_db();
        seed_session_id(&conn, "s1");
        let pending = PendingImport {
            s3_session_details_json: Some(
                r#"[{
                    "session_id":"s1",
                    "access_key_id":"AKIAEXAMPLE",
                    "region":"us-east-1",
                    "endpoint":"https://s3.example.com",
                    "path_style":true,
                    "default_bucket":"my-bucket",
                    "default_prefix":"logs/",
                    "secret_access_key_secret_id":"session.s3.s1"
                }]"#
                .into(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.s3_session_details_applied, 1);
        let row = crate::db::s3_sessions::get(&conn, "s1")
            .unwrap()
            .expect("s3 detail row landed");
        assert_eq!(row.access_key_id, "AKIAEXAMPLE");
        assert!(row.path_style);
        assert_eq!(row.region, "us-east-1");
    }

    #[test]
    fn apply_sftp_bookmarks_round_trip() {
        let mut conn = fresh_db();
        seed_session_id(&conn, "s1");
        let pending = PendingImport {
            sftp_bookmarks_json: Some(
                r#"[{
                    "id":"bm1",
                    "session_id":"s1",
                    "remote_path":"/var/log",
                    "label":"logs",
                    "created_at":"2026-04-26T00:00:00.000Z"
                }]"#
                .into(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.sftp_bookmarks_applied, 1);
        let rows = crate::db::sftp_bookmarks::list_for_session(&conn, "s1").unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].remote_path, "/var/log");
    }

    #[test]
    fn apply_port_forward_rules_round_trip() {
        let mut conn = fresh_db();
        seed_session_id(&conn, "s1");
        let pending = PendingImport {
            port_forward_rules_json: Some(
                r#"[{
                    "id":"pf1",
                    "session_id":"s1",
                    "kind":"local",
                    "bind_host":"127.0.0.1",
                    "bind_port":8080,
                    "remote_host":"app.example.com",
                    "remote_port":80,
                    "description":"webdev",
                    "enabled":true,
                    "sort_order":0,
                    "created_at_ms":1700000000000
                }]"#
                .into(),
            ),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert_eq!(outcome.port_forward_rules_applied, 1);
        let rows = crate::db::port_forwards::list_for_session(&conn, "s1").unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].bind_port, 8080);
        assert_eq!(rows[0].remote_host, "app.example.com");
    }

    // ── Stage 3: SSH key round-trip per backend ────────────────

    fn round_trip_key_through_apply(backend: &str, extra_fields: &str) -> ssh_keys::SshKeyRow {
        let mut conn = fresh_db();
        let json = format!(
            r#"[{{
                "id":"k1",
                "label":"my-key",
                "public_key":"ssh-ed25519 AAAA...",
                "key_type":"ssh-ed25519",
                "is_generated":false,
                "created_at":"2026-04-26T00:00:00.000Z",
                "backend":"{backend}"
                {extra_fields}
            }}]"#
        );
        let pending = PendingImport {
            keys_json: Some(json),
            ..empty_pending()
        };
        let mut outcome = ApplyOutcome::default();
        apply_pending_to_db(
            &mut conn,
            &pending,
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            &merge_all_options(),
            1_700_000_000_000,
            &mut outcome,
        )
        .unwrap();
        assert!(outcome.errors.is_empty(), "errors: {:?}", outcome.errors);
        ssh_keys::get(&conn, "k1").unwrap().expect("key row landed")
    }

    #[test]
    fn apply_ssh_key_software_round_trips_private_key() {
        let row = round_trip_key_through_apply("software", r#", "private_key":"PRIVATE-BYTES""#);
        assert_eq!(row.backend, ssh_keys::KeyBackend::Software);
        assert_eq!(row.private_key, "PRIVATE-BYTES");
        assert!(!row.imported_as_stub);
    }

    #[test]
    fn apply_ssh_key_fido2_round_trips_credential_id_and_application() {
        let row = round_trip_key_through_apply(
            "fido2",
            r#", "credential_id":[1,2,3,4], "application_string":"ssh:", "has_user_verification":true"#,
        );
        assert_eq!(row.backend, ssh_keys::KeyBackend::Fido2);
        assert_eq!(row.credential_id, Some(vec![1, 2, 3, 4]));
        assert_eq!(row.application_string.as_deref(), Some("ssh:"));
        assert!(row.has_user_verification);
        assert!(!row.imported_as_stub);
        assert!(
            row.private_key.is_empty(),
            "FIDO2 rows carry no private PEM"
        );
    }

    #[test]
    fn apply_ssh_key_pkcs11_round_trips_uri_and_object_ingredients_but_never_module_path() {
        let row = round_trip_key_through_apply(
            "pkcs11",
            r#", "pkcs11_uri":"pkcs11:token=YubiKey", "pkcs11_token_serial":"01ABCDEF", "pkcs11_object_id":[10,20], "pkcs11_object_label":"my-piv-cert""#,
        );
        assert_eq!(row.backend, ssh_keys::KeyBackend::Pkcs11);
        assert_eq!(row.pkcs11_uri.as_deref(), Some("pkcs11:token=YubiKey"),);
        assert_eq!(row.pkcs11_token_serial.as_deref(), Some("01ABCDEF"));
        assert_eq!(row.pkcs11_object_id, Some(vec![10, 20]));
        assert_eq!(row.pkcs11_object_label.as_deref(), Some("my-piv-cert"));
        // Module path is the per-host install location and is
        // resolved locally on first use — never travels through
        // the archive.
        assert!(row.pkcs11_module_path.is_none());
        assert!(!row.imported_as_stub);
    }

    #[test]
    fn apply_ssh_key_enclave_lands_as_stub_with_public_half_only() {
        let row = round_trip_key_through_apply("enclave", "");
        assert_eq!(row.backend, ssh_keys::KeyBackend::Enclave);
        assert!(row.imported_as_stub, "Apple SE row must land as stub");
        assert!(row.private_key.is_empty());
        assert!(row.enclave_tag.is_none());
    }

    #[test]
    fn apply_ssh_key_hello_lands_as_stub_with_public_half_only() {
        let row = round_trip_key_through_apply("hello", "");
        assert_eq!(row.backend, ssh_keys::KeyBackend::Hello);
        assert!(row.imported_as_stub);
        assert!(row.hello_credential_name.is_none());
    }

    #[test]
    fn apply_ssh_key_tpm_lands_as_stub_with_public_half_only() {
        let row = round_trip_key_through_apply("tpm", "");
        assert_eq!(row.backend, ssh_keys::KeyBackend::Tpm);
        assert!(row.imported_as_stub);
        assert!(row.tpm_blob.is_none());
        assert!(row.tpm_handle.is_none());
    }

    #[test]
    fn apply_ssh_key_keystore_lands_as_stub_with_public_half_only() {
        let row = round_trip_key_through_apply("keystore", "");
        assert_eq!(row.backend, ssh_keys::KeyBackend::Keystore);
        assert!(row.imported_as_stub);
        assert!(row.keystore_alias.is_none());
    }

    // ── Stage 1: cross-mode unified-entry parity ───────────────

    /// Exercise the same Pending fixture through both
    /// ArchiveImport and Sync modes; assert the per-mode DB state
    /// matches the documented shape. Archive-import always upserts;
    /// Sync gates on LWW. The fixture lands one fresh row that has
    /// no local equivalent — both modes must apply it.
    #[test]
    fn apply_pending_to_db_round_trip_through_both_modes() {
        let session_json = r#"[{
            "id":"s1",
            "label":"prod",
            "host":"h.example.com",
            "port":22,
            "user":"deploy",
            "auth_type":"password",
            "password":"",
            "key_path":"",
            "key_data":"",
            "passphrase":"",
            "created_at":"2026-04-26T00:00:00.000Z",
            "updated_at":"2026-04-26T00:00:00.000Z"
        }]"#;
        for mode in &[
            ApplyMode::ArchiveImport {
                replace_mode: false,
            },
            ApplyMode::Sync,
        ] {
            let mut conn = fresh_db();
            let pending = PendingImport {
                sessions_json: Some(session_json.into()),
                ..empty_pending()
            };
            let mut outcome = ApplyOutcome::default();
            apply_pending_to_db(
                &mut conn,
                &pending,
                *mode,
                &ApplyOptions {
                    apply_sessions: true,
                    ..ApplyOptions::default()
                },
                1_700_000_000_000,
                &mut outcome,
            )
            .unwrap_or_else(|e| panic!("{mode:?} apply: {e:?}"));
            assert_eq!(outcome.sessions_applied, 1, "{mode:?}");
            let row = sessions::get(&conn, "s1").unwrap().expect("row");
            assert_eq!(row.label, "prod", "{mode:?}");
        }
    }
}
