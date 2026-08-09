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

use crate::archive::{apply_pending_to_db, ApplyMode, ApplyOptions, ApplyOutcome, PendingImport};
use crate::db::Connection;
use crate::error::Error;

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

/// Fold `pending` into `conn`'s live tables under LWW. Thin wrapper
/// around [`apply_pending_to_db`] with [`ApplyMode::Sync`]; the
/// unified driver runs the merge inside one transaction and routes
/// every per-kind branch through the same helper set the archive-
/// import path uses (LWW gates inside each helper guard the
/// peer-newer-wins contract).
///
/// Per-row parse failures land in [`MergeOutcome::errors`]; the
/// transaction still commits so a single corrupt entry in a 500-row
/// pull does not abort the whole merge. Catastrophic DB errors
/// (transaction begin/commit failure, schema mismatch) bubble up as
/// `Err`.
pub fn merge_pending_into_local(
    conn: &mut Connection,
    pending: &PendingImport,
) -> Result<MergeOutcome, Error> {
    let mut outcome = ApplyOutcome::default();
    // ApplyOptions is ignored under Sync mode (the orchestrator
    // always applies every entry the peer carried); supply a default
    // for the unified entry's signature.
    let options = ApplyOptions::default();
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    apply_pending_to_db(
        conn,
        pending,
        ApplyMode::Sync,
        &options,
        now_ms,
        &mut outcome,
    )?;
    Ok(MergeOutcome::from_apply_outcome(outcome))
}

impl MergeOutcome {
    /// Project the unified [`ApplyOutcome`] onto the sync-shape
    /// counters Dart's `lfs_frb::api::sync` adapter consumes. Each
    /// per-kind counter maps one-for-one onto the unified outcome;
    /// SFTP-bookmark counts land on [`MergeOutcome::bookmarks_merged`].
    pub fn from_apply_outcome(o: ApplyOutcome) -> Self {
        Self {
            sessions_merged: o.sessions_applied as u32,
            keys_merged: o.keys_applied as u32,
            tags_merged: o.tags_applied as u32,
            snippets_merged: o.snippets_applied as u32,
            bookmarks_merged: o.sftp_bookmarks_applied as u32,
            session_tag_edges_merged: o.session_tags_applied as u32,
            folder_tag_edges_merged: o.folder_tags_applied as u32,
            session_snippet_edges_merged: o.session_snippets_applied as u32,
            errors: o.errors,
        }
    }
}
#[cfg(test)]
#[path = "../../tests/unit/sync_merge.rs"]
mod tests;
