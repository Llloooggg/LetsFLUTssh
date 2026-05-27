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
//!   stubs because device-bound backends never travel between
//!   installs.
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

use super::iso8601::{parse_iso8601_opt, parse_iso8601_or_now};
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
    /// driven by a user-initiated `.lfs` import flow. Gates per-mode
    /// toggle checks (sync ignores `ApplyOptions` toggles and always
    /// applies every entry the peer carried).
    fn is_archive(self) -> bool {
        matches!(self, Self::ArchiveImport { .. })
    }

    fn is_sync(self) -> bool {
        matches!(self, Self::Sync)
    }
}

/// Unified counters surfaced by [`apply_pending_to_db`]. Carries
/// every metric both codepaths report (`ApplyResult` for archive
/// import, `MergeOutcome` for sync merge). Projection helpers
/// ([`ApplyOutcome::to_apply_result`] /
/// [`ApplyOutcome::to_merge_outcome`]) build the per-mode views
/// callers consume.
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
    /// M2M link rows (`session_tags`, `folder_tags`,
    /// `session_snippets`) dropped during apply — either because the
    /// link's target was not part of the import set (the insert
    /// FK-fails, common in a partial Merge import) or because the row
    /// was malformed. In Merge mode the link is silently dropped and
    /// the import continues, so this counter is the only signal the
    /// user gets that some associations did not survive.
    pub links_skipped: i64,
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
            links_skipped: self.links_skipped,
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
    /// True → write every `.cast` entry from the archive's
    /// `recordings/` directory under
    /// `<recordings_root>/imported/<session_id>/<file_name>` via
    /// [`apply_recordings_to_filesystem`]. False skips the
    /// extraction even if the staged `PendingImport.recordings`
    /// is non-empty.
    pub apply_recordings: bool,
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
    /// M2M link rows dropped during apply (target not in the import
    /// set, or malformed). See [`ApplyOutcome::links_skipped`].
    pub links_skipped: i64,
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

/// Per-kind apply toggles resolved from the optional [`ApplyOptions`].
/// Sync ignores `options` — the orchestrator always ships every entry
/// the peer carried — so every flag defaults to `true`. Archive-import
/// callers gate per-kind through the toggle set.
#[derive(Debug, Clone, Copy)]
struct WantFlags {
    keys: bool,
    sessions: bool,
    tags: bool,
    snippets: bool,
    known_hosts: bool,
}

