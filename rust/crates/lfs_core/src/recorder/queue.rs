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

use tokio::sync::{mpsc, Mutex};
use tokio::task::JoinHandle;

use super::{RecordDirection, RecorderId, MAX_FILE_BYTES};
use crate::bus::Event;
use crate::error::Error;

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
    /// `Close` entry arrives.
    _join: JoinHandle<()>,
}

impl RecorderQueue {
    pub fn new() -> Self {
        Self {
            workers: Mutex::new(HashMap::new()),
        }
    }

    /// Spawn the per-id worker. Idempotent on a re-spawn for the
    /// same id (the prior worker's channel drops, which causes the
    /// prior worker to exit on its next `recv`). Call after
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
                _join: join,
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
                    return Err(Error::Io(format!("recorder queue {id} not spawned")));
                }
            }
        };
        sender
            .send(entry)
            .await
            .map_err(|_| Error::Io(format!("recorder queue {id} closed")))
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
                let app = app.clone();
                let id = id.clone();
                let _ = tokio::task::spawn_blocking(move || {
                    let _ = app
                        .recorders
                        .record_header(&id, width, height, &shell_label, &app.bus);
                })
                .await;
            }
            QueueEntry::Event { kind, bytes } => {
                let app_for_task = app.clone();
                let id_for_task = id.clone();
                let total_after = tokio::task::spawn_blocking(move || {
                    app_for_task
                        .recorders
                        .record_event(&id_for_task, kind, &bytes, &app_for_task.bus)
                        .ok()
                })
                .await
                .ok()
                .flatten();
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
                let app = app.clone();
                let id = id.clone();
                let _ = tokio::task::spawn_blocking(move || {
                    let _ = app.recorders.rotate_to(&id, new_path, &app.bus);
                })
                .await;
                // Reset the latched flag so the next over-cap write
                // can request another rotation.
                rotate_requested = false;
            }
            QueueEntry::Close => {
                let app_inner = app.clone();
                let id_inner = id.clone();
                let _ = tokio::task::spawn_blocking(move || {
                    let _ = app_inner.recorders.close_with_io(&id_inner, &app_inner.bus);
                })
                .await;
                // Slot is dropped by the higher-level `drop_worker`
                // call so the WorkerHandle's `_join` does not point
                // back at us during the unwind.
                app.recorder_queue.drop_worker(&id).await;
                return;
            }
        }
    }
    // Channel closed without an explicit Close — best-effort flush.
    let app_inner = app.clone();
    let id_inner = id.clone();
    let _ = tokio::task::spawn_blocking(move || {
        let _ = app_inner.recorders.close_with_io(&id_inner, &app_inner.bus);
    })
    .await;
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
}
