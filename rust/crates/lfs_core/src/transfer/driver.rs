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

use async_channel::{Receiver, Sender};
use tokio::sync::Mutex;
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
///
/// Backed by `async-channel` so every worker pulls directly off
/// the same multi-consumer receiver — no `Arc<Mutex<Receiver>>`
/// gate that would serialise workers across `recv().await`.
/// `tokio::sync::mpsc` is single-consumer by design; cloning the
/// receiver is what the prior shape attempted, holding the lock
/// across the await collapsed `worker_count > 1` to effective
/// `1` because every worker except the lock-holder was blocked
/// outside the critical section.
pub struct WorkerPool {
    sender: Sender<String>,
    cancel_tokens: Arc<Mutex<HashMap<String, CancellationToken>>>,
    workers: Vec<JoinHandle<()>>,
}

impl WorkerPool {
    /// Spin up `worker_count` tokio workers backed by `executor`.
    /// Channel capacity defaults to `2 * worker_count` (lower
    /// bound 8) — keeps dispatch non-blocking under steady-state
    /// load while flat-lining at a bounded queue depth so a
    /// runaway UI can't OOM the pool.
    pub fn spawn<E: TaskExecutor>(executor: Arc<E>, worker_count: usize) -> Self {
        let cap = (worker_count * 2).max(8);
        let (tx, rx) = async_channel::bounded::<String>(cap);
        let cancel_tokens: Arc<Mutex<HashMap<String, CancellationToken>>> =
            Arc::new(Mutex::new(HashMap::new()));

        let mut workers = Vec::with_capacity(worker_count);
        for _ in 0..worker_count {
            let rx: Receiver<String> = rx.clone();
            let cancel_tokens = cancel_tokens.clone();
            let executor = executor.clone();
            let worker = tokio::spawn(async move {
                loop {
                    let task_id = match rx.recv().await {
                        Ok(id) => id,
                        Err(_) => return, // channel closed → pool shutdown
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
            .map_err(|e| Error::Transport(format!("transfer dispatch: {e}")))
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
                .ok_or_else(|| Error::SessionUnavailable(format!("session {} not registered", task.session_id)))?;
            let session = {
                let guard = actor
                    .lock()
                    .map_err(|_| Error::Io("actor mutex poisoned".to_string()))?;
                guard.clone_session().ok_or_else(|| {
                    Error::Transport(format!("session {} has no live handle", task.session_id))
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

/// Chunk size for streaming SFTP transfers. 256 KiB keeps the SSH
/// channel window fed without flooding it: russh's default channel
/// window is 2 MiB, so eight in-flight chunks saturate it without
/// triggering a back-pressure stall. The previous 64 KiB cap left a
/// single-stream transfer running at maybe a quarter of the pipe
/// limit on 100+ Mbps links because each read awaited a full
/// round-trip before the next packet went out. Larger sizes (1 MiB+)
/// risk fragmentation against smaller server-side window settings;
/// 256 KiB is the conservative mid-point.
const TRANSFER_CHUNK_SIZE: usize = 256 * 1024;

async fn download(
    sftp: &crate::sftp::Sftp,
    task: &TaskSnapshot,
    cancel: &CancellationToken,
) -> Result<(), Error> {
    use tokio::io::AsyncWriteExt;
    let app = crate::app::instance();
    let remote = sftp.open(&task.remote_path).await?;
    let local_path = std::path::Path::new(&task.local_path);
    if let Some(parent) = local_path.parent() {
        if !parent.as_os_str().is_empty() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Transport(format!("mkdir {}: {e}", parent.display())))?;
        }
    }
    // tokio::fs::File so the local I/O runs on the blocking pool —
    // the SFTP read at the top of the loop is async and does not
    // block its worker thread, but a slow disk on the write side
    // would otherwise pin the same worker and stall every other
    // task scheduled on it.
    let mut local = tokio::fs::File::create(&task.local_path)
        .await
        .map_err(|e| Error::Transport(format!("create {}: {e}", task.local_path)))?;
    // Single scratch buffer reused across every chunk read — the
    // pre-fix `read_chunk(TRANSFER_CHUNK_SIZE)` allocated a fresh
    // `vec![0; 256 KiB]` per iteration. On a 100 MB/s pipe that's
    // ~400 mallocs/s; the buffer reuse keeps the heap pressure
    // off the tokio worker.
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    let mut written: u64 = 0;
    loop {
        if cancel.is_cancelled() {
            return Err(Error::Io("download cancelled".to_string()));
        }
        let n = remote.read_into(&mut buf).await?;
        if n == 0 {
            break;
        }
        local
            .write_all(&buf[..n])
            .await
            .map_err(|e| Error::Transport(format!("write {}: {e}", task.local_path)))?;
        written = written.saturating_add(n as u64);
        app.transfers.set_progress(&task.id, written, &app.bus);
    }
    local
        .sync_all()
        .await
        .map_err(|e| Error::Transport(format!("fsync {}: {e}", task.local_path)))?;
    Ok(())
}

async fn upload(
    sftp: &crate::sftp::Sftp,
    task: &TaskSnapshot,
    cancel: &CancellationToken,
) -> Result<(), Error> {
    use tokio::io::AsyncReadExt;
    let app = crate::app::instance();
    let mut local = tokio::fs::File::open(&task.local_path)
        .await
        .map_err(|e| Error::Transport(format!("read {}: {e}", task.local_path)))?;
    let remote = sftp.create(&task.remote_path).await?;
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    let mut written: u64 = 0;
    loop {
        if cancel.is_cancelled() {
            return Err(Error::Io("upload cancelled".to_string()));
        }
        let n = local
            .read(&mut buf)
            .await
            .map_err(|e| Error::Transport(format!("read {}: {e}", task.local_path)))?;
        if n == 0 {
            break;
        }
        remote.write_all(&buf[..n]).await?;
        written = written.saturating_add(n as u64);
        app.transfers.set_progress(&task.id, written, &app.bus);
    }
    remote.sync_all().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::transfer::{EnqueueRequest, TaskKind, TransferQueue};
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
            EnqueueRequest {
                id: "t-pool-1".into(),
                kind: TaskKind::Download,
                session_id: "sess-pool".into(),
                remote_path: "/r".into(),
                local_path: "/l".into(),
                bytes_total: 0,
            },
            &bus,
        );
        // Move the row into the singleton's registry so the
        // worker can find it.
        crate::app::instance().transfers.enqueue(
            EnqueueRequest {
                id: "t-pool-1".into(),
                kind: TaskKind::Download,
                session_id: "sess-pool".into(),
                remote_path: "/r".into(),
                local_path: "/l".into(),
                bytes_total: 0,
            },
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
