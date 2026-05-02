//! FRB adapter for `lfs_core::transfer`. Surfaces the worker
//! pool driver so Dart can enqueue + dispatch tasks against the
//! Rust execution path. Per-task progress + state events arrive
//! through the existing bus subscription (`TransferTaskAdded`,
//! `TransferTaskState`, `TransferTaskProgress`,
//! `TransferTaskError`).

use std::sync::Arc;

use lfs_core::transfer::driver::{SftpTaskExecutor, WorkerPool};
use lfs_core::transfer::{TaskKind, TaskSnapshot, TaskState};

/// Default worker count. Matches the `Tokio worker pool with
/// bounded concurrency, default = host-platform-aware`
/// guidance — four parallel SFTP streams cover the typical
/// user-facing batch without saturating the SSH session's
/// channel slots.
const DEFAULT_WORKER_COUNT: usize = 4;

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
        *slot = Some(Arc::new(WorkerPool::spawn(executor, DEFAULT_WORKER_COUNT)));
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
        id.clone(),
        kind.into(),
        session_id,
        remote_path,
        local_path,
        bytes_total,
        &app.bus,
    );
    let pool = pool_arc();
    pool.dispatch(id).await.map_err(|e| e.to_string())?;
    Ok(snap.into())
}

/// Dispatch a previously-enqueued task into the worker pool.
/// Used by paths that build the row out-of-band (not through
/// [`transfer_enqueue`]) — kept around for symmetry with the
/// older single-step shape.
pub async fn transfer_dispatch(task_id: String) -> Result<(), String> {
    let pool = pool_arc();
    pool.dispatch(task_id).await.map_err(|e| e.to_string())
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
