//! Per-recording write queue + worker.
//!
//! `RecorderRegistry` already owns file IO + AES-GCM framing for an
//! active recording. The Dart-era `SessionRecorder` wrapped each
//! `recorder_record_event` FRB call in a single-subscription
//! `StreamController` + `asyncMap` so concurrent terminal output
//! events landed on disk in arrival order. The same serialisation
//! moves Rust-side here: each `RecorderId` gets a dedicated tokio
//! worker that drains an mpsc channel of [`QueueEntry`] items and
//! calls into the registry one entry at a time.
//!
//! The Dart shim is then a thin enqueue layer (`recorder_queue_enqueue_event`,
//! `…_header`, `…_rotate`, `…_close`) — fire-and-forget calls that
//! never await the write, so the caller's hot path (terminal stdout
//! pump) is unblocked even when the disk lags.
//!
//! Auto-rotation: the worker checks `bytes_written` after each
//! frame; once it crosses [`super::MAX_FILE_BYTES`], the worker
//! publishes [`super::Event::RecorderRotateRequested`] (a fresh
//! event variant carrying the recording id) and continues writing
//! to the current file until the Dart side hands back a fresh path
//! via `recorder_queue_enqueue_rotate`. A short overshoot of the
//! cap is tolerated rather than blocking the writer waiting for a
//! path round-trip.

use std::collections::HashMap;
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use super::{RecordDirection, RecorderId, MAX_FILE_BYTES};
use crate::bus::Event;
use crate::error::Error;

/// Flush a per-direction buffer immediately once it grows past this
/// many bytes, without waiting for [`FLUSH_DEADLINE`]. Replaces the
/// matching constant on the Dart side; absorbs `cat large_file`-style
/// bursts that would otherwise queue 100+ KiB into the buffer before
/// the deadline fires.
const FLUSH_THRESHOLD_BYTES: usize = 8 * 1024;

/// Maximum wall time a buffered byte may sit before the worker mailbox
/// receives it. A 10 ms budget mirrors a single 60 FPS animation
/// frame — the user-facing typing-to-render lag stays under one
/// frame.
const FLUSH_DEADLINE: Duration = Duration::from_millis(10);

/// One unit of work sent to a recording's worker. The worker
/// processes entries strictly in arrival order so the on-disk
/// asciinema event sequence reflects the user's typing /
/// terminal-output sequence even under concurrent enqueues.
#[derive(Debug)]
pub enum QueueEntry {
    /// Compose + write the asciinema v2 header line.
    Header {
        width: u32,
        height: u32,
        shell_label: String,
    },
    /// Compose + write an asciinema v2 event line. `bytes` is the
    /// terminal chunk (output or input) with no length cap; the
    /// worker hands it to `record_event` which fans out the
    /// per-frame AES-GCM envelope.
    Event {
        kind: RecordDirection,
        bytes: Vec<u8>,
    },
    /// Atomically rotate the recording to a new file. The Dart side
    /// allocates the path (it owns `getApplicationSupportDirectory`
    /// plus the `hardenFilePerms` platform sweep) so this entry
    /// just hands the worker the new destination.
    Rotate { new_path: String },
    /// Flush + close the recording's file and exit the worker.
    /// Subsequent enqueues for the same id no-op (the worker handle
    /// is removed by the worker before exit).
    Close,
}

/// Mailbox capacity per worker. Generous enough that terminal-storm
/// scenarios (paste → 10 000-char block) don't backpressure the FRB
/// caller; small enough that a wedged disk doesn't accumulate
/// gigabytes of in-flight chunks.
const QUEUE_CAPACITY: usize = 1024;

/// Process-singleton handle map. One [`WorkerHandle`] per active
/// recording id. Owned by `AppState`.
pub struct RecorderQueue {
    workers: Mutex<HashMap<RecorderId, WorkerHandle>>,
}

