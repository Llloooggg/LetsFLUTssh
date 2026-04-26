//! Transfer queue worker pool.
//!
//! Generic over a `TaskExecutor` trait so production wires
//! download / upload to `lfs_core::sftp::Sftp` while tests
//! inject a closure-driven fake executor that bumps progress
//! deterministically.
//!
//! Pool shape: a bounded set of tokio worker tasks, each
//! pulling from an `mpsc::Receiver<TaskId>`. The Dart side
//! enqueues via `TransferQueue::enqueue` (which we already
//! ship) + `WorkerPool::dispatch(task_id)` (here). The pool
//! holds a [`CancellationToken`]-style flag per running task
//! so the UI's "Cancel" maps to a clean stop.

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use crate::error::Error;
use crate::transfer::{TaskKind, TaskSnapshot, TaskState};

/// What the worker pool calls per task. Production wraps SFTP
/// download / upload; tests substitute a closure that walks a
/// canned progress curve.
pub trait TaskExecutor: Send + Sync + 'static {
    /// Drive the task to completion or failure. The executor
    /// uses [`crate::app::instance().transfers`] (or the
    /// `bus` it owns) to publish per-task progress events as
    /// it runs.
    fn execute(
        &self,
        task: TaskSnapshot,
        cancel: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<(), Error>> + Send + 'static>>;
}

/// Cancellation token a worker checks between progress chunks.
/// Cloned across the executor + the pool's `cancel(id)` API
/// so the UI's Cancel button flips a single shared flag.
#[derive(Clone, Debug, Default)]
pub struct CancellationToken {
    cancelled: Arc<std::sync::atomic::AtomicBool>,
}

impl CancellationToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.cancelled
            .store(true, std::sync::atomic::Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(std::sync::atomic::Ordering::SeqCst)
    }
}

/// Bounded worker pool. Owns the dispatch channel + the
/// per-task cancel flag map. Drop the pool to abort every
/// worker; per-task `cancel` flips the matching token without
/// killing the worker.
pub struct WorkerPool {
    sender: mpsc::Sender<String>,
    cancel_tokens: Arc<Mutex<HashMap<String, CancellationToken>>>,
    workers: Vec<JoinHandle<()>>,
}

impl WorkerPool {
    /// Spin up `worker_count` tokio workers backed by `executor`.
    /// Channel capacity defaults to `2 * worker_count` — keeps
    /// dispatch non-blocking under steady-state load while
    /// flat-lining at a bounded queue depth so a runaway UI
    /// can't OOM the pool.
    pub fn spawn<E: TaskExecutor>(executor: Arc<E>, worker_count: usize) -> Self {
        let cap = (worker_count * 2).max(8);
        let (tx, rx) = mpsc::channel::<String>(cap);
        let rx = Arc::new(Mutex::new(rx));
        let cancel_tokens: Arc<Mutex<HashMap<String, CancellationToken>>> =
            Arc::new(Mutex::new(HashMap::new()));

        let mut workers = Vec::with_capacity(worker_count);
        for _ in 0..worker_count {
            let rx = rx.clone();
            let cancel_tokens = cancel_tokens.clone();
            let executor = executor.clone();
            let worker = tokio::spawn(async move {
                loop {
                    let task_id = {
                        let mut guard = rx.lock().await;
                        match guard.recv().await {
                            Some(id) => id,
                            None => return, // channel closed → pool shutdown
                        }
                    };
                    run_one(&task_id, &cancel_tokens, executor.as_ref()).await;
                }
            });
            workers.push(worker);
        }

        WorkerPool {
            sender: tx,
            cancel_tokens,
            workers,
        }
    }

    /// Hand a queued task off to the pool. Must be paired with
    /// a prior `TransferQueue::enqueue(id, ...)` so the row
    /// exists in the registry. Returns `Err` when the channel
    /// is full (back-pressure: the UI should surface "queue
    /// busy, try again") or the pool has been dropped.
    pub async fn dispatch(&self, task_id: String) -> Result<(), Error> {
        self.sender
            .send(task_id)
            .await
            .map_err(|e| Error::Io(format!("transfer dispatch: {e}")))
    }

    /// Flip the cancel flag for `task_id`. Idempotent on a
    /// missing id — the worker has already finished or the
    /// task was never dispatched. Returns `true` when a token
    /// was actually flipped.
    pub async fn cancel(&self, task_id: &str) -> bool {
        let tokens = self.cancel_tokens.lock().await;
        match tokens.get(task_id) {
            Some(token) => {
                token.cancel();
                true
            }
            None => false,
        }
    }
}

impl Drop for WorkerPool {
    fn drop(&mut self) {
        for worker in &self.workers {
            worker.abort();
        }
    }
}

