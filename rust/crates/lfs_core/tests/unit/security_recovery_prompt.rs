/// Unit tests extracted from security/recovery_prompt.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn response_wire_name_round_trips() {
    for r in [
        RecoveryPromptResponse::Reset,
        RecoveryPromptResponse::Quit,
        RecoveryPromptResponse::TryOtherTier,
    ] {
        assert_eq!(
            RecoveryPromptResponse::from_wire_name(r.wire_name()),
            Some(r)
        );
    }
}

#[test]
fn response_from_wire_name_unknown_yields_none() {
    assert_eq!(RecoveryPromptResponse::from_wire_name(""), None);
    assert_eq!(RecoveryPromptResponse::from_wire_name("RESET"), None);
    assert_eq!(RecoveryPromptResponse::from_wire_name("Unknown"), None);
}

#[test]
fn kind_wire_name_is_stable() {
    assert_eq!(
        RecoveryPromptKind::DbCorruptDetected { reason: "x".into() }.wire_name(),
        "dbCorruptDetected"
    );
    assert_eq!(
        RecoveryPromptKind::VaultStateMissing {
            tier_label: "T1".into()
        }
        .wire_name(),
        "vaultStateMissing"
    );
    assert_eq!(
        RecoveryPromptKind::LegacyStateFound {
            config_version_on_disk: 3,
            orphan_artefacts: true,
        }
        .wire_name(),
        "legacyStateFound"
    );
}

#[tokio::test]
async fn register_and_resolve_round_trips_wire_string() {
    let reg = PromptRegistry::new();
    let rx = reg.register("p1".into());
    assert!(reg.resolve("p1", RecoveryPromptResponse::Reset.wire_name().into()));
    let wire = rx.await.unwrap();
    assert_eq!(
        RecoveryPromptResponse::from_wire_name(&wire),
        Some(RecoveryPromptResponse::Reset)
    );
}

#[test]
fn cancel_drops_without_resolving() {
    let reg = PromptRegistry::new();
    let _rx = reg.register("p".into());
    reg.cancel("p");
    assert_eq!(reg.pending_count(), 0);
    assert!(!reg.resolve("p", "reset".into()));
}

#[test]
fn resolve_unknown_id_is_noop() {
    let reg = PromptRegistry::new();
    assert!(!reg.resolve("ghost", "reset".into()));
}
