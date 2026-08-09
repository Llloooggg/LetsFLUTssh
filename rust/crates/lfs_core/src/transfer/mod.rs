//! Transfer queue + worker-pool driver.
//!
//! Owns the canonical state for the SFTP transfer queue: per-task
//! status (`Queued / Running / Completed / Failed / Cancelled`),
//! byte progress, insertion order. The bounded worker pool lives
//! in [`driver`]; production wires it to
//! [`driver::SftpTaskExecutor`] which drives
//! `Sftp::download_file` / `upload_file` against the active
//! connection actor's session.

pub mod driver;

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::bus::{Event, EventBus};
use crate::config::{DEFAULT_TRANSFER_WORKERS, MAX_TRANSFER_WORKERS};

/// Resolve the worker-pool size from the live config store,
/// clamped to `[1, MAX_TRANSFER_WORKERS]`. The FRB pool spawn calls
/// this so the user's "Parallel workers" setting actually sizes the
/// pool; an unreadable / unparseable config store falls back to
/// [`DEFAULT_TRANSFER_WORKERS`]. Mirrors the recorder's
/// `read_storage_cap_from_config_store` pattern — the pool is
/// spawned lazily and never resized, so the value is read once when
/// the first transfer creates the pool and applies for that session.
pub fn worker_count_from_config_store() -> usize {
    worker_count_from_json(crate::config_store::instance().get_json().as_deref())
}

/// Pure core of [`worker_count_from_config_store`] — parse the
/// `transfer_workers` field out of a config-store JSON snapshot and
/// clamp it to `[1, MAX_TRANSFER_WORKERS]`, falling back to
/// [`DEFAULT_TRANSFER_WORKERS`] when the snapshot is absent,
/// unparseable, or missing the field. Split out so the read of the
/// process-global config-store singleton stays in the thin wrapper.
fn worker_count_from_json(json: Option<&str>) -> usize {
    let raw = json
        .and_then(|j| serde_json::from_str::<serde_json::Value>(j).ok())
        .and_then(|v| {
            v.as_object()
                .and_then(|o| o.get("transfer_workers"))
                .and_then(serde_json::Value::as_i64)
        })
        .unwrap_or(DEFAULT_TRANSFER_WORKERS);
    raw.clamp(1, MAX_TRANSFER_WORKERS) as usize
}

#[cfg(test)]
mod worker_count_tests {
    use super::*;

    #[test]
    fn absent_snapshot_falls_back_to_default() {
        assert_eq!(
            worker_count_from_json(None),
            DEFAULT_TRANSFER_WORKERS as usize
        );
    }

    #[test]
    fn unparseable_or_missing_field_falls_back_to_default() {
        assert_eq!(
            worker_count_from_json(Some("not json")),
            DEFAULT_TRANSFER_WORKERS as usize
        );
        assert_eq!(
            worker_count_from_json(Some("{\"font_size\":14}")),
            DEFAULT_TRANSFER_WORKERS as usize
        );
    }

    #[test]
    fn reads_and_clamps_the_field() {
        assert_eq!(worker_count_from_json(Some("{\"transfer_workers\":3}")), 3);
        assert_eq!(worker_count_from_json(Some("{\"transfer_workers\":0}")), 1);
        assert_eq!(
            worker_count_from_json(Some("{\"transfer_workers\":500}")),
            MAX_TRANSFER_WORKERS as usize
        );
    }
}

/// Minimum byte-delta between two progress publishes for the same
/// task. Caps the bus event rate at one per 256 KiB regardless of
/// chunk size — without this the SFTP read loop emits one event
/// per chunk, which detonates Dart-side: every event triggers a
/// `_scheduleRefresh` that rebuilds the full transfer history
/// snapshot.
const PROGRESS_BYTES_THRESHOLD: u64 = 256 * 1024;

/// Minimum wall time between two progress publishes for the same
/// task. Catches the small-file / slow-link case where the byte
/// delta hits the threshold quickly but the user's UI does not need
/// 60 fps progress updates anyway.
const PROGRESS_TIME_THRESHOLD: Duration = Duration::from_millis(100);

