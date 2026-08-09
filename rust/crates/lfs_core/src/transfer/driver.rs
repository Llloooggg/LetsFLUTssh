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
/// the same multi-consumer receiver. **Don't switch to
/// `tokio::sync::mpsc`** — it is single-consumer by design, and
/// the only way to fan out is `Arc<Mutex<Receiver>>` + holding
/// the lock across `recv().await`. Holding a lock across an
/// await collapses `worker_count > 1` to effective `1` because
/// every worker except the lock-holder is blocked outside the
/// critical section.
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

/// Production [`TaskExecutor`] that dispatches by transport kind.
///
/// 1. `app.providers.get(connection_id)` first — populated by the
///    WebDAV / S3 connect helpers, hits the `dyn Provider` path
///    that streams through [`Provider::get_stream`] /
///    [`Provider::put_stream`].
/// 2. Falls back to `app.connections.get(connection_id)` (russh
///    actor) for SSH, then runs the SFTP-native [`download`] /
///    [`upload`] streamers below.
///
/// Keying by **connection id** matches every other registry in
/// `AppState`. A session torn down mid-transfer surfaces a clean
/// failure (`SessionUnavailable`) rather than a dangling
/// reference: the registry slot frees on `Drop` of the FRB-opaque
/// handle, and the lookup returns `None` on the next pickup.
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
            // Non-SSH transport path: the WebDAV / S3 connect
            // helpers registered the live provider in
            // `app.providers` keyed by connection id. If the slot
            // is populated, route through the generic
            // `Provider`-driven streamers — these are kind-agnostic
            // and use the same chunked + cancellable + progress-
            // reporting shape the SFTP path has.
            if let Some(provider) = app.providers.get(&task.session_id) {
                return match task.kind {
                    TaskKind::Download => {
                        download_via_provider(provider.as_ref(), &task, &cancel).await
                    }
                    TaskKind::Upload => {
                        upload_via_provider(provider.as_ref(), &task, &cancel).await
                    }
                };
            }
            // SSH path: the russh actor lookup is the canonical
            // pre-`providers`-registry shape — kept verbatim so
            // SSH transfers see no behaviour change.
            let actor = app.connections.get(&task.session_id).ok_or_else(|| {
                Error::SessionUnavailable(format!("session {} not registered", task.session_id))
            })?;
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

/// Generic download driver for any [`Provider`] backend. Mirrors
/// the SFTP-native [`download`] shape: `.<task-id>.part` staging,
/// progress reporting per chunk, cancellation between chunks,
/// rename on completion, cleanup on failure.
async fn download_via_provider(
    provider: &dyn crate::storage::Provider,
    task: &TaskSnapshot,
    cancel: &CancellationToken,
) -> Result<(), Error> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;
    let app = crate::app::instance();
    let local_path = std::path::Path::new(&task.local_path);
    if let Some(parent) = local_path.parent() {
        if !parent.as_os_str().is_empty() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| Error::Transport(format!("mkdir {}: {e}", parent.display())))?;
        }
    }
    let part_path = format!("{}.{}.part", task.local_path, task.id);
    let result = async {
        let mut stream = provider.get_stream(&task.remote_path, None).await?;
        let mut local = tokio::fs::File::create(&part_path)
            .await
            .map_err(|e| Error::Transport(format!("create {}: {e}", part_path)))?;
        let mut written: u64 = 0;
        while let Some(chunk) = stream.next().await {
            if cancel.is_cancelled() {
                return Err(Error::Io("download cancelled".to_string()));
            }
            let bytes = chunk?;
            local
                .write_all(&bytes)
                .await
                .map_err(|e| Error::Transport(format!("write {}: {e}", part_path)))?;
            written = written.saturating_add(bytes.len() as u64);
            app.transfers.set_progress(&task.id, written, &app.bus);
        }
        local
            .sync_all()
            .await
            .map_err(|e| Error::Transport(format!("fsync {}: {e}", part_path)))?;
        Ok::<(), Error>(())
    }
    .await;
    if result.is_err() {
        let _ = tokio::fs::remove_file(&part_path).await;
        return result;
    }
    tokio::fs::rename(&part_path, &task.local_path)
        .await
        .map_err(|e| {
            Error::Transport(format!("rename {} → {}: {e}", part_path, task.local_path))
        })?;
    Ok(())
}

