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

/// Minimum byte-delta between two progress publishes for the same
/// task. Caps the bus event rate at one per 256 KiB regardless of
/// chunk size — without this the SFTP read loop emits an event per
/// 64 KiB chunk (~3200 events / s on a 100 MB/s pipe), which
/// detonates Dart-side: each event triggers a `_scheduleRefresh`
/// that rebuilds the full transfer history snapshot.
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
        self.inner.lock().expect("transfer queue mutex poisoned")
    }

    /// Enqueue a fresh task. Emits `TransferTaskAdded`. Idempotent
    /// on repeated id (later enqueues replace the row).
    #[allow(clippy::too_many_arguments)]
    pub fn enqueue(
        &self,
        id: TaskId,
        kind: TaskKind,
        session_id: String,
        remote_path: String,
        local_path: String,
        bytes_total: u64,
        bus: &EventBus,
    ) -> TaskSnapshot {
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
mod tests {
    use super::*;

    #[test]
    fn enqueue_and_progress() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Download,
            "s1".into(),
            "/r/path".into(),
            "/l/path".into(),
            1024,
            &bus,
        );
        q.set_progress("t1", 512, &bus);
        let snap = q.snapshot("t1").unwrap();
        assert_eq!(snap.bytes_done, 512);
        assert_eq!(snap.bytes_total, 1024);
        assert_eq!(snap.state, TaskState::Queued);
    }

    /// Regression for the bus-event storm: tight `set_progress`
    /// calls per 64 KiB chunk used to publish one event each (~3200
    /// events/s/conn at 100 MB/s — full Dart-side history snapshot
    /// rebuild for every event). Throttling caps at one event per
    /// 256 KiB (or per 100 ms — see `PROGRESS_BYTES_THRESHOLD` /
    /// `PROGRESS_TIME_THRESHOLD`). 16 calls of 64 KiB increments
    /// against a 10 MiB total cover that ladder: first publish
    /// (always fires), then every 4-th call clears the byte
    /// threshold. Sub-100 ms wall time so the time-based threshold
    /// does NOT fire for the in-between calls.
    #[test]
    fn set_progress_throttles_high_frequency_byte_deltas() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Download,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            10 * 1024 * 1024,
            &bus,
        );
        // Drain the TransferTaskAdded event so the receiver only
        // sees TransferTaskProgress hits.
        let _ = rx.try_recv();
        const CHUNK: u64 = 64 * 1024;
        for i in 1..=16 {
            q.set_progress("t1", CHUNK * i, &bus);
        }
        // Snapshot reflects the LATEST byte count regardless of
        // throttle — counter updates are non-skipped.
        assert_eq!(q.snapshot("t1").unwrap().bytes_done, CHUNK * 16);
        // Count the published progress events. With a 256 KiB
        // threshold we expect 1 (first publish) + 1 every 4 chunks
        // ≤ 5 total. Without the throttle this would be 16.
        let mut progress_events = 0;
        while let Ok(evt) = rx.try_recv() {
            if let Event::TransferTaskProgress { .. } = evt {
                progress_events += 1;
            }
        }
        assert!(
            progress_events <= 5,
            "expected ≤ 5 throttled progress events, got {progress_events}"
        );
        assert!(
            progress_events >= 1,
            "first publish must always fire, got {progress_events}"
        );
    }

    /// The completion edge — `bytes_done == bytes_total > 0` —
    /// must publish unconditionally so the Dart UI sees the final
    /// counter value before the state→Completed transition.
    #[test]
    fn set_progress_publishes_final_value_unconditionally() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Upload,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            1024,
            &bus,
        );
        let _ = rx.try_recv();
        q.set_progress("t1", 1, &bus); // first publish (always)
                                       // A near-zero delta would normally be throttled. The
                                       // completion check overrides because bytes_done == total.
        q.set_progress("t1", 1024, &bus);
        let mut saw_complete = false;
        while let Ok(evt) = rx.try_recv() {
            if let Event::TransferTaskProgress {
                bytes_done: 1024, ..
            } = evt
            {
                saw_complete = true;
            }
        }
        assert!(
            saw_complete,
            "completion publish must fire even on tiny delta"
        );
    }

    #[test]
    fn fail_records_error() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Upload,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.fail("t1", "permission denied".into(), &bus);
        let snap = q.snapshot("t1").unwrap();
        assert_eq!(snap.state, TaskState::Failed);
        assert_eq!(snap.error.as_deref(), Some("permission denied"));
    }

    #[test]
    fn cancel_running_task() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Download,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.set_state("t1", TaskState::Running, &bus);
        assert!(q.cancel("t1", &bus));
        assert_eq!(q.snapshot("t1").unwrap().state, TaskState::Cancelled);
    }

    #[test]
    fn cancel_completed_is_noop() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Download,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.set_state("t1", TaskState::Completed, &bus);
        assert!(!q.cancel("t1", &bus));
        assert_eq!(q.snapshot("t1").unwrap().state, TaskState::Completed);
    }

    #[test]
    fn cancel_failed_does_not_clobber_error() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Download,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.fail("t1", "boom".into(), &bus);
        assert!(!q.cancel("t1", &bus));
        let snap = q.snapshot("t1").unwrap();
        assert_eq!(snap.state, TaskState::Failed);
        assert_eq!(snap.error.as_deref(), Some("boom"));
    }

    #[test]
    fn cancel_missing_id_returns_false() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        assert!(!q.cancel("ghost", &bus));
    }

    #[test]
    fn drop_terminal_removes_completed_task() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Upload,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.set_state("t1", TaskState::Completed, &bus);
        assert!(q.drop_terminal("t1"));
        assert!(q.snapshot("t1").is_none());
        assert_eq!(q.count(), 0);
    }

    #[test]
    fn drop_terminal_refuses_running_task() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        q.enqueue(
            "t1".into(),
            TaskKind::Upload,
            "s1".into(),
            "/r".into(),
            "/l".into(),
            0,
            &bus,
        );
        q.set_state("t1", TaskState::Running, &bus);
        assert!(!q.drop_terminal("t1"));
        assert_eq!(q.count(), 1);
    }

    #[test]
    fn snapshot_all_preserves_insertion_order() {
        let bus = EventBus::new();
        let q = TransferQueue::new();
        for n in 0..5 {
            q.enqueue(
                format!("t{n}"),
                TaskKind::Download,
                "s1".into(),
                "/r".into(),
                "/l".into(),
                0,
                &bus,
            );
        }
        let ids: Vec<String> = q.snapshot_all().into_iter().map(|s| s.id).collect();
        assert_eq!(ids, vec!["t0", "t1", "t2", "t3", "t4"]);
    }
}
