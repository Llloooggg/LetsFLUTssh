/// Unit tests extracted from portforward/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
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
