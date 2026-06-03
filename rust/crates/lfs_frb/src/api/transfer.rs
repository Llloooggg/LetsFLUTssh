//! FRB adapter for `lfs_core::transfer`. Surfaces the worker
//! pool driver so Dart can enqueue + dispatch tasks against the
//! Rust execution path. Per-task progress + state events arrive
//! through the existing bus subscription (`TransferTaskAdded`,
//! `TransferTaskState`, `TransferTaskProgress`,
//! `TransferTaskError`).

use std::sync::Arc;

use lfs_core::transfer::driver::{SftpTaskExecutor, WorkerPool};
use lfs_core::transfer::{EnqueueRequest, TaskKind, TaskSnapshot, TaskState};

fn pool_arc() -> Arc<WorkerPool> {
    let app = lfs_core::app::instance();
    // `unwrap_or_else(into_inner)` recovers from a poisoned lock by
    // taking the inner value back. A poison only happens if a prior
    // holder panicked while mutating; the slot is `Option<Arc<...>>`
    // — even a panic mid-`spawn` leaves it observable (None or a
    // valid Arc), so reusing the inner value is sound. The
    // alternative `.expect(...)` would propagate a panic across the
    // FRB worker thread, corrupting Dart-side Futures.
    let mut slot = app.transfer_pool.lock().unwrap_or_else(|p| p.into_inner());
    if slot.is_none() {
        let executor = Arc::new(SftpTaskExecutor);
        // Size the pool from the user's "Parallel workers" setting
        // (clamped + defaulted in lfs_core). Read once at first spawn
        // — the pool is never resized, so a changed setting applies
        // on the next launch.
        let workers = lfs_core::transfer::worker_count_from_config_store();
        *slot = Some(Arc::new(WorkerPool::spawn(executor, workers)));
    }
    slot.as_ref().unwrap().clone()
}

/// FRB mirror of `lfs_core::transfer::TaskKind`.
#[derive(Debug, Clone, Copy)]
pub enum DbTransferKind {
    Download,
    Upload,
}

impl From<DbTransferKind> for TaskKind {
    fn from(k: DbTransferKind) -> Self {
        match k {
            DbTransferKind::Download => TaskKind::Download,
            DbTransferKind::Upload => TaskKind::Upload,
        }
    }
}

impl From<TaskKind> for DbTransferKind {
    fn from(k: TaskKind) -> Self {
        match k {
            TaskKind::Download => DbTransferKind::Download,
            TaskKind::Upload => DbTransferKind::Upload,
        }
    }
}

/// FRB mirror of `lfs_core::transfer::TaskState`.
#[derive(Debug, Clone, Copy)]
pub enum DbTransferState {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl From<TaskState> for DbTransferState {
    fn from(s: TaskState) -> Self {
        match s {
            TaskState::Queued => DbTransferState::Queued,
            TaskState::Running => DbTransferState::Running,
            TaskState::Completed => DbTransferState::Completed,
            TaskState::Failed => DbTransferState::Failed,
            TaskState::Cancelled => DbTransferState::Cancelled,
        }
    }
}

/// FRB mirror of `lfs_core::transfer::TaskSnapshot`.
#[derive(Debug, Clone)]
pub struct DbTransferSnapshot {
    pub id: String,
    pub kind: DbTransferKind,
    pub session_id: String,
    pub remote_path: String,
    pub local_path: String,
    pub state: DbTransferState,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub error: Option<String>,
}

impl From<TaskSnapshot> for DbTransferSnapshot {
    fn from(s: TaskSnapshot) -> Self {
        Self {
            id: s.id,
            kind: s.kind.into(),
            session_id: s.session_id,
            remote_path: s.remote_path,
            local_path: s.local_path,
            state: s.state.into(),
            bytes_done: s.bytes_done,
            bytes_total: s.bytes_total,
            error: s.error,
        }
    }
}

/// Enqueue a fresh transfer task and immediately dispatch it
/// into the worker pool. Returns the registered task id (used
/// later for cancel + history-drop). Lazy-inits the worker pool
/// on the first enqueue.
///
/// `bytes_total` is informational — the executor reports
/// real-time `bytes_done` via `TransferTaskProgress` events.
/// Pass `0` when the size is unknown (e.g. a remote read whose
/// size we haven't stat'd yet).
pub async fn transfer_enqueue(
    id: String,
    kind: DbTransferKind,
    session_id: String,
    remote_path: String,
    local_path: String,
    bytes_total: u64,
) -> Result<DbTransferSnapshot, String> {
    let app = lfs_core::app::instance();
    let snap = app.transfers.enqueue(
        EnqueueRequest {
            id: id.clone(),
            kind: kind.into(),
            session_id,
            remote_path,
            local_path,
            bytes_total,
        },
        &app.bus,
    );
    let pool = pool_arc();
    pool.dispatch(id)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))?;
    Ok(snap.into())
}

