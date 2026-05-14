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

    #[test]
    fn rule_kind_wire_round_trip_every_variant() {
        // Byte-identity guard — these strings round-trip the DB
        // column `port_forward_rules.kind`, so a typo would brick
        // every saved row.
        for v in [RuleKind::Local, RuleKind::Remote, RuleKind::Dynamic] {
            assert_eq!(RuleKind::from_wire_name(v.wire_name()), v);
        }
    }

    #[test]
    fn rule_kind_unknown_wire_falls_back_to_local() {
        assert_eq!(RuleKind::from_wire_name(""), RuleKind::Local);
        assert_eq!(RuleKind::from_wire_name("does-not-exist"), RuleKind::Local);
    }

    #[test]
    fn rule_kind_wire_names_match_dart_enum_dot_name() {
        assert_eq!(RuleKind::Local.wire_name(), "local");
        assert_eq!(RuleKind::Remote.wire_name(), "remote");
        assert_eq!(RuleKind::Dynamic.wire_name(), "dynamic");
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

impl RuleKind {
    /// Wire value persisted in the `port_forward_rules.kind` column
    /// and the canonical-JSON `kind` key. Byte-identical to the
    /// matching Dart enum's `.name` getter on the FRB-generated
    /// mirror so the DB column round-trips across the boundary
    /// without a Dart-side parser.
    #[must_use]
    pub fn wire_name(self) -> &'static str {
        match self {
            RuleKind::Local => "local",
            RuleKind::Remote => "remote",
            RuleKind::Dynamic => "dynamic",
        }
    }

    /// Parse a wire value into the typed variant. Unknown / empty
    /// strings fall back to [`RuleKind::Local`] so a future variant
    /// added in a newer build can never brick a legacy stored row —
    /// it simply renders as `local` until the build catches up. The
    /// previous Dart-side `PortForwardKindExt.fromWireName` followed
    /// the same fallback rule.
    #[must_use]
    pub fn from_wire_name(s: &str) -> Self {
        match s {
            "remote" => RuleKind::Remote,
            "dynamic" => RuleKind::Dynamic,
            _ => RuleKind::Local,
        }
    }
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

/// App-side port-forward rule shape — the canonical JSON the FRB
/// codec helpers (`port_forward_rule_to_json_typed` /
/// `port_forward_rule_from_json_typed`) round-trip. Mirrors the
/// Dart `PortForwardRule` struct (no `session_id`; `created_at` is
/// an ISO-8601 UTC string the way Dart's
/// `DateTime.toIso8601String()` emits when the source is UTC).
///
/// Distinct from [`db::port_forwards::PortForwardRuleRow`] (the
/// DB-row shape, which carries `session_id` + `created_at_ms` and
/// the sync `updated_at_ms` stamp). The DB-row codec lives in
/// `archive::compose::port_forward_row_to_value`; this one is the
/// Dart-side rule's canonical wire that legacy code emitted from
/// `PortForwardRule.toJson` and parsed in `.fromJson`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppRule {
    pub id: String,
    pub kind: RuleKind,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub description: String,
    pub enabled: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
}

/// Serialise an [`AppRule`] into the canonical JSON string the
/// Dart-side rule grammar expects. Field order + key names match
/// what `PortForwardRule.toJson` historically emitted so any
/// on-disk / clipboard artefact written with the old codec still
/// parses byte-identically through `from_json_string`.
///
/// `description` is omitted when empty (mirrors the prior Dart
/// codec's `if (description.isNotEmpty)` guard so a freshly built
/// rule round-trips through the typed FRB shim without growing a
/// spurious empty field).
#[must_use]
pub fn rule_to_json_string(rule: &AppRule) -> String {
    let mut obj = serde_json::Map::new();
    obj.insert("id".into(), serde_json::json!(rule.id));
    obj.insert("kind".into(), serde_json::json!(rule.kind.wire_name()));
    obj.insert("bind_host".into(), serde_json::json!(rule.bind_host));
    obj.insert("bind_port".into(), serde_json::json!(rule.bind_port));
    obj.insert("remote_host".into(), serde_json::json!(rule.remote_host));
    obj.insert("remote_port".into(), serde_json::json!(rule.remote_port));
    if !rule.description.is_empty() {
        obj.insert("description".into(), serde_json::json!(rule.description));
    }
    obj.insert("enabled".into(), serde_json::json!(rule.enabled));
    obj.insert("sort_order".into(), serde_json::json!(rule.sort_order));
    obj.insert(
        "created_at".into(),
        serde_json::json!(crate::archive::iso8601::format_iso8601_utc(
            rule.created_at_ms
        )),
    );
    serde_json::Value::Object(obj).to_string()
}