/// Stable identifier for a queued task. Allocated Dart-side via
/// `Uuid().v4()` so the same string flows through Riverpod
/// ownership before the worker pool starts the transfer.
pub type TaskId = String;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskKind {
    Download,
    Upload,
}

#[derive(Debug, Clone)]
pub struct TaskSnapshot {
    pub id: TaskId,
    pub kind: TaskKind,
    pub session_id: String,
    pub remote_path: String,
    pub local_path: String,
    pub state: TaskState,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub error: Option<String>,
}

#[derive(Debug)]
pub struct TaskActor {
    pub id: TaskId,
    pub kind: TaskKind,
    pub session_id: String,
    pub remote_path: String,
    pub local_path: String,
    pub state: TaskState,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub error: Option<String>,
    /// Bytes-done value at the time of the last `TransferTaskProgress`
    /// publish. Combined with [`PROGRESS_BYTES_THRESHOLD`] to
    /// throttle the bus event rate.
    pub progress_published_bytes: u64,
    /// Wall clock at the time of the last `TransferTaskProgress`
    /// publish. `None` means "never published yet" — the first
    /// `set_progress` call publishes unconditionally so the Dart UI
    /// sees an early "transfer started" tick.
    pub progress_published_at: Option<Instant>,
}

impl TaskActor {
    pub fn snapshot(&self) -> TaskSnapshot {
        TaskSnapshot {
            id: self.id.clone(),
            kind: self.kind,
            session_id: self.session_id.clone(),
            remote_path: self.remote_path.clone(),
            local_path: self.local_path.clone(),
            state: self.state,
            bytes_done: self.bytes_done,
            bytes_total: self.bytes_total,
            error: self.error.clone(),
        }
    }
}

/// Bundled inputs for [`TransferQueue::enqueue`]. Bundling the
/// per-task fields keeps the call signature under clippy's
/// too-many-arguments threshold and lets the FRB shim pass a
/// typed payload through verbatim.
#[derive(Clone, Debug)]
pub struct EnqueueRequest {
    pub id: TaskId,
    pub kind: TaskKind,
    pub session_id: String,
    pub remote_path: String,
    pub local_path: String,
    pub bytes_total: u64,
}

/// Process-singleton transfer queue. Owned by `AppState`.
pub struct TransferQueue {
    inner: Mutex<QueueInner>,
}

struct QueueInner {
    by_id: HashMap<TaskId, TaskActor>,
    /// Insertion order — preserved for the workspace transfer
    /// panel that renders rows in the order the user enqueued.
    order: Vec<TaskId>,
}

impl TransferQueue {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(QueueInner {
                by_id: HashMap::new(),
                order: Vec::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, QueueInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Enqueue a fresh task. Emits `TransferTaskAdded`. Idempotent
    /// on repeated id (later enqueues replace the row).
    pub fn enqueue(&self, req: EnqueueRequest, bus: &EventBus) -> TaskSnapshot {
        let EnqueueRequest {
            id,
            kind,
            session_id,
            remote_path,
            local_path,
            bytes_total,
        } = req;
        let actor = TaskActor {
            id: id.clone(),
            kind,
            session_id,
            remote_path,
            local_path,
            state: TaskState::Queued,
            bytes_done: 0,
            bytes_total,
            error: None,
            progress_published_bytes: 0,
            progress_published_at: None,
        };
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            if !g.by_id.contains_key(&id) {
                g.order.push(id.clone());
            }
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::TransferTaskAdded { id });
        snap
    }

    /// Update a task's state. Emits `TransferTaskState`.
    pub fn set_state(&self, id: &str, state: TaskState, bus: &EventBus) {
        let changed = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            if actor.state == state {
                return;
            }
            actor.state = state;
            true
        };
        if changed {
            bus.publish(Event::TransferTaskState {
                id: id.to_string(),
                state,
            });
        }
    }

