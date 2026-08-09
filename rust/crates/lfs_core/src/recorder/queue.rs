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
                    bufs.flush_task = Some(spawn_deadline_flush(buffers.clone(), sender.clone()));
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

/// Schedule the single deadline flush for a freshly non-empty
/// buffer set: sleep [`FLUSH_DEADLINE`], drain, then forward each
/// drained chunk to the worker mailbox. Clears its own
/// `flush_task` slot before draining so the next chunk re-arms.
fn spawn_deadline_flush(
    buffers: Arc<StdMutex<EventBuffers>>,
    sender: mpsc::Sender<QueueEntry>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        tokio::time::sleep(FLUSH_DEADLINE).await;
        let drained = {
            let mut b = buffers.lock().unwrap_or_else(|p| p.into_inner());
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
            if let Err(e) = sender.send(QueueEntry::Event { kind: k, bytes: bs }).await {
                crate::app_log_warn!(
                    "RecorderQueue",
                    "deadline-flush send failed (worker closed): {}",
                    e
                );
                break;
            }
        }
    })
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
            } => handle_header(&app, &id, width, height, shell_label).await,
            QueueEntry::Event { kind, bytes } => {
                handle_event(&app, &id, kind, bytes, &mut rotate_requested).await
            }
            QueueEntry::Rotate { new_path } => {
                handle_rotate(&app, &id, new_path, &mut rotate_requested).await
            }
            QueueEntry::Close => {
                handle_close(&app, &id).await;
                // Slot is dropped by the higher-level `drop_worker`
                // call so the WorkerHandle's `_join` does not point
                // back at us during the unwind.
                app.recorder_queue.drop_worker(&id).await;
                return;
            }
        }
    }
    // Channel closed without an explicit Close — best-effort flush.
    handle_close(&app, &id).await;
}

/// Resolve a `spawn_blocking` join result for a recorder op, routing
/// both the inner `Error` and the `JoinError` through
/// [`publish_recorder_failure`] under `kind`. Returns the op's value
/// on success or `None` on either failure.
fn resolve_blocking_result<T>(
    app: &Arc<crate::app::AppState>,
    id: &RecorderId,
    kind: &str,
    result: Result<Result<T, Error>, tokio::task::JoinError>,
) -> Option<T> {
    match result {
        Ok(Ok(v)) => Some(v),
        Ok(Err(e)) => {
            publish_recorder_failure(app, id, kind, e.to_string());
            None
        }
        Err(join_err) => {
            publish_recorder_failure(app, id, kind, join_err.to_string());
            None
        }
    }
}

async fn handle_header(
    app: &Arc<crate::app::AppState>,
    id: &RecorderId,
    width: u32,
    height: u32,
    shell_label: String,
) {
    let result = tokio::task::spawn_blocking({
        let app = app.clone();
        let id = id.clone();
        move || {
            app.recorders
                .record_header(&id, width, height, &shell_label, &app.bus)
        }
    })
    .await;
    resolve_blocking_result(app, id, "header", result);
}

async fn handle_event(
    app: &Arc<crate::app::AppState>,
    id: &RecorderId,
    kind: RecordDirection,
    bytes: Vec<u8>,
    rotate_requested: &mut bool,
) {
    let result = tokio::task::spawn_blocking({
        let app = app.clone();
        let id = id.clone();
        move || app.recorders.record_event(&id, kind, &bytes, &app.bus)
    })
    .await;
    let total_after = resolve_blocking_result(app, id, "event", result);
    if !*rotate_requested {
        if let Some(total) = total_after {
            if total > MAX_FILE_BYTES {
                *rotate_requested = true;
                app.bus.publish(Event::RecorderRotateRequested {
                    id: id.clone(),
                    bytes_written: total,
                });
            }
        }
    }
}

async fn handle_rotate(
    app: &Arc<crate::app::AppState>,
    id: &RecorderId,
    new_path: String,
    rotate_requested: &mut bool,
) {
    let result = tokio::task::spawn_blocking({
        let app = app.clone();
        let id = id.clone();
        move || app.recorders.rotate_to(&id, new_path, &app.bus)
    })
    .await;
    resolve_blocking_result(app, id, "rotate", result);
    // Reset the latched flag so the next over-cap write
    // can request another rotation.
    *rotate_requested = false;
}

async fn handle_close(app: &Arc<crate::app::AppState>, id: &RecorderId) {
    let result = tokio::task::spawn_blocking({
        let app = app.clone();
        let id = id.clone();
        move || app.recorders.close_with_io(&id, &app.bus)
    })
    .await;
    resolve_blocking_result(app, id, "close", result);
}
#[cfg(test)]
#[path = "../../tests/unit/recorder_queue.rs"]
mod tests;
