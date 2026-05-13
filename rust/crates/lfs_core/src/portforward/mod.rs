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

/// Why a port-forward rule failed pre-flight validation. Returned
/// from [`validate_rule`] as the discriminator; the Dart caller
/// formats / localises the message. Kept Rust-side so the driver
/// (`start_local` / `start_dynamic` / `start_remote`) and the
/// pre-flight UI / runtime checks share one grammar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleValidationError {
    /// `bind_port` outside `[1, 65535]`.
    BindPortOutOfRange,
    /// `remote_host` is empty for a `Local` / `Remote` rule
    /// (irrelevant for `Dynamic`).
    TargetHostRequired,
    /// `remote_port` outside `[1, 65535]` for a `Local` / `Remote`
    /// rule (irrelevant for `Dynamic`).
    TargetPortOutOfRange,
    /// `bind_host` is empty for every rule kind.
    BindHostRequired,
}

/// Pre-flight check: return `None` when the rule's network params
/// are valid for its kind, else the variant describing the first
/// rejection. Mirror of the prior Dart-side `PortForwardRule.
/// validate` body, lifted so the UI and the runtime share one
/// grammar that does not drift across the FRB boundary.
pub fn validate_rule(
    kind: RuleKind,
    bind_host: &str,
    bind_port: i64,
    remote_host: &str,
    remote_port: i64,
) -> Option<RuleValidationError> {
    if !(1..=65535).contains(&bind_port) {
        return Some(RuleValidationError::BindPortOutOfRange);
    }
    if kind != RuleKind::Dynamic {
        if remote_host.trim().is_empty() {
            return Some(RuleValidationError::TargetHostRequired);
        }
        if !(1..=65535).contains(&remote_port) {
            return Some(RuleValidationError::TargetPortOutOfRange);
        }
    }
    if bind_host.trim().is_empty() {
        return Some(RuleValidationError::BindHostRequired);
    }
    None
}

#[cfg(test)]
mod validate_rule_tests {
    use super::*;

    #[test]
    fn valid_local_rule_returns_none() {
        assert!(validate_rule(RuleKind::Local, "127.0.0.1", 8080, "example.com", 22).is_none());
    }

    #[test]
    fn bind_port_zero_is_out_of_range() {
        let r = validate_rule(RuleKind::Local, "127.0.0.1", 0, "h", 22);
        assert_eq!(r, Some(RuleValidationError::BindPortOutOfRange));
    }

    #[test]
    fn bind_port_above_65535_is_out_of_range() {
        let r = validate_rule(RuleKind::Local, "127.0.0.1", 70000, "h", 22);
        assert_eq!(r, Some(RuleValidationError::BindPortOutOfRange));
    }

    #[test]
    fn empty_target_host_rejected_for_local() {
        let r = validate_rule(RuleKind::Local, "127.0.0.1", 8080, "", 22);
        assert_eq!(r, Some(RuleValidationError::TargetHostRequired));
    }

    #[test]
    fn empty_target_host_accepted_for_dynamic() {
        // Dynamic (SOCKS5) does not name a target host — the
        // SOCKS protocol carries the destination per-connection.
        assert!(validate_rule(RuleKind::Dynamic, "127.0.0.1", 1080, "", 0).is_none());
    }

    #[test]
    fn target_port_out_of_range_rejected_for_local() {
        let r = validate_rule(RuleKind::Local, "127.0.0.1", 8080, "h", 70000);
        assert_eq!(r, Some(RuleValidationError::TargetPortOutOfRange));
    }

    #[test]
    fn empty_bind_host_rejected() {
        let r = validate_rule(RuleKind::Local, "", 8080, "h", 22);
        assert_eq!(r, Some(RuleValidationError::BindHostRequired));
    }
}

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

/// Bundled inputs for [`PortForwardRegistry::register`]. Eight
/// per-rule fields land here so the registration call signature
/// stays under clippy's too-many-arguments threshold.
#[derive(Clone, Debug)]
pub struct RegisterRequest {
    pub id: RuleId,
    pub session_id: String,
    pub connection_id: Option<crate::connection::ConnId>,
    pub kind: RuleKind,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
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
            .unwrap_or_else(|e| e.into_inner())
            .insert(id.to_string(), handle);
    }

    /// Drop the stored `-R` handle so the inbound bridge task aborts
    /// and the server-side listener is withdrawn. Idempotent on a
    /// missing id. Returns `true` when a handle was actually stopped.
    ///
    /// The `Drop`-only path falls back to a detached
    /// `tokio::spawn` for the network-side withdraw, which loses the
    /// runtime-shutdown race in the worst case. Async callers
    /// (the FRB shim chain) prefer [`Self::stop_remote_forward_async`]
    /// so the cleanup actually completes before the FRB future
    /// resolves.
    pub fn stop_remote_forward(&self, id: &str) -> bool {
        self.remote_forwards
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(id)
            .is_some()
    }

    /// Awaitable variant of [`Self::stop_remote_forward`]. Pulls
    /// the handle out of the registry, runs
    /// [`driver::RemoteForwardHandle::teardown`] inline, then
    /// drops the (already torn-down) handle. The `Drop` impl
    /// becomes a no-op for the network-side work — no detached
    /// task left racing the runtime shutdown.
    pub async fn stop_remote_forward_async(&self, id: &str) -> bool {
        let removed = self
            .remote_forwards
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(id);
        match removed {
            Some(mut handle) => {
                handle.teardown().await;
                true
            }
            None => false,
        }
    }

    /// Park the listener handle alongside the rule row so a
    /// subsequent stop call can abort it. Replaces any prior
    /// handle for the same id (the previous handle drops, which
    /// aborts its task).
    pub fn store_listener(&self, id: &str, handle: driver::ListenerHandle) {
        self.listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner())
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
            .unwrap_or_else(|e| e.into_inner())
            .remove(id);
        removed.map(|h| {
            let addr = h.bound_addr();
            drop(h); // drops the JoinHandle → aborts the task
            addr
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, RegistryInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Register a rule actor + emit `PortForwardRegistered`. The
    /// listener-accept driver runs once the row is registered;
    /// the row carries `Idle` until something flips it.
    pub fn register(&self, req: RegisterRequest, bus: &EventBus) -> RuleSnapshot {
        let RegisterRequest {
            id,
            session_id,
            connection_id,
            kind,
            bind_host,
            bind_port,
            remote_host,
            remote_port,
        } = req;
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
            RegisterRequest {
                id: "r1".into(),
                session_id: "s1".into(),
                connection_id: None,
                kind: RuleKind::Local,
                bind_host: "127.0.0.1".into(),
                bind_port: 8080,
                remote_host: "remote".into(),
                remote_port: 80,
            },
            &bus,
        );
        reg.set_status("r1", RuleStatus::Listening, None, &bus);
        assert_eq!(reg.snapshot("r1").unwrap().status, RuleStatus::Listening);
        reg.remove("r1", &bus);
        assert_eq!(reg.count(), 0);
    }
}
