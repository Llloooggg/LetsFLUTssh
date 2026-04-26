//! Connection lifecycle — Phase 5.1 actor.
//!
//! Owns the canonical state for every active SSH connection. Dart
//! drives operations by dispatching `ConnectionCommand`s through the
//! bus; widgets observe `ConnectionEvent`s via per-screen view
//! streams. The Dart-side `Connection` class becomes a thin view
//! that mirrors the Rust state — no FSM machinery left in the UI
//! layer.
//!
//! # State model
//!
//! Each `ConnectionActor` carries its own state machine
//! (`Disconnected → Connecting → Connected → Disconnected`) plus a
//! generation counter that protects against stale reconnect results
//! overwriting newer ones. The actor also holds the progress-step
//! history so a subscriber that joins late can replay every step
//! through a snapshot command.
//!
//! Bastion refs (`bastion_id`) point at another actor in the same
//! registry; teardown of the parent cascades into the bastion when
//! it's flagged `internal`. The internal flag also gates the user-
//! visible connection list so the workspace UI never paints a tab
//! for a hop the user did not explicitly open.
//!
//! # Scaffolding stage
//!
//! This module ships the types + registry surface. The actual
//! `connect` / `disconnect` / `reconnect` driver loops are wired in
//! the next 5.1 commit — the present commit lays the rails so the
//! Dart side can flip its `Connection` class to view-mode without
//! waiting for the full state-machine port.

use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::Mutex;

/// Stable identifier for an active connection. Allocated by the
/// registry on `ConnectAsync`; used as the key in every subsequent
/// command + event so subscribers can demux per-connection traffic.
pub type ConnId = String;

/// Mirrors the Dart-era `SSHConnectionState` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
}

/// Mirrors `ConnectionPhase` in Dart `connection_step.dart`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPhase {
    SocketConnect,
    HostKeyVerify,
    Authenticate,
    OpenChannel,
}

/// Mirrors `StepStatus` in Dart `connection_step.dart`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StepStatus {
    InProgress,
    Success,
    Failed,
}

/// Single progress step. Mirrors Dart `ConnectionStep`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgressStep {
    pub phase: ConnectionPhase,
    pub status: StepStatus,
    pub detail: Option<String>,
}

/// Snapshot view of an actor — what the FRB layer hands over to a
/// late subscriber as the initial state, and what a `Snapshot`
/// command returns. Designed to carry no plaintext: credentials
/// stay in the SecretStore, bastion linkage is by id only.
#[derive(Debug, Clone)]
pub struct ConnectionSnapshot {
    pub id: ConnId,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<ConnId>,
    pub internal: bool,
    pub state: ConnectionState,
    pub error: Option<String>,
    pub progress: Vec<ProgressStep>,
}

/// Per-connection actor. The registry owns these inside an
/// `Arc<Mutex<...>>` so commands serialise per-id while the Tokio
/// runtime drives the actual transport work concurrently.
///
/// The `transport` slot will hold the live russh handle once the
/// connect driver lands in the next 5.1 commit; today the actor
/// only carries the state-machine surface.
#[derive(Debug)]
pub struct ConnectionActor {
    pub id: ConnId,
    pub label: String,
    pub session_id: Option<String>,
    pub bastion_id: Option<ConnId>,
    pub internal: bool,
    pub state: ConnectionState,
    pub generation: u64,
    pub error: Option<String>,
    pub progress: Vec<ProgressStep>,
}

impl ConnectionActor {
    pub fn new(
        id: ConnId,
        label: String,
        session_id: Option<String>,
        bastion_id: Option<ConnId>,
        internal: bool,
    ) -> Self {
        Self {
            id,
            label,
            session_id,
            bastion_id,
            internal,
            state: ConnectionState::Disconnected,
            generation: 0,
            error: None,
            progress: Vec::new(),
        }
    }

    pub fn snapshot(&self) -> ConnectionSnapshot {
        ConnectionSnapshot {
            id: self.id.clone(),
            label: self.label.clone(),
            session_id: self.session_id.clone(),
            bastion_id: self.bastion_id.clone(),
            internal: self.internal,
            state: self.state,
            error: self.error.clone(),
            progress: self.progress.clone(),
        }
    }
}

