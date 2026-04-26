//! Transfer queue — Phase 5.3 scaffolding.
//!
//! Owns the canonical state for the SFTP transfer queue: per-task
//! status (`Queued / Running / Completed / Failed / Cancelled`),
//! history ring buffer, byte progress. Per-file SFTP work already
//! lives in `lfs_core::sftp`; this module brings the queue +
//! worker pool next to it.
//!
//! # Scaffolding stage
//!
//! Today the registry exposes the actor-creation surface +
//! status / progress mutators so the bus + FRB enums settle.
//! The Tokio worker-pool driver lands in the next 5.3 commit
//! alongside the Dart `TransferManager` swap.

use std::collections::HashMap;
use std::sync::Mutex;

use crate::bus::{Event, EventBus};

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

    /// Set the bytes-done counter. Emits `TransferTaskProgress`.
    pub fn set_progress(&self, id: &str, bytes_done: u64, bus: &EventBus) {
        let bytes_total;
        {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            actor.bytes_done = bytes_done;
            bytes_total = actor.bytes_total;
        }
        bus.publish(Event::TransferTaskProgress {
            id: id.to_string(),
            bytes_done,
            bytes_total,
        });
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
}