struct WorkerHandle {
    sender: mpsc::Sender<QueueEntry>,
    /// Held to keep the worker task alive until [`Self`] drops; the
    /// worker exits cleanly when the channel sender drops or a
    /// `Close` entry arrives. `Drop` aborts as a safety net so a
    /// `WorkerHandle` removed mid-shutdown (registry torn down
    /// before a tail `Close` flushed) doesn't leak a lingering
    /// task into the next runtime cycle.
    join: JoinHandle<()>,
    /// Per-direction byte accumulator that coalesces high-frequency
    /// russh `Data` packets into one mailbox entry per
    /// `FLUSH_THRESHOLD_BYTES` / `FLUSH_DEADLINE` so the writer
    /// worker isn't woken on every PTY chunk. Lives on the FRB side
    /// of the mailbox; Dart calls `enqueue_event_chunk` for every
    /// chunk and the buffer decides when to wake the worker.
    buffers: Arc<StdMutex<EventBuffers>>,
}

impl Drop for WorkerHandle {
    fn drop(&mut self) {
        // Abort is idempotent — safe to call on an already-completed
        // worker. Closes the audit's "WorkerHandle removed mid-
        // shutdown could leak the task" gap; clean exits via
        // `Close` entry still finish the queue normally before this
        // drop runs.
        self.join.abort();
    }
}

/// Per-direction byte accumulator + the in-flight 10 ms flush task
/// (if any). Split per direction because output and input compose
/// distinct asciinema event types — interleaving them inside a
/// single frame would corrupt the on-disk timeline.
struct EventBuffers {
    output: Vec<u8>,
    input: Vec<u8>,
    /// Set while a 10 ms timer is pending. Cleared by the timer
    /// itself or aborted by a threshold-overrun branch / a
    /// blocking enqueue (`Header` / `Rotate` / `Close` flushes
    /// pending bytes before its own entry).
    flush_task: Option<JoinHandle<()>>,
}

impl EventBuffers {
    fn new() -> Self {
        Self {
            output: Vec::new(),
            input: Vec::new(),
            flush_task: None,
        }
    }

    /// Take whatever is currently buffered and abort any pending
    /// flush task. Returns one entry per non-empty direction in
    /// `(Output, Input)` insertion order so callers can replay the
    /// drained frames into the mpsc mailbox.
    fn drain(&mut self) -> Vec<(RecordDirection, Vec<u8>)> {
        if let Some(h) = self.flush_task.take() {
            h.abort();
        }
        let mut out = Vec::new();
        if !self.output.is_empty() {
            out.push((RecordDirection::Output, std::mem::take(&mut self.output)));
        }
        if !self.input.is_empty() {
            out.push((RecordDirection::Input, std::mem::take(&mut self.input)));
        }
        out
    }
}

impl RecorderQueue {
    pub fn new() -> Self {
        Self {
            workers: Mutex::new(HashMap::new()),
        }
    }

    /// Spawn the per-id worker. Idempotent on a re-spawn for the
    /// same id — the displaced worker's channel drops, which makes
    /// that worker exit on its next `recv`. Call after
    /// `RecorderRegistry::register_with_io` so the actor row exists
    /// before the first entry arrives.
    pub async fn spawn(&self, id: RecorderId) {
        let (tx, rx) = mpsc::channel(QUEUE_CAPACITY);
        let worker_id = id.clone();
        let join = tokio::spawn(async move {
            worker_loop(worker_id, rx).await;
        });
        let mut g = self.workers.lock().await;
        g.insert(
            id,
            WorkerHandle {
                sender: tx,
                join,
                buffers: Arc::new(StdMutex::new(EventBuffers::new())),
            },
        );
    }

    /// Enqueue an entry for the given recording. Returns the
    /// "channel full" / "no worker" errors as `Error::Io` so the
    /// FRB caller can localise the failure. The success path is
    /// fire-and-forget — the worker's write happens out of band.
    pub async fn enqueue(&self, id: &str, entry: QueueEntry) -> Result<(), Error> {
        let sender = {
            let g = self.workers.lock().await;
            match g.get(id) {
                Some(h) => h.sender.clone(),
                None => {
                    return Err(Error::Recorder(format!("queue {id} not spawned")));
                }
            }
        };
        sender
            .send(entry)
            .await
            .map_err(|_| Error::Recorder(format!("queue {id} closed")))
    }