impl WantFlags {
    fn from_options(options: Option<&ApplyOptions>) -> Self {
        WantFlags {
            keys: options.is_none_or(|o| o.apply_keys),
            sessions: options.is_none_or(|o| o.apply_sessions),
            tags: options.is_none_or(|o| o.apply_tags),
            snippets: options.is_none_or(|o| o.apply_snippets),
            known_hosts: options.is_none_or(|o| o.apply_known_hosts),
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
    let want = WantFlags::from_options(options);

    if want.keys {
        if let Some(json) = pending.keys_json.as_deref() {
            apply_keys(conn, json, mode, now_ms, outcome);
        }
    }
    // Apply folders + sessions together so session.folder_id
    // resolves through the imported folder tree; the resulting
    // path → id map feeds the folder-tag arm below.
    let folder_path_to_id =
        apply_sessions_phase(conn, pending, mode, want.sessions, now_ms, outcome);
    apply_tags_phase(
        conn,
        pending,
        mode,
        want,
        &folder_path_to_id,
        now_ms,
        outcome,
    );
    apply_snippets_phase(conn, pending, mode, want, now_ms, outcome);
    if want.known_hosts {
        if let Some(text) = pending.known_hosts_text.as_deref() {
            apply_known_hosts(conn, text, now_ms, outcome);
        }
    }
    apply_child_tables(
        conn,
        pending,
        mode,
        want.keys,
        want.sessions,
        now_ms,
        outcome,
    );
}

/// Apply tags, then the session-tag and folder-tag join tables. The
/// join arms only run when both sessions and tags were requested, so a
/// session-less or tag-less import leaves the link tables untouched.
fn apply_tags_phase(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    mode: ApplyMode,
    want: WantFlags,
    folder_path_to_id: &HashMap<String, String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    if want.tags {
        if let Some(json) = pending.tags_json.as_deref() {
            apply_tags(conn, json, mode, now_ms, outcome);
        }
    }
    if !(want.sessions && want.tags) {
        return;
    }
    if let Some(json) = pending.session_tags_json.as_deref() {
        apply_session_tags(conn, json, outcome);
    }
    if let Some(json) = pending.folder_tags_json.as_deref() {
        apply_folder_tags(conn, json, folder_path_to_id, outcome);
    }
}

/// Apply snippets, then the session-snippet join table. The join arm
/// only runs when both sessions and snippets were requested.
fn apply_snippets_phase(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    mode: ApplyMode,
    want: WantFlags,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    if want.snippets {
        if let Some(json) = pending.snippets_json.as_deref() {
            apply_snippets(conn, json, mode, now_ms, outcome);
        }
    }
    if want.sessions && want.snippets {
        if let Some(json) = pending.session_snippets_json.as_deref() {
            apply_session_snippets(conn, json, outcome);
        }
    }
}

/// Apply the folder tree, sessions, and empty folders, returning the
/// folder path → id map the folder-tag arm resolves against. A no-op
/// (empty map) when `want_sessions` is false or the bundle carries no
/// `sessions.json` / `empty_folders.json`.
fn apply_sessions_phase(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    mode: ApplyMode,
    want_sessions: bool,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) -> HashMap<String, String> {
    let mut folder_path_to_id: HashMap<String, String> = HashMap::new();
    if !want_sessions {
        return folder_path_to_id;
    }
    if let Some(json) = pending.sessions_json.as_deref() {
        folder_path_to_id = apply_folder_tree(conn, json, mode, now_ms, outcome);
        apply_sessions(conn, json, mode, &folder_path_to_id, now_ms, outcome);
    }
    if let Some(json) = pending.empty_folders_json.as_deref() {
        apply_empty_folders(conn, json, &mut folder_path_to_id, now_ms, outcome);
    }
    folder_path_to_id
}

/// Apply the v3 child-table arms (certificates, WebDAV / S3 session
/// details, SFTP bookmarks, port-forward rules). Each is a no-op when
/// its JSON entry is absent from the pending bundle (e.g. a manual
/// export that did not include the section).
fn apply_child_tables(
    conn: &impl crate::db::DbAccess,
    pending: &PendingImport,
    mode: ApplyMode,
    want_keys: bool,
    want_sessions: bool,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
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
        record_clear(sftp_bookmarks::delete_all(conn), "sftp_bookmarks", outcome);
        record_clear(
            port_forwards::delete_all(conn),
            "port_forward_rules",
            outcome,
        );
        record_clear(
            webdav_sessions::delete_all(conn),
            "webdav_session_details",
            outcome,
        );
        record_clear(s3_sessions::delete_all(conn), "s3_session_details", outcome);
        record_clear(sessions::delete_all(conn), "sessions", outcome);
        record_clear(folders::delete_all(conn), "folders", outcome);
    }
    if options.apply_tags {
        record_clear(tags::delete_all(conn), "tags", outcome);
    }
    if options.apply_snippets {
        record_clear(snippets::delete_all(conn), "snippets", outcome);
    }
    if options.apply_known_hosts {
        record_clear(known_hosts::clear_all(conn), "known_hosts", outcome);
    }
}

/// Push a `replace clear <kind>: <e>` error onto `outcome` when a
/// replace-mode table wipe fails. A `Ok` result is a no-op.
fn record_clear(result: Result<usize, Error>, kind: &str, outcome: &mut ApplyOutcome) {
    if let Err(e) = result {
        outcome.errors.push(format!("replace clear {kind}: {e}"));
    }
}

fn apply_folder_tree(
    conn: &impl crate::db::DbAccess,
    sessions_json: &str,
    mode: ApplyMode,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) -> HashMap<String, String> {
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
    let mut sorted: Vec<String> = paths.into_iter().collect();
    sorted.sort();
    // Sync mode reuses local folders by path (so a peer's
    // "Production" doesn't mint a duplicate folder on every pull).
    // Archive import always inserts fresh ids — that's the
    // pre-unification behaviour, kept because import is a
    // user-initiated bulk operation that the user has reviewed.
    if mode.is_sync() {
        ensure_folder_paths_sync(conn, &sorted, now_ms, outcome)
    } else {
        let mut path_to_id: HashMap<String, String> = HashMap::new();
        let mut sort_order: i64 = 0;
        for path in &sorted {
            materialise_folder_path(
                conn,
                path,
                &mut path_to_id,
                &mut sort_order,
                now_ms,
                outcome,
                "folder",
            );
        }
        path_to_id
    }
}

/// Sync-mode folder resolution — reuse the local folder tree by path
/// via `folders::ensure_folder_path` rather than minting fresh ids,
/// so a peer's repeated pulls don't duplicate the same folder.
fn ensure_folder_paths_sync(
    conn: &impl crate::db::DbAccess,
    sorted: &[String],
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) -> HashMap<String, String> {
    let mut out: HashMap<String, String> = HashMap::new();
    for path in sorted {
        if path.is_empty() || out.contains_key(path) {
            continue;
        }
        match folders::ensure_folder_path(conn, path, now_ms) {
            Ok(Some(id)) => {
                out.insert(path.clone(), id);
            }
            Ok(None) => {}
            Err(e) => outcome
                .errors
                .push(format!("sync merge folder ensure: {e}")),
        }
    }
    out
}

/// Walk a `/`-separated folder path from root → leaf, minting a
/// fresh id for each segment not yet in `path_to_id` so each child's
/// `parent_id` resolves before it lands. `err_label` distinguishes
/// the `folder` vs `empty_folder` upsert-error message. Mutates
/// `path_to_id` / `sort_order` / `outcome` in place.
fn materialise_folder_path(
    conn: &impl crate::db::DbAccess,
    path: &str,
    path_to_id: &mut HashMap<String, String>,
    sort_order: &mut i64,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
    err_label: &str,
) {
    use rand::Rng;
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
        warn_if_windows_reserved_folder_label(seg);
        let mut bytes = [0u8; 16];
        rand::rng().fill_bytes(&mut bytes);
        let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let row = folders::FolderRow {
            id: id.clone(),
            name: seg.to_string(),
            parent_id: parent_id.clone(),
            sort_order: *sort_order,
            collapsed: false,
            created_at_ms: now_ms,
        };
        *sort_order += 1;
        match folders::upsert(conn, &row) {
            Ok(_) => {
                outcome.folders_applied += 1;
                path_to_id.insert(accum.clone(), id.clone());
                parent_id = Some(id);
            }
            Err(e) => {
                outcome
                    .errors
                    .push(format!("{err_label} {accum} upsert: {e}"));
                parent_id = None;
            }
        }
    }
}

