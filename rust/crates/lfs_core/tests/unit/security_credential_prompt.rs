/// Unit tests extracted from security/credential_prompt.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn submit_response_carries_secret_and_remember_flag() {
    let reg = PromptRegistry::new();
    let rx = reg.register("p1".into());
    assert!(reg.resolve(
        "p1",
        CredentialResponse::Submit {
            secret: vec![0xAA; 16],
            remember_for_session: true,
        }
    ));
    match rx.await.unwrap() {
        CredentialResponse::Submit {
            secret,
            remember_for_session,
        } => {
            assert_eq!(secret, vec![0xAA; 16]);
            assert!(remember_for_session);
        }
        other => panic!("expected Submit, got {other:?}"),
    }
}

#[tokio::test]
async fn cancel_response_propagates_terminal_outcome() {
    let reg = PromptRegistry::new();
    let rx = reg.register("p2".into());
    assert!(reg.resolve("p2", CredentialResponse::Cancel));
    assert_eq!(rx.await.unwrap(), CredentialResponse::Cancel);
}

#[test]
fn resolve_unknown_prompt_id_is_noop() {
    let reg = PromptRegistry::new();
    assert!(!reg.resolve("ghost", CredentialResponse::Cancel));
}

#[test]
fn cancel_drops_without_resolving() {
    let reg = PromptRegistry::new();
    let _rx = reg.register("p3".into());
    assert_eq!(reg.pending_count(), 1);
    reg.cancel("p3");
    assert_eq!(reg.pending_count(), 0);
}

#[test]
fn prompt_kind_round_trips_through_wire_name() {
    for kind in [
        CredentialPromptKind::Password,
        CredentialPromptKind::Passphrase,
    ] {
        assert_eq!(
            CredentialPromptKind::from_wire_name(kind.wire_name()),
            Some(kind),
        );
    }
    assert_eq!(CredentialPromptKind::from_wire_name("unknown"), None);
}