    /// Set the bytes-done counter. Emits `TransferTaskProgress`
    /// **only when** the new value is at least
    /// [`PROGRESS_BYTES_THRESHOLD`] past the last publish OR
    /// [`PROGRESS_TIME_THRESHOLD`] has elapsed since the last
    /// publish (or this is the first publish, or the task is
    /// finishing — `bytes_done >= bytes_total > 0`). Skipped events
    /// still update the in-memory counter, so a subsequent
    /// `task_snapshot` reads the latest value; the next eligible
    /// `set_progress` call publishes it.
    pub fn set_progress(&self, id: &str, bytes_done: u64, bus: &EventBus) {
        let publish: bool;
        let bytes_total;
        {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            actor.bytes_done = bytes_done;
            bytes_total = actor.bytes_total;
            let now = Instant::now();
            publish = match actor.progress_published_at {
                None => true,
                Some(prev_at) => {
                    let bytes_delta = bytes_done.saturating_sub(actor.progress_published_bytes);
                    let time_elapsed = now.duration_since(prev_at);
                    let finished = bytes_total > 0 && bytes_done >= bytes_total;
                    finished
                        || bytes_delta >= PROGRESS_BYTES_THRESHOLD
                        || time_elapsed >= PROGRESS_TIME_THRESHOLD
                }
            };
            if publish {
                actor.progress_published_bytes = bytes_done;
                actor.progress_published_at = Some(now);
            }
        }
        if publish {
            bus.publish(Event::TransferTaskProgress {
                id: id.to_string(),
                bytes_done,
                bytes_total,
            });
        }
    }

    /// Mark the task `Cancelled`. Idempotent — re-cancelling a
    /// terminal task (already `Completed` / `Failed` / `Cancelled`)
    /// is a no-op so a racing UI cancel during shutdown doesn't
    /// over-write a real failure detail. Returns `true` when the
    /// state actually changed.
    pub fn cancel(&self, id: &str, bus: &EventBus) -> bool {
        let changed = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return false;
            };
            // Cancelling something already in a terminal state is a
            // no-op — we don't want to clobber a recorded
            // `Completed` or `Failed` with `Cancelled`.
            if matches!(
                actor.state,
                TaskState::Completed | TaskState::Failed | TaskState::Cancelled
            ) {
                return false;
            }
            actor.state = TaskState::Cancelled;
            true
        };
        if changed {
            bus.publish(Event::TransferTaskState {
                id: id.to_string(),
                state: TaskState::Cancelled,
            });
        }
        changed
    }

    /// Drop a terminal task from the queue. Idempotent on a missing
    /// or non-terminal id (running / queued tasks must be cancelled
    /// first — clearing them mid-flight would leave the worker
    /// driver writing into a vanished row).
    pub fn drop_terminal(&self, id: &str) -> bool {
        let mut g = self.lock();
        let Some(actor) = g.by_id.get(id) else {
            return false;
        };
        if !matches!(
            actor.state,
            TaskState::Completed | TaskState::Failed | TaskState::Cancelled
        ) {
            return false;
        }
        g.by_id.remove(id);
        g.order.retain(|x| x != id);
        true
    }

    /// Record a terminal failure on the task — sets state to
    /// `Failed` + stores the message.
    pub fn fail(&self, id: &str, message: String, bus: &EventBus) {
        let mut g = self.lock();
        let Some(actor) = g.by_id.get_mut(id) else {
            return;
        };
        actor.state = TaskState::Failed;
        actor.error = Some(message.clone());
        drop(g);
        bus.publish(Event::TransferTaskState {
            id: id.to_string(),
            state: TaskState::Failed,
        });
        bus.publish(Event::TransferTaskError {
            id: id.to_string(),
            detail: message,
        });
    }

    pub fn snapshot(&self, id: &str) -> Option<TaskSnapshot> {
        self.lock().by_id.get(id).map(|a| a.snapshot())
    }

    pub fn snapshot_all(&self) -> Vec<TaskSnapshot> {
        let g = self.lock();
        g.order
            .iter()
            .filter_map(|id| g.by_id.get(id).map(|a| a.snapshot()))
            .collect()
    }

    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }
}

impl Default for TransferQueue {
    fn default() -> Self {
        Self::new()
    }
}
#[cfg(test)]
#[path = "../../tests/unit/transfer_mod.rs"]
mod tests;