/// Emit a soft warning when an imported folder label collides with
/// a Windows-reserved device name (`CON`, `PRN`, `AUX`, `NUL`,
/// `COM1-9`, `LPT1-9`). Folder labels are tree display strings, not
/// filesystem paths — Win32's reserved-name handling cannot apply,
/// so the warning is advisory only and the row imports normally.
/// The Windows UI may still render the label oddly when the user
/// later exports / drags / copies the name into a path context.
fn warn_if_windows_reserved_folder_label(label: &str) {
    if is_windows_reserved_name(label) {
        crate::app_log_warn!(
            "Archive",
            "folder label {label} matches Windows-reserved name; may render oddly on Windows"
        );
    }
}

/// Case-insensitive match against the Win32 reserved device names
/// (`CON`, `PRN`, `AUX`, `NUL`, `COM1`..`COM9`, `LPT1`..`LPT9`).
/// `COM0` / `LPT0` are NOT reserved on modern Windows (validated
/// against the MS-DOS device list); the digit must be `1`..`9`.
fn is_windows_reserved_name(label: &str) -> bool {
    // Strip a trailing extension — Windows treats `con.txt` as
    // reserved too because legacy CMD strips before resolution.
    let bare = match label.find('.') {
        Some(dot) => &label[..dot],
        None => label,
    };
    let upper = bare.to_ascii_uppercase();
    matches!(upper.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || matches_numbered_device(&upper, "COM")
        || matches_numbered_device(&upper, "LPT")
}

fn matches_numbered_device(upper: &str, prefix: &str) -> bool {
    let Some(tail) = upper.strip_prefix(prefix) else {
        return false;
    };
    if tail.len() != 1 {
        return false;
    }
    matches!(tail.as_bytes()[0], b'1'..=b'9')
}

fn apply_empty_folders(
    conn: &impl crate::db::DbAccess,
    json: &str,
    path_to_id: &mut HashMap<String, String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
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
        materialise_folder_path(
            conn,
            &path,
            path_to_id,
            &mut sort_order,
            now_ms,
            outcome,
            "empty_folder",
        );
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
            outcome.links_skipped += 1;
            continue;
        }
        match tags::link_session_tag(conn, &session_id, &tag_id) {
            Ok(_) => outcome.session_tags_applied += 1,
            Err(e) => {
                outcome.links_skipped += 1;
                outcome
                    .errors
                    .push(format!("session_tag {session_id}↔{tag_id}: {e}"));
            }
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
            outcome.links_skipped += 1;
            continue;
        }
        let Some(folder_id) = path_to_id.get(&folder_path) else {
            // Path was not materialised this import — sessions for
            // it weren't applied and it wasn't in empty_folders.
            // Drop the link: it belongs to a folder the user chose
            // not to import. Counted as a skipped link.
            outcome.links_skipped += 1;
            continue;
        };
        match tags::link_folder_tag(conn, folder_id, &tag_id) {
            Ok(_) => outcome.folder_tags_applied += 1,
            Err(e) => {
                outcome.links_skipped += 1;
                outcome
                    .errors
                    .push(format!("folder_tag {folder_path}↔{tag_id}: {e}"));
            }
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
            outcome.links_skipped += 1;
            continue;
        }
        match snippets::link_session_snippet(conn, &session_id, &snippet_id) {
            Ok(_) => outcome.session_snippets_applied += 1,
            Err(e) => {
                outcome.links_skipped += 1;
                outcome
                    .errors
                    .push(format!("session_snippet {session_id}↔{snippet_id}: {e}"));
            }
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
        apply_one_session(conn, &v, mode, folder_path_to_id, &local, now_ms, outcome);
    }
}

/// Apply a single session row from the staged JSON. Handles the
/// missing-id guard, tombstone branch, sync LWW gate, and upsert —
/// the per-row arm of [`apply_sessions`].
fn apply_one_session(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    folder_path_to_id: &HashMap<String, String>,
    local: &HashMap<String, sessions::SessionRow>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    if id.is_empty() {
        // Archive imports report; sync skips silently (peer ships
        // garbage shouldn't block the rest of the merge).
        if mode.is_archive() {
            outcome.errors.push("session row missing id".to_string());
        }
        return;
    }
    if is_tombstone(v) {
        // Archive imports never carry tombstones — they're a sync-
        // protocol concern. Drop the row silently rather than apply
        // it as a fake revival.
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match sessions::apply_tombstone(conn, &id, deleted_at_ms) {
                Ok(_) => outcome.sessions_applied += 1,
                Err(e) => outcome.errors.push(format!("session {id} tombstone: {e}")),
            }
        }
        return;
    }
    let peer_updated_at = if mode.is_sync() {
        // Sync LWW: a missing / malformed peer stamp must LOSE,
        // not win. Default to 0 (oldest) so it never clobbers a
        // real local `updated_at`; defaulting to `now_ms` here
        // would make every unstamped peer row overwrite local.
        parse_iso8601_opt(v.get("updated_at").and_then(|x| x.as_str()).unwrap_or("")).unwrap_or(0)
    } else {
        now_ms
    };
    // The local row's tombstone counts as part of the LWW timestamp
    // via `updated_at_ms`.
    if mode.is_sync() && lww_peer_loses(peer_updated_at, local.get(&id).map(|r| r.updated_at_ms)) {
        return;
    }
    let row = build_session_row(v, mode, folder_path_to_id, id, peer_updated_at, now_ms);
    match sessions::upsert(conn, &row) {
        Ok(_) => outcome.sessions_applied += 1,
        Err(e) => outcome
            .errors
            .push(format!("session {} upsert: {e}", row.id)),
    }
}

