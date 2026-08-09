/// Unit tests extracted from transfer/driver.rs
/// Declared via `#[path] mod tests;` in the source file.
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
