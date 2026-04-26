//! Session recorder — Phase 5.4 scaffolding.
//!
//! Owns the canonical ring buffer + file IO state for active
//! recordings. Per-frame AES-GCM crypto already runs Rust-side
//! (`crypto::aes_gcm_encrypt_raw`); this module brings the buffer
//! lifecycle next to the encrypt step so a recording's state lives
//! in one place rather than half on each side of the FRB boundary.
//!
//! # Scaffolding stage
//!
//! Today the registry exposes only the actor-creation /
//! teardown surface. The frame-write driver lands in the next
//! 5.4 commit alongside the Dart-side `SessionRecorder` swap.
//! Scaffolding here so the bus + FRB enums settle before the
//! consumer port begins.

use std::collections::HashMap;
use std::sync::Mutex;

use crate::bus::{Event, EventBus};

/// Stable identifier for an active recording. The Dart side
/// allocates this off `Uuid().v4()` so the same string flows
/// through Riverpod ownership before the Rust side has finished
/// opening the underlying file.
pub type RecorderId = String;

/// What kind of frame the recorder is writing — terminal output
/// (stdout / stderr) or terminal input (user keystrokes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordDirection {
    Output,
    Input,
}

/// Per-recording metadata — what the FRB layer hands over to a
/// late subscriber as the initial state.
#[derive(Debug, Clone)]
pub struct RecorderSnapshot {
    pub id: RecorderId,
    pub session_id: String,
    pub path: String,
    pub bytes_written: u64,
    pub encrypted: bool,
}

#[derive(Debug)]
pub struct RecorderActor {
    pub id: RecorderId,
    pub session_id: String,
    pub path: String,
    pub bytes_written: u64,
    pub encrypted: bool,
}

impl RecorderActor {
    pub fn new(id: RecorderId, session_id: String, path: String, encrypted: bool) -> Self {
        Self {
            id,
            session_id,
            path,
            bytes_written: 0,
            encrypted,
        }
    }

    pub fn snapshot(&self) -> RecorderSnapshot {
        RecorderSnapshot {
            id: self.id.clone(),
            session_id: self.session_id.clone(),
            path: self.path.clone(),
            bytes_written: self.bytes_written,
            encrypted: self.encrypted,
        }
    }
}

/// Process-singleton registry. Owned by `AppState`. The full
/// frame-write driver loop lands in the next 5.4 commit; today
/// the registry only manages actor creation + removal so the
/// FRB surface stabilises ahead of the consumer port.
pub struct RecorderRegistry {
    inner: Mutex<RegistryInner>,
}

struct RegistryInner {
    by_id: HashMap<RecorderId, RecorderActor>,
}

impl RecorderRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
            }),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner.lock().expect("recorder registry mutex poisoned")
    }

    /// Register a fresh recording actor. Emits `RecorderStarted`
    /// for any subscribed view. Idempotent on repeated id —
    /// later registers replace the row.
    pub fn register(
        &self,
        id: RecorderId,
        session_id: String,
        path: String,
        encrypted: bool,
        bus: &EventBus,
    ) -> RecorderSnapshot {
        let actor = RecorderActor::new(id.clone(), session_id, path, encrypted);
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::RecorderStarted {
            id,
            path: snap.path.clone(),
        });
        snap
    }

    /// Tear down a recording actor. Idempotent on a missing id.
    /// Emits `RecorderStopped` so subscribers can refresh their
    /// recording list.
    pub fn close(&self, id: &str, bus: &EventBus) {
        let removed = {
            let mut g = self.lock();
            g.by_id.remove(id)
        };
        if removed.is_some() {
            bus.publish(Event::RecorderStopped { id: id.to_string() });
        }
    }

    pub fn snapshot(&self, id: &str) -> Option<RecorderSnapshot> {
        self.lock().by_id.get(id).map(|a| a.snapshot())
    }

    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }

    /// Bump the byte counter for an actor — called by the
    /// frame-write driver once it lands. Today exposed as a thin
    /// API so tests can verify the counter / event fan-out
    /// without the file IO.
    pub fn record_chunk(&self, id: &str, bytes: u64, bus: &EventBus) {
        let new_total = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            actor.bytes_written = actor.bytes_written.saturating_add(bytes);
            actor.bytes_written
        };
        bus.publish(Event::RecorderBytesWritten {
            id: id.to_string(),
            total_bytes: new_total,
        });
    }
}

impl Default for RecorderRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_and_close() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe();
        let reg = RecorderRegistry::new();
        let snap = reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
        assert_eq!(snap.id, "r1");
        assert_eq!(reg.count(), 1);
        // Drain the bus event sent during register.
        let _ = rx.try_recv();
        reg.close("r1", &bus);
        assert_eq!(reg.count(), 0);
    }

    #[test]
    fn record_chunk_bumps_bytes() {
        let bus = EventBus::new();
        let reg = RecorderRegistry::new();
        reg.register("r1".into(), "s1".into(), "/tmp/r.cast".into(), false, &bus);
        reg.record_chunk("r1", 42, &bus);
        assert_eq!(reg.snapshot("r1").unwrap().bytes_written, 42);
    }
}