/// Build a [`sessions::SessionRow`] from the wire-format JSON value.
/// The mode flips the per-field divergences between archive import
/// and sync (notes, extras default, port default).
fn build_session_row(
    v: &Value,
    mode: ApplyMode,
    folder_path_to_id: &HashMap<String, String>,
    id: String,
    peer_updated_at: i64,
    now_ms: i64,
) -> sessions::SessionRow {
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
    sessions::SessionRow {
        id,
        label: json_string(v, "label"),
        folder_id,
        kind,
        host: json_string(v, "host"),
        port: if mode.is_sync() {
            json_i64_opt(v, "port").unwrap_or(22)
        } else {
            json_i64(v, "port")
        },
        user: json_string(v, "user"),
        auth_type: json_string(v, "auth_type"),
        password: json_string(v, "password"),
        key_path: json_string(v, "key_path"),
        key_data: json_string(v, "key_data"),
        key_id: v
            .get("key_id")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(String::from),
        passphrase: json_string(v, "passphrase"),
        sort_order: 0,
        // Sync mode doesn't ship `notes`; archive imports do.
        // Keep both behaviours faithful: archive reads the field,
        // sync leaves it empty.
        notes: if mode.is_sync() {
            String::new()
        } else {
            json_string(v, "notes")
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
    }
}

fn json_i64_opt(v: &Value, key: &str) -> Option<i64> {
    v.get(key).and_then(|x| x.as_i64())
}

/// Whether a staged row carries the sync `tombstone` flag. Defaults
/// to `false` when the field is absent or non-boolean.
fn is_tombstone(v: &Value) -> bool {
    v.get("tombstone")
        .and_then(|x| x.as_bool())
        .unwrap_or(false)
}

/// Sync LWW gate: the peer row loses when a local stamp is present and
/// at least as fresh. Strict-greater wins, so a tie keeps local state.
/// `None` local stamp means no local row exists — the peer always
/// applies.
fn lww_peer_loses(peer_ts: i64, local_ts: Option<i64>) -> bool {
    matches!(local_ts, Some(local) if peer_ts <= local)
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
/// `software` because device-bound backends never travel between
/// installs.
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
        apply_one_key_sync(conn, &v, &local, now_ms, outcome);
    }
}

/// Sync-mode per-key arm — id guard, tombstone replay, LWW gate on
/// `created_at`, then upsert. Extracted from [`apply_keys_sync`].
fn apply_one_key_sync(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    local: &HashMap<String, ssh_keys::SshKeyRow>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    if id.is_empty() {
        return;
    }
    // A deleted key must not resurrect on a peer. Apply the
    // tombstone through the DAO's own LWW gate (peer
    // `deleted_at_ms` must beat the local `created_at`).
    let is_tombstone = v
        .get("tombstone")
        .and_then(|x| x.as_bool())
        .unwrap_or(false);
    if is_tombstone {
        let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
        match ssh_keys::apply_tombstone(conn, &id, deleted_at_ms) {
            Ok(_) => outcome.keys_applied += 1,
            Err(e) => outcome
                .errors
                .push(format!("sync merge key {id} tombstone: {e}")),
        }
        return;
    }
    // Sync LWW key on `created_at` (keys carry no `updated_at`);
    // a missing / malformed stamp defaults to 0 so it loses to a
    // real local row instead of winning via `now_ms`.
    let peer_ts =
        parse_iso8601_opt(v.get("created_at").and_then(|x| x.as_str()).unwrap_or("")).unwrap_or(0);
    if let Some(local_row) = local.get(&id) {
        if peer_ts <= local_row.created_at_ms {
            return;
        }
    }
    let row = match build_key_row(v, now_ms) {
        Ok(mut r) => {
            r.id = id.clone();
            r.created_at_ms = peer_ts;
            r
        }
        Err(msg) => {
            outcome.errors.push(format!("sync merge key {id}: {msg}"));
            return;
        }
    };
    match ssh_keys::upsert(conn, &row) {
        Ok(_) => outcome.keys_applied += 1,
        Err(e) => outcome.errors.push(format!("sync merge key {id}: {e}")),
    }
}

/// Build an `SshKeyRow` from the wire-format JSON value. Every
/// cross-device row is pinned to [`ssh_keys::KeyBackend::Software`]
/// — device-bound backends (FIDO2 / PKCS#11) are hardware-resident
/// and never travel between installs, so an imported key always
/// lands as a software key.
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
        apply_one_tag(conn, &v, mode, &local, now_ms, outcome);
    }
}