    /// Append one PTY chunk into the per-id, per-direction buffer.
    /// Wakes the worker either on the [`FLUSH_THRESHOLD_BYTES`]
    /// over-shoot (bypasses the timer) or via a single 10 ms task
    /// scheduled on the first non-empty buffer; callers therefore
    /// invoke this once per arriving russh `Data` packet without
    /// paying a worker wake-up per call. Concurrent chunks for the
    /// same id serialise on the per-id `StdMutex` — the lock is held
    /// only across the buffer math, never across an `await`.
    pub async fn enqueue_event_chunk(
        &self,
        id: &str,
        kind: RecordDirection,
        bytes: Vec<u8>,
    ) -> Result<(), Error> {
        if bytes.is_empty() {
            return Ok(());
        }
        let (sender, buffers) = {
            let g = self.workers.lock().await;
            let h = g
                .get(id)
                .ok_or_else(|| Error::Recorder(format!("queue {id} not spawned")))?;
            (h.sender.clone(), h.buffers.clone())
        };
        let drain_now = {
            // Poison-recovery contract: recover the inner state via
            // `into_inner` so a panic in another holder does not propagate
            // through every recorder write site. Mirrors the pattern used
            // across the codebase (see `prompt_registry::poisoned_mutex_recovers_via_into_inner`).
            let mut bufs = buffers.lock().unwrap_or_else(|p| p.into_inner());
            let buf = match kind {
                RecordDirection::Output => &mut bufs.output,
                RecordDirection::Input => &mut bufs.input,
            };
            buf.extend_from_slice(&bytes);
            if buf.len() >= FLUSH_THRESHOLD_BYTES {
                Some(bufs.drain())
            } else {
                if bufs.flush_task.is_none() {
                    let buffers_for_task = buffers.clone();
                    let sender_for_task = sender.clone();
                    bufs.flush_task = Some(tokio::spawn(async move {
                        tokio::time::sleep(FLUSH_DEADLINE).await;
                        let drained = {
                            let mut b = buffers_for_task.lock().unwrap_or_else(|p| p.into_inner());
                            b.flush_task = None;
                            b.drain()
                        };
                        for (k, bs) in drained {
                            // The receiver only drops once the
                            // worker is closing — surface the
                            // first send-failure as a warn so a
                            // race between the deadline-flush and
                            // a `Close` entry is greppable in
                            // support traces. Subsequent failures
                            // in the same drain stay silent
                            // (log-spam guard).
                            if let Err(e) = sender_for_task
                                .send(QueueEntry::Event { kind: k, bytes: bs })
                                .await
                            {
                                crate::app_log_warn!(
                                    "RecorderQueue",
                                    "deadline-flush send failed (worker closed): {}",
                                    e
                                );
                                break;
                            }
                        }
                    }));
                }
                None
            }
        };
        if let Some(items) = drain_now {
            for (k, bs) in items {
                sender
                    .send(QueueEntry::Event { kind: k, bytes: bs })
                    .await
                    .map_err(|_| Error::Recorder(format!("queue {id} closed")))?;
            }
        }
        Ok(())
    }

    /// Drain any pending buffered events into the mailbox, then send
    /// `entry`. Used for [`QueueEntry::Header`] / `Rotate` / `Close`
    /// so the asciinema timeline stays linear: pending output that
    /// arrived just before a rotate lands in the *old* file, not the
    /// new one; pending bytes before a close land on disk before
    /// the file is sealed.
    pub async fn enqueue_blocking(&self, id: &str, entry: QueueEntry) -> Result<(), Error> {
        let (sender, buffers) = {
            let g = self.workers.lock().await;
            let h = g
                .get(id)
                .ok_or_else(|| Error::Recorder(format!("queue {id} not spawned")))?;
            (h.sender.clone(), h.buffers.clone())
        };
        let drained = {
            let mut bufs = buffers.lock().unwrap_or_else(|p| p.into_inner());
            bufs.drain()
        };
        for (k, bs) in drained {
            sender
                .send(QueueEntry::Event { kind: k, bytes: bs })
                .await
                .map_err(|_| Error::Recorder(format!("queue {id} closed")))?;
        }
        sender
            .send(entry)
            .await
            .map_err(|_| Error::Recorder(format!("queue {id} closed")))
    }