/// Generic upload driver for any [`Provider`] backend. Reads the
/// local file in `TRANSFER_CHUNK_SIZE`-byte chunks, wraps the
/// reader as a `ByteStream`, and hands it to
/// [`Provider::put_stream`]. Progress reporting happens off a
/// counting wrapper inside the stream so backends that PUT in a
/// single shot (S3 < 5 MiB) still emit at least one progress event.
async fn upload_via_provider(
    provider: &dyn crate::storage::Provider,
    task: &TaskSnapshot,
    cancel: &CancellationToken,
) -> Result<(), Error> {
    use futures_util::stream;
    let local = tokio::fs::File::open(&task.local_path)
        .await
        .map_err(|e| Error::Transport(format!("read {}: {e}", task.local_path)))?;
    let total = local
        .metadata()
        .await
        .map_err(|e| Error::Transport(format!("stat {}: {e}", task.local_path)))?
        .len();

    // Lazily stream the file from disk one chunk at a time instead of
    // pre-reading the whole thing into a Vec — buffering would hold an
    // entire multi-GB upload in RAM. `unfold` reads the next
    // `TRANSFER_CHUNK_SIZE` block per poll, reports progress, and ends
    // on EOF / cancel / read error (the `done` flag stops a poll after
    // an error from re-yielding). Memory stays bounded to one chunk in
    // flight, matching the SFTP-native path's footprint.
    struct UploadState {
        file: tokio::fs::File,
        written: u64,
        done: bool,
    }
    let app = crate::app::instance();
    let task_id = task.id.clone();
    let local_path = task.local_path.clone();
    let cancel = cancel.clone();
    let body = Box::pin(stream::unfold(
        UploadState {
            file: local,
            written: 0,
            done: false,
        },
        move |mut st| {
            let app = app.clone();
            let task_id = task_id.clone();
            let local_path = local_path.clone();
            let cancel = cancel.clone();
            async move {
                use tokio::io::AsyncReadExt;
                if st.done {
                    return None;
                }
                if cancel.is_cancelled() {
                    st.done = true;
                    return Some((Err(Error::Io("upload cancelled".to_string())), st));
                }
                let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
                match st.file.read(&mut buf).await {
                    Ok(0) => None,
                    Ok(n) => {
                        st.written = st.written.saturating_add(n as u64);
                        app.transfers.set_progress(&task_id, st.written, &app.bus);
                        buf.truncate(n);
                        Some((Ok(bytes::Bytes::from(buf)), st))
                    }
                    Err(e) => {
                        st.done = true;
                        Some((Err(Error::Transport(format!("read {local_path}: {e}"))), st))
                    }
                }
            }
        },
    )) as crate::storage::ByteStream;
    provider
        .put_stream(&task.remote_path, body, Some(total))
        .await?;
    Ok(())
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
    // Stage the download in `<dest>.<task-id>.part` and rename
    // atomically once the SFTP read loop finishes. A retry after
    // a mid-flight failure (cancel / network drop) finds the
    // existing target file untouched — only the .part file is
    // ever truncated. Closes the audit's "transfer/driver
    // truncates partial files on every retry" gap.
    let part_path = crate::sftp::transfer_staging_path(&task.local_path, &task.id);
    // tokio::fs::File so the local I/O runs on the blocking pool —
    // the SFTP read at the top of the loop is async and does not
    // block its worker thread, but a slow disk on the write side
    // would otherwise pin the same worker and stall every other
    // task scheduled on it.
    let mut local = tokio::fs::File::create(&part_path)
        .await
        .map_err(|e| Error::Transport(format!("create {}: {e}", part_path)))?;
    // Single scratch buffer reused across every chunk read.
    let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
    let mut written: u64 = 0;
    let result: Result<(), Error> = async {
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
                .map_err(|e| Error::Transport(format!("write {}: {e}", part_path)))?;
            written = written.saturating_add(n as u64);
            app.transfers.set_progress(&task.id, written, &app.bus);
        }
        local
            .sync_all()
            .await
            .map_err(|e| Error::Transport(format!("fsync {}: {e}", part_path)))?;
        Ok(())
    }
    .await;
    drop(local);
    if result.is_err() {
        // Best-effort cleanup — leaving the .part file behind
        // would just trip the next retry's `File::create`
        // truncate (which is fine semantically), but explicit
        // delete keeps the support_dir tidy.
        let _ = tokio::fs::remove_file(&part_path).await;
        return result;
    }
    tokio::fs::rename(&part_path, &task.local_path)
        .await
        .map_err(|e| {
            Error::Transport(format!("rename {} → {}: {e}", part_path, task.local_path))
        })?;
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
    // Stage onto a sibling `<dest>.<task-id>.part` and promote it
    // over the destination only once the last byte lands. Writing
    // straight onto `task.remote_path` (SFTP `create` truncates on
    // open) would leave the prior remote file truncated or empty
    // whenever the user cancels or the link drops mid-upload —
    // silent remote data loss. Mirrors the download `.part` path.
    let part_path = crate::sftp::transfer_staging_path(&task.remote_path, &task.id);
    let mut written: u64 = 0;
    let result: Result<(), Error> = async {
        let remote = sftp.create(&part_path).await?;
        let mut buf = vec![0u8; TRANSFER_CHUNK_SIZE];
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
    .await;
    if result.is_err() {
        let _ = sftp.remove_file(&part_path).await;
        return result;
    }
    sftp.promote_staged(&part_path, &task.remote_path).await
}
#[cfg(test)]
#[path = "../../tests/unit/transfer_driver.rs"]
mod tests;