/// Apply a single tag row — tombstone handling, id / name guards,
/// sync LWW gate, then upsert. The per-row arm of [`apply_tags`].
fn apply_one_tag(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    local: &HashMap<String, tags::TagRow>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    let name = json_string(v, "name");
    if is_tombstone(v) {
        // Archive imports never carry tombstones; drop silently. A
        // tag deletion on a peer must not resurrect here, so the
        // sync path routes through the DAO's LWW-gated tombstone.
        if mode.is_sync() && !id.is_empty() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match tags::apply_tombstone(conn, &id, deleted_at_ms) {
                Ok(_) => outcome.tags_applied += 1,
                Err(e) => outcome.errors.push(format!("tag {id} tombstone: {e}")),
            }
        }
        return;
    }
    // Archive import: a missing `created_at` is informational →
    // default to `now`. Sync LWW keys on `created_at`, so a
    // missing peer stamp defaults to 0 to LOSE the merge rather
    // than win via `now`.
    let peer_ts = parse_iso8601_opt(v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""))
        .unwrap_or(if mode.is_sync() { 0 } else { now_ms });
    // A tag needs both id and name; the empty case is skipped in
    // either mode.
    if id.is_empty() || name.is_empty() {
        return;
    }
    if mode.is_sync() && lww_peer_loses(peer_ts, local.get(&id).map(|r| r.created_at_ms)) {
        return;
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
        apply_one_snippet(conn, &v, mode, &local, now_ms, outcome);
    }
}

/// Apply a single snippet row — id / title guards, tombstone replay,
/// sync LWW gate on `updated_at`, then upsert. The per-row arm of
/// [`apply_snippets`].
fn apply_one_snippet(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    local: &HashMap<String, snippets::SnippetRow>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    let title = json_string(v, "title");
    if id.is_empty() {
        return;
    }
    if is_tombstone(v) {
        // Archive imports never carry tombstones; drop silently. A
        // snippet deletion on a peer routes through the DAO's
        // LWW-gated tombstone so it can't resurrect.
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match snippets::apply_tombstone(conn, &id, deleted_at_ms) {
                Ok(_) => outcome.snippets_applied += 1,
                Err(e) => outcome.errors.push(format!("snippet {id} tombstone: {e}")),
            }
        }
        return;
    }
    if !mode.is_sync() && title.is_empty() {
        return;
    }
    // Only consumed under sync (the `updated_at_ms` assignment
    // below uses `now_ms` for archive imports). A missing peer
    // stamp defaults to 0 so it loses the LWW gate instead of
    // winning via `now_ms`.
    let peer_updated =
        parse_iso8601_opt(v.get("updated_at").and_then(|x| x.as_str()).unwrap_or("")).unwrap_or(0);
    if mode.is_sync() && lww_peer_loses(peer_updated, local.get(&id).map(|r| r.updated_at_ms)) {
        return;
    }
    let row = snippets::SnippetRow {
        id: id.clone(),
        title,
        command: json_string(v, "command"),
        description: json_string(v, "description"),
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

fn apply_known_hosts(
    conn: &impl crate::db::DbAccess,
    text: &str,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
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
        // Validate base64 at import time so a corrupt key body
        // does not sit in the DB until the next connect attempt
        // surfaces it as a TOFU mismatch.
        if key_base64.is_empty() || STANDARD.decode(key_base64).is_err() {
            crate::app_log_warn!(
                "ArchiveKnownHosts",
                "skipping archive known_hosts row with invalid base64 key body"
            );
            outcome
                .warnings
                .push("known_hosts row skipped: invalid base64 key body".into());
            continue;
        }
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
        // `principals` rides through archives either as a JSON
        // array (the canonical shape, as written by the export
        // path) or as a JSON-encoded string (legacy interim shape).
        // Parse both into the typed `Vec<String>` the DAO carries.
        let principals: Vec<String> = match v.get("principals") {
            Some(x) if x.is_array() => x
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|e| e.as_str().map(str::to_owned))
                        .collect()
                })
                .unwrap_or_default(),
            Some(x) if x.is_string() => {
                serde_json::from_str::<Vec<String>>(x.as_str().unwrap_or("[]")).unwrap_or_default()
            }
            _ => Vec::new(),
        };
        // Same dual-shape decode for `critical_options` → typed
        // `BTreeMap<String, String>`.
        let critical_options: std::collections::BTreeMap<String, String> =
            match v.get("critical_options") {
                Some(x) if x.is_object() => x
                    .as_object()
                    .map(|m| {
                        m.iter()
                            .filter_map(|(k, val)| val.as_str().map(|s| (k.clone(), s.to_owned())))
                            .collect()
                    })
                    .unwrap_or_default(),
                Some(x) if x.is_string() => serde_json::from_str::<
                    std::collections::BTreeMap<String, String>,
                >(x.as_str().unwrap_or("{}"))
                .unwrap_or_default(),
                _ => std::collections::BTreeMap::new(),
            };
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
        apply_one_webdav_session_detail(conn, &v, mode, &live_sessions, now_ms, outcome);
    }
}