    /// Best-effort drop the worker handle for `id`. Used at close
    /// to clear the slot once the `Close` entry has propagated.
    pub async fn drop_worker(&self, id: &str) {
        let mut g = self.workers.lock().await;
        g.remove(id);
    }

    pub async fn worker_count(&self) -> usize {
        self.workers.lock().await.len()
    }
}

impl Default for RecorderQueue {
    fn default() -> Self {
        Self::new()
    }
}

/// Surface a recorder-write failure: log at warn-level and publish
/// `Event::RecorderWriteFailed` so Dart can flip the row to an error
/// chip. Rate-limiting is the subscriber's job — the worker keeps
/// draining its mailbox so a transient failure on one frame does
/// not stop subsequent ones.
fn publish_recorder_failure(
    app: &std::sync::Arc<crate::app::AppState>,
    id: &str,
    kind: &str,
    detail: String,
) {
    crate::app_log_warn!("recorder", "queue {id} {kind} write failed: {detail}");
    app.bus.publish(Event::RecorderWriteFailed {
        id: id.to_string(),
        kind: kind.to_string(),
        detail,
    });
}

async fn worker_loop(id: RecorderId, mut rx: mpsc::Receiver<QueueEntry>) {
    // Snapshot the singleton AppState handle once. The worker keeps
    // a strong Arc; AppState lives for the process so this never
    // dangles. Cloning per-iteration keeps spawn_blocking's
    // requirement (`Send + 'static`) happy.
    let app = crate::app::instance();
    let mut rotate_requested = false;
    while let Some(entry) = rx.recv().await {
        match entry {
            QueueEntry::Header {
                width,
                height,
                shell_label,
            } => {
                let result = tokio::task::spawn_blocking({
                    let app = app.clone();
                    let id = id.clone();
                    move || {
                        app.recorders
                            .record_header(&id, width, height, &shell_label, &app.bus)
                    }
                })
                .await;
                match result {
                    Ok(Ok(_)) => {}
                    Ok(Err(e)) => publish_recorder_failure(&app, &id, "header", e.to_string()),
                    Err(join_err) => {
                        publish_recorder_failure(&app, &id, "header", join_err.to_string())
                    }
                }
            }
            QueueEntry::Event { kind, bytes } => {
                let result = tokio::task::spawn_blocking({
                    let app = app.clone();
                    let id = id.clone();
                    move || app.recorders.record_event(&id, kind, &bytes, &app.bus)
                })
                .await;
                let total_after = match result {
                    Ok(Ok(total)) => Some(total),
                    Ok(Err(e)) => {
                        publish_recorder_failure(&app, &id, "event", e.to_string());
                        None
                    }
                    Err(join_err) => {
                        publish_recorder_failure(&app, &id, "event", join_err.to_string());
                        None
                    }
                };
                if !rotate_requested {
                    if let Some(total) = total_after {
                        if total > MAX_FILE_BYTES {
                            rotate_requested = true;
                            app.bus.publish(Event::RecorderRotateRequested {
                                id: id.clone(),
                                bytes_written: total,
                            });
                        }
                    }
                }
            }
            QueueEntry::Rotate { new_path } => {
                let result = tokio::task::spawn_blocking({
                    let app = app.clone();
                    let id = id.clone();
                    move || app.recorders.rotate_to(&id, new_path, &app.bus)
                })
                .await;
                match result {
                    Ok(Ok(_)) => {}
                    Ok(Err(e)) => publish_recorder_failure(&app, &id, "rotate", e.to_string()),
                    Err(join_err) => {
                        publish_recorder_failure(&app, &id, "rotate", join_err.to_string())
                    }
                }
                // Reset the latched flag so the next over-cap write
                // can request another rotation.
                rotate_requested = false;
            }
            QueueEntry::Close => {
                let result = tokio::task::spawn_blocking({
                    let app = app.clone();
                    let id = id.clone();
                    move || app.recorders.close_with_io(&id, &app.bus)
                })
                .await;
                match result {
                    Ok(Ok(())) => {}
                    Ok(Err(e)) => publish_recorder_failure(&app, &id, "close", e.to_string()),
                    Err(join_err) => {
                        publish_recorder_failure(&app, &id, "close", join_err.to_string())
                    }
                }
                // Slot is dropped by the higher-level `drop_worker`
                // call so the WorkerHandle's `_join` does not point
                // back at us during the unwind.
                app.recorder_queue.drop_worker(&id).await;
                return;
            }
        }
    }
    // Channel closed without an explicit Close — best-effort flush.
    let result = tokio::task::spawn_blocking({
        let app = app.clone();
        let id = id.clone();
        move || app.recorders.close_with_io(&id, &app.bus)
    })
    .await;
    match result {
        Ok(Ok(())) => {}
        Ok(Err(e)) => publish_recorder_failure(&app, &id, "close", e.to_string()),
        Err(join_err) => publish_recorder_failure(&app, &id, "close", join_err.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tempfile(suffix: &str) -> String {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        let dir = std::env::temp_dir();
        dir.join(format!("lfs_recorder_queue_test_{pid}_{n}_{suffix}"))
            .to_string_lossy()
            .into_owned()
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn enqueue_event_via_singleton_serialises_writes() {
        // App + registry + queue are singletons. Smoke that
        // enqueueing through the queue lands a frame on disk.
        let app = crate::app::init();
        let path = tempfile("queue-enqueue");
        let id = format!("queue-{}", uuid_like());
        app.recorders
            .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
            .expect("register");
        app.recorder_queue.spawn(id.clone()).await;

        for chunk in 0..16 {
            app.recorder_queue
                .enqueue(
                    &id,
                    QueueEntry::Event {
                        kind: RecordDirection::Output,
                        bytes: format!("chunk-{chunk}\n").into_bytes(),
                    },
                )
                .await
                .expect("enqueue");
        }
        // Close drains the channel + closes the file.
        app.recorder_queue
            .enqueue(&id, QueueEntry::Close)
            .await
            .expect("close enqueue");
        // Give the worker a tick to drain.
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        let body = std::fs::read_to_string(&path).expect("read");
        // Plaintext mode → events appear verbatim, in order.
        for chunk in 0..16 {
            let token = format!("chunk-{chunk}");
            assert!(body.contains(&token), "expected {token:?} in {body:?}");
        }
        // Ordering check: chunk-0 appears before chunk-15.
        let pos_first = body.find("chunk-0").expect("first");
        let pos_last = body.find("chunk-15").expect("last");
        assert!(pos_first < pos_last, "events out of order: {body:?}");
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn enqueue_close_drops_worker() {
        let app = crate::app::init();
        let path = tempfile("queue-close");
        let id = format!("queue-close-{}", uuid_like());
        app.recorders
            .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
            .expect("register");
        app.recorder_queue.spawn(id.clone()).await;
        let before = app.recorder_queue.worker_count().await;
        assert!(before >= 1, "spawn should add a worker");
        app.recorder_queue
            .enqueue(&id, QueueEntry::Close)
            .await
            .expect("close enqueue");
        // Worker is async; poll briefly until it's gone.
        for _ in 0..50 {
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            let g = app.recorder_queue.workers.lock().await;
            if !g.contains_key(&id) {
                let _ = std::fs::remove_file(&path);
                return;
            }
        }
        panic!("worker never dropped");
    }

    /// Sequence-suffixed id so concurrent test cases don't collide
    /// inside the singleton registry.
    fn uuid_like() -> String {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let pid = std::process::id();
        format!("{pid}-{n}")
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn enqueue_event_chunk_coalesces_under_threshold() {
        let app = crate::app::init();
        let path = tempfile("chunk-coalesce");
        let id = format!("queue-chunk-{}", uuid_like());
        app.recorders
            .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
            .expect("register");
        app.recorder_queue.spawn(id.clone()).await;

        // Three small chunks well under the 8 KiB threshold. The
        // 10 ms timer is what eventually pushes them to the worker.
        for word in ["alpha", "bravo", "charlie"] {
            app.recorder_queue
                .enqueue_event_chunk(&id, RecordDirection::Output, word.as_bytes().to_vec())
                .await
                .expect("chunk");
        }
        // Wait long enough for the deadline to fire and the worker to
        // drain.
        tokio::time::sleep(Duration::from_millis(150)).await;
        app.recorder_queue
            .enqueue_blocking(&id, QueueEntry::Close)
            .await
            .expect("close");
        tokio::time::sleep(Duration::from_millis(150)).await;

        let body = std::fs::read_to_string(&path).expect("read");
        // The three chunks merged into one asciinema event line —
        // i.e. the substring `"alphabravocharlie"` must appear once
        // (the JSON payload escaping doesn't split runs of ASCII
        // letters).
        assert!(
            body.contains("alphabravocharlie"),
            "expected coalesced chunk in {body:?}"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn enqueue_event_chunk_flushes_on_threshold() {
        let app = crate::app::init();
        let path = tempfile("chunk-threshold");
        let id = format!("queue-thresh-{}", uuid_like());
        app.recorders
            .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
            .expect("register");
        app.recorder_queue.spawn(id.clone()).await;

        // One chunk over the threshold — flush should run before the
        // 10 ms timer would fire.
        let big = vec![b'A'; FLUSH_THRESHOLD_BYTES + 1];
        app.recorder_queue
            .enqueue_event_chunk(&id, RecordDirection::Output, big)
            .await
            .expect("chunk");
        // Brief wait — much shorter than the 10 ms deadline — to let
        // the worker process the immediate-flush mailbox entry.
        tokio::time::sleep(Duration::from_millis(50)).await;
        app.recorder_queue
            .enqueue_blocking(&id, QueueEntry::Close)
            .await
            .expect("close");
        tokio::time::sleep(Duration::from_millis(150)).await;

        let body = std::fs::read_to_string(&path).expect("read");
        // The 8 KiB+ run lands as a single event line in the file.
        let run = "A".repeat(FLUSH_THRESHOLD_BYTES + 1);
        assert!(
            body.contains(&run),
            "expected over-threshold chunk verbatim"
        );
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn enqueue_blocking_drains_pending_chunks_before_entry() {
        let app = crate::app::init();
        let path = tempfile("blocking-drain");
        let id = format!("queue-drain-{}", uuid_like());
        app.recorders
            .register_with_io(id.clone(), "s".into(), path.clone(), None, &app.bus)
            .expect("register");
        app.recorder_queue.spawn(id.clone()).await;

        // Buffer some bytes that haven't crossed the threshold and
        // would otherwise wait for the 10 ms timer.
        app.recorder_queue
            .enqueue_event_chunk(&id, RecordDirection::Output, b"pending-payload".to_vec())
            .await
            .expect("chunk");
        // Close must drain the buffered chunk first. Without the
        // pre-entry drain the trailing bytes would race the file
        // close and disappear.
        app.recorder_queue
            .enqueue_blocking(&id, QueueEntry::Close)
            .await
            .expect("close");
        tokio::time::sleep(Duration::from_millis(150)).await;

        let body = std::fs::read_to_string(&path).expect("read");
        assert!(
            body.contains("pending-payload"),
            "buffered chunk lost across close: {body:?}"
        );
        let _ = std::fs::remove_file(&path);
    }
}