/// Parse a canonical-JSON rule string into the typed [`AppRule`].
///
/// Tolerant of missing / unknown fields the same way the previous
/// Dart codec was: a missing `kind` → `Local`; missing `bind_host`
/// → `127.0.0.1`; missing numeric fields → 0; missing `enabled`
/// → `true`; missing `created_at` (or unparseable) → "now"
/// (matches `DateTime.tryParse(...) ?? DateTime.now()` semantics
/// the legacy parser shipped). Returns the parser error string for
/// malformed JSON only — a recognised shape always succeeds.
pub fn rule_from_json_string(json: &str, now_ms: i64) -> Result<AppRule, String> {
    let v: serde_json::Value = serde_json::from_str(json).map_err(|e| e.to_string())?;
    let obj = v.as_object().ok_or("rule json: top-level not an object")?;
    let s = |key: &str| obj.get(key).and_then(|v| v.as_str()).map(str::to_owned);
    let i = |key: &str| obj.get(key).and_then(serde_json::Value::as_i64);
    let b = |key: &str| obj.get(key).and_then(serde_json::Value::as_bool);
    let kind_wire = s("kind").unwrap_or_default();
    let created_at_ms = match s("created_at") {
        Some(s) if !s.is_empty() => crate::archive::iso8601::parse_iso8601_or_now(&s, now_ms),
        _ => now_ms,
    };
    Ok(AppRule {
        id: s("id").unwrap_or_default(),
        kind: RuleKind::from_wire_name(&kind_wire),
        bind_host: s("bind_host").unwrap_or_else(|| "127.0.0.1".to_owned()),
        bind_port: i("bind_port").unwrap_or(0),
        remote_host: s("remote_host").unwrap_or_default(),
        remote_port: i("remote_port").unwrap_or(0),
        description: s("description").unwrap_or_default(),
        enabled: b("enabled").unwrap_or(true),
        sort_order: i("sort_order").unwrap_or(0),
        created_at_ms,
    })
}

#[cfg(test)]
mod app_rule_codec_tests {
    use super::*;

    fn rule_with_iso_ms(ms: i64) -> AppRule {
        AppRule {
            id: "fixed-id".into(),
            kind: RuleKind::Local,
            bind_host: "127.0.0.1".into(),
            bind_port: 9090,
            remote_host: "svc.local".into(),
            remote_port: 443,
            description: "prod tunnel".into(),
            enabled: false,
            sort_order: 5,
            created_at_ms: ms,
        }
    }

    #[test]
    fn rule_round_trips_through_canonical_json() {
        // 2026-01-02T03:04:05.000Z → ms = 1767322145000
        let original = rule_with_iso_ms(1_767_322_145_000);
        let s = rule_to_json_string(&original);
        let back = rule_from_json_string(&s, 0).expect("parse");
        assert_eq!(back, original);
    }

    #[test]
    fn rule_to_json_omits_empty_description() {
        let r = AppRule {
            description: String::new(),
            ..rule_with_iso_ms(0)
        };
        let s = rule_to_json_string(&r);
        assert!(!s.contains("description"));
    }

    #[test]
    fn rule_from_json_defaults_missing_fields() {
        let s = r#"{"bind_port":22}"#;
        let r = rule_from_json_string(s, 12_345).expect("parse");
        assert_eq!(r.kind, RuleKind::Local);
        assert_eq!(r.bind_host, "127.0.0.1");
        assert!(r.enabled);
        assert_eq!(r.bind_port, 22);
        // Missing created_at → fall back to the supplied `now_ms`.
        assert_eq!(r.created_at_ms, 12_345);
    }

    #[test]
    fn rule_from_json_maps_unknown_kind_to_local() {
        let s = r#"{"bind_port":1,"kind":"who-knows"}"#;
        let r = rule_from_json_string(s, 0).expect("parse");
        assert_eq!(r.kind, RuleKind::Local);
    }

    #[test]
    fn rule_from_json_maps_every_known_kind() {
        for (wire, expected) in [
            ("local", RuleKind::Local),
            ("remote", RuleKind::Remote),
            ("dynamic", RuleKind::Dynamic),
        ] {
            let s = format!(r#"{{"bind_port":1,"kind":"{wire}"}}"#);
            assert_eq!(rule_from_json_string(&s, 0).unwrap().kind, expected);
        }
    }

    #[test]
    fn rule_from_json_rejects_malformed_json() {
        assert!(rule_from_json_string("not json", 0).is_err());
        assert!(rule_from_json_string("[1,2,3]", 0).is_err());
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