/// Apply a single `webdav_session_details` row — id guard, tombstone
/// replay, absent-parent warning, sync LWW gate, then stamped upsert.
fn apply_one_webdav_session_detail(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    live_sessions: &HashSet<String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let session_id = json_string(v, "session_id");
    if session_id.is_empty() {
        return;
    }
    if is_tombstone(v) {
        // Archive imports never carry tombstones — they're a sync-
        // protocol concern. Drop the row silently rather than apply
        // it as a fake revival.
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match webdav_sessions::apply_tombstone(conn, &session_id, deleted_at_ms) {
                Ok(_) => outcome.webdav_session_details_applied += 1,
                Err(e) => outcome.errors.push(format!(
                    "webdav_session_details {session_id} tombstone: {e}"
                )),
            }
        }
        return;
    }
    if !live_sessions.contains(&session_id) {
        outcome.warnings.push(format!(
            "webdav_session_details {session_id}: parent session absent"
        ));
        return;
    }
    if mode.is_sync() {
        // LWW gate: skip when the local stamp is at least as
        // fresh as the peer's. The tombstone branch above uses
        // its own gate inside `apply_tombstone`.
        let peer_updated_at = json_i64_opt(v, "updated_at_ms").unwrap_or(0);
        let local_updated = webdav_sessions::get_updated_at(conn, &session_id)
            .ok()
            .flatten();
        if lww_peer_loses(peer_updated_at, local_updated) {
            return;
        }
    }
    let row = webdav_sessions::WebDavSessionRow {
        session_id: session_id.clone(),
        base_url: json_string(v, "base_url"),
        username: json_string(v, "username"),
        auth_method: json_string(v, "auth_method"),
        trusted_cert_pem: v
            .get("trusted_cert_pem")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        insecure_skip_verify: v
            .get("insecure_skip_verify")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
    };
    let result = if mode.is_sync() {
        // Stored stamp: a row that passed the LWW gate is being
        // applied now, so a missing peer stamp falls back to
        // `now_ms` (the gate above already used 0 so an unstamped
        // peer can't *win* over a newer local row).
        let peer_updated_at = json_i64_opt(v, "updated_at_ms").unwrap_or(now_ms);
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
        apply_one_s3_session_detail(conn, &v, mode, &live_sessions, now_ms, outcome);
    }
}

/// Apply a single `s3_session_details` row — id guard, tombstone
/// replay, absent-parent warning, sync LWW gate, then stamped upsert.
fn apply_one_s3_session_detail(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    live_sessions: &HashSet<String>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let session_id = json_string(v, "session_id");
    if session_id.is_empty() {
        return;
    }
    if is_tombstone(v) {
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match s3_sessions::apply_tombstone(conn, &session_id, deleted_at_ms) {
                Ok(_) => outcome.s3_session_details_applied += 1,
                Err(e) => outcome
                    .errors
                    .push(format!("s3_session_details {session_id} tombstone: {e}")),
            }
        }
        return;
    }
    if !live_sessions.contains(&session_id) {
        outcome.warnings.push(format!(
            "s3_session_details {session_id}: parent session absent"
        ));
        return;
    }
    if mode.is_sync() {
        let peer_updated_at = json_i64_opt(v, "updated_at_ms").unwrap_or(0);
        let local_updated = s3_sessions::get_updated_at(conn, &session_id)
            .ok()
            .flatten();
        if lww_peer_loses(peer_updated_at, local_updated) {
            return;
        }
    }
    let row = s3_sessions::S3SessionRow {
        session_id: session_id.clone(),
        access_key_id: json_string(v, "access_key_id"),
        region: json_string(v, "region"),
        endpoint: json_string(v, "endpoint"),
        path_style: v
            .get("path_style")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
        default_bucket: json_string(v, "default_bucket"),
        default_prefix: json_string(v, "default_prefix"),
        trusted_cert_pem: v
            .get("trusted_cert_pem")
            .and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        insecure_skip_verify: v
            .get("insecure_skip_verify")
            .and_then(|x| x.as_bool())
            .unwrap_or(false),
    };
    let result = if mode.is_sync() {
        // Stored stamp falls back to `now_ms` (fresh apply); the
        // LWW gate above used 0 so an unstamped peer cannot win.
        let peer_updated_at = json_i64_opt(v, "updated_at_ms").unwrap_or(now_ms);
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

fn apply_sftp_bookmarks(
    conn: &impl crate::db::DbAccess,
    json: &str,
    mode: ApplyMode,
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
    // Local snapshot for the sync LWW gate. Bookmarks carry no
    // `updated_at`, so `created_at` is the LWW timestamp — a peer's
    // stale live row must not revive a freshly-tombstoned local
    // bookmark, and a stale peer tombstone must not delete a newer
    // local row. The DAO's `apply_tombstone` enforces the second
    // half; the first is the `peer_ts <= local` skip below.
    let local_created_at: HashMap<String, i64> = if mode.is_sync() {
        match sftp_bookmarks::list_all_with_tombstones(conn) {
            Ok(rows) => rows
                .into_iter()
                .map(|(r, _)| (r.id.clone(), r.created_at_ms))
                .collect(),
            Err(e) => {
                outcome
                    .errors
                    .push(format!("sftp_bookmarks local snapshot: {e}"));
                return;
            }
        }
    } else {
        HashMap::new()
    };
    for v in arr {
        apply_one_sftp_bookmark(
            conn,
            &v,
            mode,
            &live_sessions,
            &local_created_at,
            now_ms,
            outcome,
        );
    }
}

/// Apply a single `sftp_bookmarks` row — id / session_id guards,
/// tombstone replay, absent-parent warning, sync LWW gate on
/// `created_at`, then upsert.
fn apply_one_sftp_bookmark(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    live_sessions: &HashSet<String>,
    local_created_at: &HashMap<String, i64>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    let session_id = json_string(v, "session_id");
    if id.is_empty() || session_id.is_empty() {
        return;
    }
    if is_tombstone(v) {
        // Archive imports never carry tombstones; drop silently. A
        // bookmark deletion on a peer routes through the DAO's
        // LWW-gated tombstone so it can't resurrect.
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            match sftp_bookmarks::apply_tombstone(conn, &id, deleted_at_ms) {
                Ok(_) => outcome.sftp_bookmarks_applied += 1,
                Err(e) => outcome
                    .errors
                    .push(format!("sftp_bookmark {id} tombstone: {e}")),
            }
        }
        return;
    }
    if !live_sessions.contains(&session_id) {
        outcome.warnings.push(format!(
            "sftp_bookmark {id}: parent session {session_id} absent"
        ));
        return;
    }
    let created_at_ms = parse_iso8601_or_now(
        v.get("created_at").and_then(|x| x.as_str()).unwrap_or(""),
        now_ms,
    );
    // A peer's stale live row must not revive a freshly-tombstoned
    // local bookmark (the tombstone's `deleted_at` is recorded as a
    // later `created_at` would have to beat).
    if mode.is_sync() && lww_peer_loses(created_at_ms, local_created_at.get(&id).copied()) {
        return;
    }
    let row = sftp_bookmarks::SftpBookmarkRow {
        id: id.clone(),
        session_id,
        remote_path: json_string(v, "remote_path"),
        label: json_string(v, "label"),
        created_at_ms,
    };
    match sftp_bookmarks::upsert(conn, &row) {
        Ok(_) => outcome.sftp_bookmarks_applied += 1,
        Err(e) => outcome
            .errors
            .push(format!("sftp_bookmark {id} upsert: {e}")),
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
        apply_one_port_forward_rule(
            conn,
            &v,
            mode,
            &live_sessions,
            &local_updated_at,
            now_ms,
            outcome,
        );
    }
}