/// Dispatch an already-enqueued task into the worker pool. Used by
/// paths that build the row out-of-band (not through
/// [`transfer_enqueue`]).
pub async fn transfer_dispatch(task_id: String) -> Result<(), String> {
    let pool = pool_arc();
    pool.dispatch(task_id)
        .await
        .map_err(|e| crate::api::frb_err::from_core(&e))
}

/// Flip the cancel flag for a running task. Idempotent on a
/// missing id (task already finished or never dispatched).
/// Returns `true` when a token was actually flipped.
pub async fn transfer_cancel(task_id: String) -> Result<bool, String> {
    let pool = pool_arc();
    Ok(pool.cancel(&task_id).await)
}

/// Snapshot every task in the registry — queued / running /
/// completed / failed / cancelled. Insertion order preserved
/// so the UI renders the same row sequence the user enqueued.
pub async fn transfer_snapshot_all() -> Vec<DbTransferSnapshot> {
    let app = lfs_core::app::instance();
    app.transfers
        .snapshot_all()
        .into_iter()
        .map(DbTransferSnapshot::from)
        .collect()
}

/// Drop a terminal task (Completed / Failed / Cancelled) from
/// the registry. No-op for missing or non-terminal ids — the
/// UI's "clear history" button calls this per row.
pub async fn transfer_drop_terminal(task_id: String) -> bool {
    let app = lfs_core::app::instance();
    app.transfers.drop_terminal(&task_id)
}

/// Bulk drop every terminal task. Mirrors the existing Dart
/// `TransferManager.clearHistory`. Returns the count of dropped
/// tasks.
pub async fn transfer_clear_history() -> u32 {
    let app = lfs_core::app::instance();
    let snapshots = app.transfers.snapshot_all();
    let mut dropped: u32 = 0;
    for s in snapshots {
        if matches!(
            s.state,
            TaskState::Completed | TaskState::Failed | TaskState::Cancelled
        ) && app.transfers.drop_terminal(&s.id)
        {
            dropped += 1;
        }
    }
    dropped
}

#[cfg(test)]
mod tests {
    use super::*;

    // The enqueue / dispatch / cancel / snapshot endpoints route
    // through `lfs_core::app::instance()` + the worker pool and need
    // the FRB worker bootstrap; covered by the Dart
    // `transfer_manager_test.dart` integration suite. The standalone
    // tests below pin the FRB↔core variant mapping that crosses the
    // boundary on every snapshot.

    #[test]
    fn db_transfer_kind_round_trips_through_core() {
        for db in [DbTransferKind::Download, DbTransferKind::Upload] {
            let core: TaskKind = db.into();
            let back: DbTransferKind = core.into();
            assert!(
                matches!(
                    (db, back),
                    (DbTransferKind::Download, DbTransferKind::Download)
                        | (DbTransferKind::Upload, DbTransferKind::Upload)
                ),
                "kind round-trip must be lossless"
            );
        }
    }

    #[test]
    fn db_transfer_state_maps_each_variant_distinctly() {
        // Pin the variant→variant mapping so a future refactor that
        // collapses two states (e.g. Failed → Cancelled) breaks
        // loudly here, not silently in the UI.
        for (core, expected_label) in [
            (TaskState::Queued, "queued"),
            (TaskState::Running, "running"),
            (TaskState::Completed, "completed"),
            (TaskState::Failed, "failed"),
            (TaskState::Cancelled, "cancelled"),
        ] {
            let db: DbTransferState = core.into();
            let label = match db {
                DbTransferState::Queued => "queued",
                DbTransferState::Running => "running",
                DbTransferState::Completed => "completed",
                DbTransferState::Failed => "failed",
                DbTransferState::Cancelled => "cancelled",
            };
            assert_eq!(label, expected_label);
        }
    }

    #[test]
    fn db_transfer_snapshot_carries_every_field_through() {
        let core = TaskSnapshot {
            id: "task-1".into(),
            kind: TaskKind::Download,
            session_id: "sess-a".into(),
            remote_path: "/var/log/app.log".into(),
            local_path: "/tmp/app.log".into(),
            state: TaskState::Running,
            bytes_done: 512,
            bytes_total: 4096,
            error: None,
        };
        let db: DbTransferSnapshot = core.into();
        assert_eq!(db.id, "task-1");
        assert!(matches!(db.kind, DbTransferKind::Download));
        assert!(matches!(db.state, DbTransferState::Running));
        assert_eq!(db.bytes_done, 512);
        assert_eq!(db.bytes_total, 4096);
        assert_eq!(db.session_id, "sess-a");
        assert!(db.error.is_none());
    }
}