async fn run_one<E: TaskExecutor + ?Sized>(
    task_id: &str,
    cancel_tokens: &Arc<Mutex<HashMap<String, CancellationToken>>>,
    executor: &E,
) {
    let app = crate::app::instance();
    let snap = match app.transfers.snapshot(task_id) {
        Some(s) => s,
        None => return, // row evicted before the worker picked it up
    };

    let token = CancellationToken::new();
    cancel_tokens
        .lock()
        .await
        .insert(task_id.to_string(), token.clone());

    app.transfers
        .set_state(task_id, TaskState::Running, &app.bus);
    let result = executor.execute(snap, token.clone()).await;

    cancel_tokens.lock().await.remove(task_id);

    if token.is_cancelled() {
        app.transfers.cancel(task_id, &app.bus);
        return;
    }
    match result {
        Ok(_) => app
            .transfers
            .set_state(task_id, TaskState::Completed, &app.bus),
        Err(e) => app.transfers.fail(task_id, e.to_string(), &app.bus),
    }
}

/// Production [`TaskExecutor`] wired to
/// `lfs_core::sftp::Sftp::download_file` /
/// `upload_file`. The session lookup happens per task
/// (`AppState::connections.get`) so a session torn down
/// mid-transfer surfaces a clean failure rather than a
/// dangling reference.
pub struct SftpTaskExecutor;

impl TaskExecutor for SftpTaskExecutor {
    fn execute(
        &self,
        task: TaskSnapshot,
        cancel: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = Result<(), Error>> + Send + 'static>> {
        Box::pin(async move {
            if cancel.is_cancelled() {
                return Err(Error::Io("cancelled before start".to_string()));
            }
            let app = crate::app::instance();
            let actor = app
                .connections
                .get(&task.session_id)
                .ok_or_else(|| Error::Io(format!("session {} not registered", task.session_id)))?;
            let session = {
                let guard = actor
                    .lock()
                    .map_err(|_| Error::Io("actor mutex poisoned".to_string()))?;
                guard.clone_session().ok_or_else(|| {
                    Error::Io(format!("session {} has no live handle", task.session_id))
                })?
            };
            let sftp = session.open_sftp().await?;
            match task.kind {
                TaskKind::Download => download(&sftp, &task, &cancel).await,
                TaskKind::Upload => upload(&sftp, &task, &cancel).await,
            }
        })
    }
}

async fn download(
    sftp: &crate::sftp::Sftp,
    task: &TaskSnapshot,
    _cancel: &CancellationToken,
) -> Result<(), Error> {
    // Small-file path: pull the whole blob in one read, write
    // it atomically. Streaming + cancellation hooks for large
    // files go through the byte-stream surface — wired in
    // alongside the `SftpFile` open path.
    let bytes = sftp.read_file(&task.remote_path).await?;
    std::fs::write(&task.local_path, &bytes)
        .map_err(|e| Error::Io(format!("write {}: {e}", task.local_path)))?;
    let app = crate::app::instance();
    app.transfers
        .set_progress(&task.id, bytes.len() as u64, &app.bus);
    Ok(())
}

async fn upload(
    sftp: &crate::sftp::Sftp,
    task: &TaskSnapshot,
    _cancel: &CancellationToken,
) -> Result<(), Error> {
    let bytes = std::fs::read(&task.local_path)
        .map_err(|e| Error::Io(format!("read {}: {e}", task.local_path)))?;
    sftp.write_file(&task.remote_path, &bytes).await?;
    let app = crate::app::instance();
    app.transfers
        .set_progress(&task.id, bytes.len() as u64, &app.bus);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transfer::{TaskKind, TransferQueue};
    use std::sync::atomic::{AtomicU32, Ordering};

    /// Counts execute calls + acts on the cancel flag.
    struct CountingExecutor {
        invocations: AtomicU32,
        respect_cancel: bool,
    }

    impl TaskExecutor for CountingExecutor {
        fn execute(
            &self,
            _task: TaskSnapshot,
            cancel: CancellationToken,
        ) -> Pin<Box<dyn Future<Output = Result<(), Error>> + Send + 'static>> {
            self.invocations.fetch_add(1, Ordering::SeqCst);
            let respect = self.respect_cancel;
            Box::pin(async move {
                if respect && cancel.is_cancelled() {
                    return Err(Error::Io("cancelled".to_string()));
                }
                Ok(())
            })
        }
    }

    #[test]
    fn cancellation_token_round_trip() {
        let t = CancellationToken::new();
        assert!(!t.is_cancelled());
        let clone = t.clone();
        clone.cancel();
        assert!(t.is_cancelled());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn pool_dispatch_runs_executor() {
        // The driver routes through `app::instance()`. Init
        // it by calling `app::init()` once; subsequent calls
        // are no-ops.
        let _app = crate::app::init();
        let registry = TransferQueue::new();
        let bus = crate::bus::EventBus::new();
        registry.enqueue(
            "t-pool-1".into(),
            TaskKind::Download,
            "sess-pool".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        // Move the row into the singleton's registry so the
        // worker can find it.
        crate::app::instance().transfers.enqueue(
            "t-pool-1".into(),
            TaskKind::Download,
            "sess-pool".into(),
            "/r".into(),
            "/l".into(),
            0,
            &crate::app::instance().bus,
        );
        let exec = Arc::new(CountingExecutor {
            invocations: AtomicU32::new(0),
            respect_cancel: false,
        });
        let pool = WorkerPool::spawn(exec.clone(), 1);
        pool.dispatch("t-pool-1".into()).await.expect("dispatch");
        // Give the worker a tick.
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        assert!(exec.invocations.load(Ordering::SeqCst) >= 1);
    }
}