/// Apply a single `port_forward_rules` row — id / session_id guards,
/// tombstone replay, absent-parent warning, sync LWW gate on
/// `updated_at`, then stamped upsert.
fn apply_one_port_forward_rule(
    conn: &impl crate::db::DbAccess,
    v: &Value,
    mode: ApplyMode,
    live_sessions: &HashSet<String>,
    local_updated_at: &HashMap<String, i64>,
    now_ms: i64,
    outcome: &mut ApplyOutcome,
) {
    let id = json_string(v, "id");
    let session_id = json_string(v, "session_id");
    if id.is_empty() || session_id.is_empty() {
        return;
    }
    if is_tombstone(v) {
        if mode.is_sync() {
            let deleted_at_ms = json_i64_opt(v, "deleted_at_ms").unwrap_or(0);
            record_pf_result(
                port_forwards::apply_tombstone(conn, &id, deleted_at_ms),
                &id,
                "tombstone",
                outcome,
            );
        }
        return;
    }
    if !live_sessions.contains(&session_id) {
        outcome.warnings.push(format!(
            "port_forward_rule {id}: parent session {session_id} absent"
        ));
        return;
    }
    let peer_updated_at = if mode.is_sync() {
        json_i64_opt(v, "updated_at_ms").unwrap_or(0)
    } else {
        now_ms
    };
    if mode.is_sync() && lww_peer_loses(peer_updated_at, local_updated_at.get(&id).copied()) {
        return;
    }
    let row = port_forwards::PortForwardRuleRow {
        id: id.clone(),
        session_id,
        kind: json_string(v, "kind"),
        bind_host: json_string(v, "bind_host"),
        bind_port: json_i64(v, "bind_port"),
        remote_host: json_string(v, "remote_host"),
        remote_port: json_i64(v, "remote_port"),
        description: json_string(v, "description"),
        enabled: v.get("enabled").and_then(|x| x.as_bool()).unwrap_or(true),
        sort_order: json_i64(v, "sort_order"),
        created_at_ms: json_i64(v, "created_at_ms"),
        updated_at_ms: peer_updated_at,
    };
    let result = if mode.is_sync() {
        port_forwards::upsert_with_stamp(conn, &row, peer_updated_at)
    } else {
        port_forwards::upsert(conn, &row)
    };
    record_pf_result(result, &id, "upsert", outcome);
}

/// Fold a port-forward DAO result into the outcome: bump the applied
/// counter on success, push a `{op}`-labelled error otherwise. Shared
/// by the tombstone and upsert paths.
fn record_pf_result<T>(result: Result<T, Error>, id: &str, op: &str, outcome: &mut ApplyOutcome) {
    match result {
        Ok(_) => outcome.port_forward_rules_applied += 1,
        Err(e) => outcome
            .errors
            .push(format!("port_forward_rule {id} {op}: {e}")),
    }
}

