//! Port forward registry + listener / accept-loop driver.
//!
//! Owns the canonical state of every active forwarding rule:
//! kind (`Local` / `Remote` / `Dynamic`), bind endpoint, target,
//! current status (`Idle` / `Listening` / `Error`). The russh
//! `direct-tcpip` / `tcpip-forward` primitives live in
//! `lfs_core::ssh`; this module brings the listener-runtime
//! lifecycle next to them.
//!
//! [`driver`] carries the accept-loop + bidirectional pump
//! generic over a [`driver::ChannelFactory`] — production wires
//! the factory to `Session::open_direct_tcpip`; tests inject
//! a duplex echo for self-contained coverage.

pub mod driver;

use std::collections::HashMap;
use std::sync::Mutex;

use crate::bus::{Event, EventBus};

/// Stable identifier for a forwarding rule. Re-uses the rule's
/// DB id so the same string flows between persistence + actor.
pub type RuleId = String;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleKind {
    /// `-L bind_host:bind_port:remote_host:remote_port`.
    Local,
    /// `-R bind_host:bind_port:remote_host:remote_port`.
    Remote,
    /// `-D bind_host:bind_port` — SOCKS5 dynamic forward.
    Dynamic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleStatus {
    Idle,
    Listening,
    Error,
}

#[derive(Debug, Clone)]
pub struct RuleSnapshot {
    pub id: RuleId,
    pub session_id: String,
    pub connection_id: Option<crate::connection::ConnId>,
    pub kind: RuleKind,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub status: RuleStatus,
    pub detail: Option<String>,
}

#[derive(Debug)]
pub struct RuleActor {
    pub id: RuleId,
    pub session_id: String,
    pub connection_id: Option<crate::connection::ConnId>,
    pub kind: RuleKind,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub status: RuleStatus,
    pub detail: Option<String>,
}

impl RuleActor {
    pub fn snapshot(&self) -> RuleSnapshot {
        RuleSnapshot {
            id: self.id.clone(),
            session_id: self.session_id.clone(),
            connection_id: self.connection_id.clone(),
            kind: self.kind,
            bind_host: self.bind_host.clone(),
            bind_port: self.bind_port,
            remote_host: self.remote_host.clone(),
            remote_port: self.remote_port,
            status: self.status,
            detail: self.detail.clone(),
        }
    }
}

/// Process-singleton port-forward registry. Owned by `AppState`.
pub struct PortForwardRegistry {
    inner: Mutex<RegistryInner>,
    listeners: Mutex<HashMap<RuleId, driver::ListenerHandle>>,
    remote_forwards: Mutex<HashMap<RuleId, driver::RemoteForwardHandle>>,
}

struct RegistryInner {
    by_id: HashMap<RuleId, RuleActor>,
}

impl PortForwardRegistry {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(RegistryInner {
                by_id: HashMap::new(),
            }),
            listeners: Mutex::new(HashMap::new()),
            remote_forwards: Mutex::new(HashMap::new()),
        }
    }

    /// Park a Rust-driven `-R` remote-forward handle alongside the
    /// rule row. Replaces any prior handle for the same id (the
    /// previous handle drops, which aborts its dispatcher task and
    /// withdraws the server-side listener).
    pub fn store_remote_forward(&self, id: &str, handle: driver::RemoteForwardHandle) {
        self.remote_forwards
            .lock()
            .expect("port forward remote_forwards mutex poisoned")
            .insert(id.to_string(), handle);
    }

    /// Drop the stored `-R` handle so the inbound bridge task aborts
    /// and the server-side listener is withdrawn. Idempotent on a
    /// missing id. Returns `true` when a handle was actually stopped.
    pub fn stop_remote_forward(&self, id: &str) -> bool {
        self.remote_forwards
            .lock()
            .expect("port forward remote_forwards mutex poisoned")
            .remove(id)
            .is_some()
    }

    /// Park the listener handle alongside the rule row so a
    /// subsequent stop call can abort it. Replaces any prior
    /// handle for the same id (the previous handle drops, which
    /// aborts its task).
    pub fn store_listener(&self, id: &str, handle: driver::ListenerHandle) {
        self.listeners
            .lock()
            .expect("port forward listeners mutex poisoned")
            .insert(id.to_string(), handle);
    }

    /// Abort + remove the stored listener. Idempotent on a
    /// missing id. Returns the bound port the listener was
    /// running on (useful for diagnostic logs); `None` when no
    /// handle was tracked.
    pub fn stop_listener(&self, id: &str) -> Option<std::net::SocketAddr> {
        let removed = self
            .listeners
            .lock()
            .expect("port forward listeners mutex poisoned")
            .remove(id);
        removed.map(|h| {
            let addr = h.bound_addr();
            drop(h); // drops the JoinHandle → aborts the task
            addr
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner
            .lock()
            .expect("port forward registry mutex poisoned")
    }

    /// Register a rule actor + emit `PortForwardRegistered`. The
    /// listener-accept driver lands in the next 5.2 commit;
    /// today the row carries `Idle` until something flips it.
    #[allow(clippy::too_many_arguments)]
    pub fn register(
        &self,
        id: RuleId,
        session_id: String,
        connection_id: Option<crate::connection::ConnId>,
        kind: RuleKind,
        bind_host: String,
        bind_port: i64,
        remote_host: String,
        remote_port: i64,
        bus: &EventBus,
    ) -> RuleSnapshot {
        let actor = RuleActor {
            id: id.clone(),
            session_id,
            connection_id,
            kind,
            bind_host,
            bind_port,
            remote_host,
            remote_port,
            status: RuleStatus::Idle,
            detail: None,
        };
        let snap = actor.snapshot();
        {
            let mut g = self.lock();
            g.by_id.insert(id.clone(), actor);
        }
        bus.publish(Event::PortForwardRegistered { id });
        snap
    }

    /// Update a rule's status. Emits `PortForwardStatus` for
    /// subscribed view-models.
    pub fn set_status(&self, id: &str, status: RuleStatus, detail: Option<String>, bus: &EventBus) {
        let changed = {
            let mut g = self.lock();
            let Some(actor) = g.by_id.get_mut(id) else {
                return;
            };
            if actor.status == status && actor.detail == detail {
                return;
            }
            actor.status = status;
            actor.detail = detail.clone();
            true
        };
        if changed {
            bus.publish(Event::PortForwardStatus {
                id: id.to_string(),
                status,
                detail,
            });
        }
    }

    /// Tear down a rule. Emits `PortForwardRemoved`.
    pub fn remove(&self, id: &str, bus: &EventBus) {
        let removed = {
            let mut g = self.lock();
            g.by_id.remove(id)
        };
        if removed.is_some() {
            bus.publish(Event::PortForwardRemoved { id: id.to_string() });
        }
    }

    pub fn snapshot(&self, id: &str) -> Option<RuleSnapshot> {
        self.lock().by_id.get(id).map(|a| a.snapshot())
    }

    pub fn count(&self) -> usize {
        self.lock().by_id.len()
    }
}

impl Default for PortForwardRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_status_remove_round_trip() {
        let bus = EventBus::new();
        let reg = PortForwardRegistry::new();
        reg.register(
            "r1".into(),
            "s1".into(),
            None,
            RuleKind::Local,
            "127.0.0.1".into(),
            8080,
            "remote".into(),
            80,
            &bus,
        );
        reg.set_status("r1", RuleStatus::Listening, None, &bus);
        assert_eq!(reg.snapshot("r1").unwrap().status, RuleStatus::Listening);
        reg.remove("r1", &bus);
        assert_eq!(reg.count(), 0);
    }
}
