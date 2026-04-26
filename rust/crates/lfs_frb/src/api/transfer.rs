//! FRB adapter for `lfs_core::transfer`. Surfaces the worker
//! pool driver so Dart can dispatch enqueued tasks to the
//! Rust-driven execution path. Per-task progress + state
//! events still arrive through the existing bus subscription
//! (`PortForwardStatus`, `TransferTaskState`,
//! `TransferTaskProgress`, `TransferTaskError`); this surface
//! is the dispatch / cancel control plane only.

use std::sync::Arc;

use lfs_core::transfer::driver::{SftpTaskExecutor, WorkerPool};

/// Default worker count. Matches the `Tokio worker pool with
/// bounded concurrency, default = host-platform-aware`
/// guidance in the migration plan — four parallel SFTP
/// streams cover the typical user-facing batch without
/// saturating the SSH session's channel slots.
const DEFAULT_WORKER_COUNT: usize = 4;

fn pool_arc() -> Arc<WorkerPool> {
    let app = lfs_core::app::instance();
    let mut slot = app
        .transfer_pool
        .lock()
        .expect("transfer pool slot poisoned");
    if slot.is_none() {
        let executor = Arc::new(SftpTaskExecutor);
        *slot = Some(Arc::new(WorkerPool::spawn(executor, DEFAULT_WORKER_COUNT)));
    }
    slot.as_ref().unwrap().clone()
}

/// Dispatch a previously-enqueued task into the worker pool.
/// Caller must have already inserted the row through the
/// existing DAO surface (currently exposed by the export /
/// import driver path Dart-side); the pool needs the row to
/// resolve session id + paths via [`TransferQueue::snapshot`].
///
/// Lazy-initialises the worker pool on the first call so the
/// tokio runtime is guaranteed to be alive (the FRB worker
/// hosts a tokio runtime by construction).
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