/// Mirror the SHA-256-of-normalised-PEM fingerprint the
/// `ssh_keys::list_metadata` path computes — keep both sides
/// of the dedup compare reading the same hash. Empty input →
/// empty fingerprint so missing-public-key rows do not
/// false-match the dedup set.
/// Outcome of a recordings extraction. Mirrors the per-kind
/// `applied` counters on [`ApplyResult`] without sneaking onto
/// that struct — recordings land on the filesystem, not the DB,
/// and a downstream consumer that cares only about the DB delta
/// should not have to look at this field.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RecordingApplyOutcome {
    /// Number of `.cast` files written under
    /// `<recordings_root>/imported/<session_id>/`.
    pub written: u32,
    /// Number of files skipped because the destination already
    /// existed — re-importing the same archive a second time
    /// does not overwrite a recording the user may have already
    /// edited locally.
    pub skipped: u32,
    /// Number of `.cast` files the post-extract sweep promoted
    /// to `.lfsr` under the receiver's active DB key (T1 / T2
    /// tier). `0` on the plaintext tier.
    pub promoted_to_lfsr: u32,
}

/// Extract every `recordings/<session_id>/<file_name>` entry the
/// archive carried into
/// `<recordings_root>/imported/<session_id>/<file_name>`. Existing
/// destination files are skipped (the import is idempotent on
/// re-run + does not stomp a recording the user may have edited
/// locally). Each write goes through `<dest>.tmp.<rand>` + atomic
/// rename so a crashed extract leaves either the old file or the
/// new one — never a torn write.
///
/// When `db_key` is `Some(...)`, the imported subtree is then
/// run through
/// [`crate::recorder::migrate::convert_all_cast_to_lfsr`] so the
/// receiver's recordings live under the same tier discipline as
/// the rest of the local tree. On plaintext tier (`db_key =
/// None`) the recordings stay as `.cast` and the receiver can
/// promote them later by enabling the master password.
pub fn apply_recordings_to_filesystem(
    pending: &PendingImport,
    recordings_root: &std::path::Path,
    db_key: Option<&[u8; 32]>,
) -> Result<RecordingApplyOutcome, Error> {
    if pending.recordings.is_empty() {
        return Ok(RecordingApplyOutcome::default());
    }
    let imported_root = recordings_root.join("imported");
    let mut outcome = RecordingApplyOutcome::default();
    for rec in &pending.recordings {
        if !is_safe_segment(&rec.session_id) || !is_safe_segment(&rec.file_name) {
            crate::app_log_warn!(
                "ArchiveImport",
                "skip recording with unsafe path: session={} file={}",
                rec.session_id,
                rec.file_name
            );
            continue;
        }
        let session_dir = imported_root.join(&rec.session_id);
        std::fs::create_dir_all(&session_dir).map_err(|e| {
            Error::Archive(format!("recordings mkdir {}: {e}", session_dir.display()))
        })?;
        let dest = session_dir.join(&rec.file_name);
        if dest.exists() {
            outcome.skipped = outcome.skipped.saturating_add(1);
            continue;
        }
        let tmp = atomic_tmp_path(&dest);
        std::fs::write(&tmp, &rec.bytes)
            .map_err(|e| Error::Archive(format!("recordings tmp write {}: {e}", tmp.display())))?;
        if let Err(msg) = crate::path::harden_file_perms(&tmp) {
            crate::app_log_warn!(
                "ArchiveImport",
                "recordings tmp harden {}: {msg}",
                tmp.display()
            );
        }
        std::fs::rename(&tmp, &dest).map_err(|e| {
            let _ = std::fs::remove_file(&tmp);
            Error::Archive(format!("recordings rename {}: {e}", dest.display()))
        })?;
        outcome.written = outcome.written.saturating_add(1);
    }
    // T1 / T2 receiver: promote the just-extracted `.cast` files
    // to `.lfsr` under the active DB key so they match the rest
    // of the recordings tree's tier discipline. Plaintext tier
    // skips this step — recordings stay as `.cast`.
    if let Some(key) = db_key {
        if imported_root.is_dir() {
            let migrate_outcome =
                crate::recorder::migrate::convert_all_cast_to_lfsr(&imported_root, key)?;
            outcome.promoted_to_lfsr = migrate_outcome.cast_to_lfsr;
        }
    }
    Ok(outcome)
}

/// `<dest>.tmp.<pid>.<nanos>` scratch path. Matches the discipline
/// the recordings migration helper uses for its own atomic writes.
fn atomic_tmp_path(dest: &std::path::Path) -> std::path::PathBuf {
    let pid = std::process::id();
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let parent = dest.parent().unwrap_or_else(|| std::path::Path::new("."));
    let name = dest
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("recording");
    parent.join(format!("{name}.tmp.{pid}.{nanos:x}"))
}

/// Reject path segments that could escape the `imported/` root
/// (`.` / `..` / embedded separators). The archive parser already
/// runs the same check in [`super::parse_recording_entry_path`];
/// the duplication here defends against a hand-crafted
/// `PendingImport` reaching `apply_recordings_to_filesystem`
/// directly (today only the parse path produces one, but the
/// public API does not gate on that).
fn is_safe_segment(s: &str) -> bool {
    !s.is_empty()
        && s != "."
        && s != ".."
        && !s.contains('/')
        && !s.contains('\\')
        && !s.contains('\0')
}

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
mod tests;
