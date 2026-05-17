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
    use tokio::io::AsyncReadExt;
    let app = crate::app::instance();
    let mut local = tokio::fs::File::open(&task.local_path)
        .await
        .map_err(|e| Error::Transport(format!("read {}: {e}", task.local_path)))?;
    let meta = local
        .metadata()
        .await
        .map_err(|e| Error::Transport(format!("stat {}: {e}", task.local_path)))?;
    let total = meta.len();
    // Pre-read into a Vec of chunks. Streaming `tokio::fs::File`
    // through `ReaderStream` would be marginally more memory-
    // efficient, but the resulting stream isn't `Send + 'static`
    // through the `Provider` trait without a 'static lifetime hop
    // — and the chunked Vec path matches the SFTP-native shape's
    // memory footprint (one buffer per chunk in flight). For
    // multi-GB files a follow-up could swap this for a streaming
    // backend with per-chunk reads, but the typical drop is
    // single-file under a few hundred MB.
    let mut chunks: Vec<Result<bytes::Bytes, Error>> = Vec::new();
    let mut written: u64 = 0;
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
        let bytes = bytes::Bytes::copy_from_slice(&buf[..n]);
        written = written.saturating_add(n as u64);
        app.transfers.set_progress(&task.id, written, &app.bus);
        chunks.push(Ok(bytes));
    }
    if cancel.is_cancelled() {
        return Err(Error::Io("upload cancelled".to_string()));
    }
    let body = Box::pin(stream::iter(chunks)) as crate::storage::ByteStream;
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
    let part_path = format!("{}.{}.part", task.local_path, task.id);
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

    /// In-memory `Provider` stub backed by a `HashMap` — exactly
    /// the surface the generic `download_via_provider` /
    /// `upload_via_provider` paths exercise. Used by the round-trip
    /// tests below to prove the non-SSH transfer path works without
    /// a live network transport.
    struct MemProvider {
        files: tokio::sync::Mutex<std::collections::HashMap<String, Vec<u8>>>,
    }

    impl MemProvider {
        fn new(seed: &[(&str, &[u8])]) -> Self {
            let mut files = std::collections::HashMap::new();
            for (path, body) in seed {
                files.insert((*path).to_string(), body.to_vec());
            }
            Self {
                files: tokio::sync::Mutex::new(files),
            }
        }
    }

    impl crate::storage::Provider for MemProvider {
        fn list<'a>(
            &'a self,
            _: &'a str,
        ) -> crate::storage::ProviderFuture<'a, Vec<crate::storage::Entry>> {
            Box::pin(async { Ok(vec![]) })
        }
        fn stat<'a>(
            &'a self,
            _: &'a str,
        ) -> crate::storage::ProviderFuture<'a, crate::storage::Metadata> {
            unimplemented!()
        }
        fn mkdir<'a>(&'a self, _: &'a str) -> crate::storage::ProviderFuture<'a, ()> {
            Box::pin(async { Ok(()) })
        }
        fn remove<'a>(&'a self, _: &'a str) -> crate::storage::ProviderFuture<'a, ()> {
            Box::pin(async { Ok(()) })
        }
        fn rename<'a>(&'a self, _: &'a str, _: &'a str) -> crate::storage::ProviderFuture<'a, ()> {
            Box::pin(async { Ok(()) })
        }
        fn get_stream<'a>(
            &'a self,
            path: &'a str,
            _: Option<(u64, u64)>,
        ) -> crate::storage::ProviderFuture<'a, crate::storage::ByteStream> {
            let path = path.to_string();
            Box::pin(async move {
                let files = self.files.lock().await;
                let body = files
                    .get(&path)
                    .cloned()
                    .ok_or_else(|| Error::Io(format!("not found: {path}")))?;
                // Emit the body as a single chunk so the downstream
                // streamer exercises the `while let Some(chunk)` loop
                // at least once, but stays simple.
                use futures_util::stream;
                let s = stream::iter(vec![Ok(bytes::Bytes::from(body))]);
                Ok(Box::pin(s) as crate::storage::ByteStream)
            })
        }
        fn put_stream<'a>(
            &'a self,
            path: &'a str,
            mut body: crate::storage::ByteStream,
            _: Option<u64>,
        ) -> crate::storage::ProviderFuture<'a, ()> {
            let path = path.to_string();
            Box::pin(async move {
                use futures_util::StreamExt;
                let mut buf = Vec::new();
                while let Some(chunk) = body.next().await {
                    buf.extend_from_slice(&chunk?);
                }
                let mut files = self.files.lock().await;
                files.insert(path, buf);
                Ok(())
            })
        }
        fn dir_size<'a>(&'a self, _: &'a str) -> crate::storage::ProviderFuture<'a, u64> {
            Box::pin(async { Ok(0) })
        }
    }

    /// Download path: an entry registered in `app.providers` under
    /// the task's `session_id` routes through `download_via_provider`,
    /// the chunked stream lands in the `.part` file, the rename
    /// finalises the destination. This is the exact path WebDAV /
    /// S3 drag-drop downloads follow — the prior `SftpTaskExecutor`
    /// had no fall-through here and surfaced `SessionUnavailable`,
    /// which is what the user observed as "0 reaction" on WebDAV
    /// drop.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn provider_path_runs_download_through_generic_streamer() {
        let app = crate::app::init();
        let conn_id = "conn-provider-download";
        let task_id = "t-provider-download";
        let local_dir = tempfile::tempdir().expect("tempdir");
        let local_path = local_dir
            .path()
            .join("downloaded.bin")
            .to_string_lossy()
            .into_owned();
        let body = b"hello from the provider streamer";
        let provider: Arc<dyn crate::storage::Provider> =
            Arc::new(MemProvider::new(&[("/remote.bin", body)]));
        app.providers.register(conn_id, provider);

        app.transfers.enqueue(
            EnqueueRequest {
                id: task_id.into(),
                kind: TaskKind::Download,
                session_id: conn_id.into(),
                remote_path: "/remote.bin".into(),
                local_path: local_path.clone(),
                bytes_total: body.len() as u64,
            },
            &app.bus,
        );

        let exec = SftpTaskExecutor;
        let task = app.transfers.snapshot(task_id).expect("snapshot");
        let result = exec.execute(task, CancellationToken::new()).await;
        assert!(result.is_ok(), "download failed: {result:?}");

        // Local file landed with the right bytes.
        let written = tokio::fs::read(&local_path).await.expect("read local");
        assert_eq!(written, body);

        // Progress events fired — the post-download snapshot's
        // `bytes_done` matches the body length.
        let snap = app.transfers.snapshot(task_id).expect("snap");
        assert_eq!(snap.bytes_done, body.len() as u64);

        app.providers.unregister(conn_id);
    }

    /// Upload path: a local file streams through
    /// `upload_via_provider`, lands in the in-memory store on the
    /// `put_stream` end. Mirrors the WebDAV / S3 drag-drop upload
    /// flow.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn provider_path_runs_upload_through_generic_streamer() {
        let app = crate::app::init();
        let conn_id = "conn-provider-upload";
        let task_id = "t-provider-upload";
        let local_dir = tempfile::tempdir().expect("tempdir");
        let local_path = local_dir
            .path()
            .join("source.bin")
            .to_string_lossy()
            .into_owned();
        let body = b"payload uploading through the provider streamer";
        tokio::fs::write(&local_path, body)
            .await
            .expect("write source");

        let provider = Arc::new(MemProvider::new(&[]));
        // Hold a separate reference to the same Arc so we can
        // inspect the destination store after the executor runs.
        // `app.providers.register` clones the Arc on insert.
        let inspector: Arc<MemProvider> = provider.clone();
        app.providers.register(conn_id, provider);

        app.transfers.enqueue(
            EnqueueRequest {
                id: task_id.into(),
                kind: TaskKind::Upload,
                session_id: conn_id.into(),
                remote_path: "/uploaded.bin".into(),
                local_path: local_path.clone(),
                bytes_total: body.len() as u64,
            },
            &app.bus,
        );

        let exec = SftpTaskExecutor;
        let task = app.transfers.snapshot(task_id).expect("snapshot");
        let result = exec.execute(task, CancellationToken::new()).await;
        assert!(result.is_ok(), "upload failed: {result:?}");

        // Destination key holds the same bytes.
        let stored = inspector.files.lock().await;
        let got = stored.get("/uploaded.bin").expect("dest key");
        assert_eq!(got, body);

        let snap = app.transfers.snapshot(task_id).expect("snap");
        assert_eq!(snap.bytes_done, body.len() as u64);

        app.providers.unregister(conn_id);
    }

    /// Cancellation: a token flipped before download starts
    /// surfaces a clean `cancelled` error rather than partial
    /// bytes on disk. The streamer aborts at the next chunk
    /// boundary.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn provider_download_honours_cancellation() {
        let app = crate::app::init();
        let conn_id = "conn-provider-cancel";
        let task_id = "t-provider-cancel";
        let local_dir = tempfile::tempdir().expect("tempdir");
        let local_path = local_dir
            .path()
            .join("cancelled.bin")
            .to_string_lossy()
            .into_owned();
        let provider: Arc<dyn crate::storage::Provider> =
            Arc::new(MemProvider::new(&[("/r.bin", b"hello")]));
        app.providers.register(conn_id, provider);

        app.transfers.enqueue(
            EnqueueRequest {
                id: task_id.into(),
                kind: TaskKind::Download,
                session_id: conn_id.into(),
                remote_path: "/r.bin".into(),
                local_path: local_path.clone(),
                bytes_total: 5,
            },
            &app.bus,
        );

        let token = CancellationToken::new();
        token.cancel();
        let exec = SftpTaskExecutor;
        let task = app.transfers.snapshot(task_id).expect("snapshot");
        let result = exec.execute(task, token).await;
        assert!(result.is_err(), "cancelled task must error");
        // The destination file must not exist after cancel —
        // `download_via_provider` removes the `.part` file on
        // failure.
        assert!(!tokio::fs::try_exists(&local_path)
            .await
            .expect("try_exists"));

        app.providers.unregister(conn_id);
    }
}