/// Process-singleton registry of active connections. Guards the
/// id-to-actor map under one lock; state mutations stay short-
/// lived (one transition then one bus event per call) so global
/// mutex contention is bounded.
///
/// Long-running transport work (connect handshake, keep-alive)
/// runs outside the lock — the driver loops clone the `Arc` and
/// re-acquire the lock only for state-change writes.
pub struct ConnectionRegistry {
    inner: Mutex<RegistryInner>,
}

struct RegistryInner {
    by_id: HashMap<ConnId, Arc<Mutex<ConnectionActor>>>,
    /// Live insertion order — preserved for the Dart-side workspace
    /// view that paints connections in the order the user opened
    /// them.
    order: Vec<ConnId>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
                order: Vec::new(),
            }),
        }
    }

    /// Insert a freshly-built actor. Returns its handle so the
    /// caller can spin up the connect driver against the same
    /// `Arc<Mutex<ConnectionActor>>` the registry now holds.
    pub async fn insert(&self, actor: ConnectionActor) -> Arc<Mutex<ConnectionActor>> {
        let id = actor.id.clone();
        let handle = Arc::new(Mutex::new(actor));
        let mut g = self.inner.lock().await;
        g.by_id.insert(id.clone(), handle.clone());
        g.order.push(id);
        handle
    }

    pub async fn get(&self, id: &str) -> Option<Arc<Mutex<ConnectionActor>>> {
        let g = self.inner.lock().await;
        g.by_id.get(id).cloned()
    }

    pub async fn remove(&self, id: &str) -> Option<Arc<Mutex<ConnectionActor>>> {
        let mut g = self.inner.lock().await;
        let handle = g.by_id.remove(id);
        if handle.is_some() {
            g.order.retain(|x| x != id);
        }
        handle
    }

    /// Snapshot every actor (in insertion order) for a workspace
    /// view rebuild. Cloning each snapshot under the lock keeps the
    /// caller off any per-actor mutex; the snapshot itself is
    /// plain-data so subsequent reads can outlive any state
    /// transition.
    pub async fn snapshot_all(&self) -> Vec<ConnectionSnapshot> {
        let g = self.inner.lock().await;
        let mut out = Vec::with_capacity(g.order.len());
        for id in &g.order {
            if let Some(handle) = g.by_id.get(id) {
                let actor = handle.lock().await;
                out.push(actor.snapshot());
            }
        }
        out
    }

    /// Live count — diagnostic only.
    pub async fn count(&self) -> usize {
        self.inner.lock().await.by_id.len()
    }
}

impl Default for ConnectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn insert_and_snapshot() {
        let reg = ConnectionRegistry::new();
        let actor =
            ConnectionActor::new("c1".into(), "Label".into(), Some("s1".into()), None, false);
        reg.insert(actor).await;
        let snap = reg.snapshot_all().await;
        assert_eq!(snap.len(), 1);
        assert_eq!(snap[0].id, "c1");
        assert_eq!(snap[0].state, ConnectionState::Disconnected);
    }

    #[tokio::test]
    async fn remove_drops_actor() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new("c1".into(), "L".into(), None, None, false);
        reg.insert(actor).await;
        assert_eq!(reg.count().await, 1);
        reg.remove("c1").await;
        assert_eq!(reg.count().await, 0);
        assert!(reg.snapshot_all().await.is_empty());
    }

    #[tokio::test]
    async fn snapshot_carries_progress() {
        let reg = ConnectionRegistry::new();
        let actor = ConnectionActor::new("c1".into(), "L".into(), None, None, false);
        let handle = reg.insert(actor).await;
        {
            let mut a = handle.lock().await;
            a.progress.push(ProgressStep {
                phase: ConnectionPhase::SocketConnect,
                status: StepStatus::Success,
                detail: None,
            });
        }
        let snap = reg.snapshot_all().await;
        assert_eq!(snap[0].progress.len(), 1);
        assert_eq!(snap[0].progress[0].phase, ConnectionPhase::SocketConnect);
    }
}
