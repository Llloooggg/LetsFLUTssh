/// Unit tests extracted from ssh_agent/endpoint.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn endpoint_lock_blocks_request_identities() {
    let mut ep = Endpoint::default();
    let _ = ep.lock(String::new()).await;
    let ids = ep.request_identities().await.unwrap();
    assert!(ids.is_empty());
}

#[tokio::test]
async fn endpoint_unlock_restores_listing() {
    // The DB is not initialised in this unit-test slice — we
    // expect `request_identities` to surface an error rather
    // than panic. `unlock` should at least flip the flag back.
    let mut ep = Endpoint::default();
    let _ = ep.lock(String::new()).await;
    assert!(ep.request_identities().await.unwrap().is_empty());
    let _ = ep.unlock(String::new()).await;
    // After unlock the listing path tries to reach the DB.
    // Without a DB the path returns `Other`; assert it surfaces
    // an error rather than producing a phantom listing.
    let result = ep.request_identities().await;
    assert!(result.is_err());
}

#[tokio::test]
async fn endpoint_remove_all_identities_is_refused() {
    // The agent protocol's REMOVE_ALL verb takes no payload —
    // gives us a clean shape to assert the refusal contract on
    // without needing to construct an `AddIdentity` (which
    // wraps a real `KeypairData`).
    let mut ep = Endpoint::default();
    let err = ep.remove_all_identities().await.unwrap_err();
    assert!(matches!(err, AgentError::Other(_)));
}

#[tokio::test]
async fn endpoint_extension_accepts_session_bind() {
    let mut ep = Endpoint::default();
    let ext = Extension {
        name: "session-bind@openssh.com".into(),
        details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
    };
    let res = ep.extension(ext).await;
    assert!(res.is_ok());
}

#[tokio::test]
async fn endpoint_extension_refuses_unknown() {
    let mut ep = Endpoint::default();
    let ext = Extension {
        name: "evil.example".into(),
        details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
    };
    let err = ep.extension(ext).await.unwrap_err();
    assert!(matches!(err, AgentError::ExtensionFailure));
}

#[test]
fn status_with_no_endpoint_reports_not_running() {
    let s = status();
    assert!(!s.running || s.socket_path.is_some());
}

/// Standalone `restrict-destination-v00@openssh.com` extension
/// request must refuse with `ExtensionFailure` so the external
/// agent-forwarding bastion knows the destination chain is NOT
/// enforced rather than thinking it has been pinned.
#[tokio::test]
async fn endpoint_extension_refuses_restrict_destination_v00() {
    let mut ep = Endpoint::default();
    let ext = Extension {
        name: "restrict-destination-v00@openssh.com".into(),
        details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
    };
    let err = ep.extension(ext).await.unwrap_err();
    assert!(matches!(err, AgentError::ExtensionFailure));
}

/// Same contract for the `-v01` revision — OpenSSH 9.x reserves
/// the future-shape name, and we refuse both with the same
/// rationale.
#[tokio::test]
async fn endpoint_extension_refuses_restrict_destination_v01() {
    let mut ep = Endpoint::default();
    let ext = Extension {
        name: "restrict-destination-v01@openssh.com".into(),
        details: ssh_agent_lib::proto::Unparsed::from(Vec::<u8>::new()),
    };
    let err = ep.extension(ext).await.unwrap_err();
    assert!(matches!(err, AgentError::ExtensionFailure));
}

/// ADD_IDENTITY_CONSTRAINED carrying a destination-restriction
/// constraint surfaces the specific "agent does not enforce"
/// refusal rather than the generic "cannot add keys" one. The
/// wire-level response is `SSH_AGENT_FAILURE` either way, but the
/// log line and any future Dart-side handler can route on the
/// specific message.
#[tokio::test]
async fn endpoint_add_identity_constrained_rejects_destination_constraint() {
    use ssh_agent_lib::proto::{KeyConstraint, PrivateCredential, Unparsed};
    use ssh_key::private::{Ed25519Keypair, KeypairData};
    let mut ep = Endpoint::default();
    let keypair = Ed25519Keypair::random(&mut ssh_key::rand_core::OsRng);
    let identity = AddIdentity {
        credential: PrivateCredential::Key {
            privkey: KeypairData::Ed25519(keypair),
            comment: "test".into(),
        },
    };
    let constrained = AddIdentityConstrained {
        identity,
        constraints: vec![KeyConstraint::Extension(Extension {
            name: "restrict-destination-v00@openssh.com".into(),
            details: Unparsed::from(Vec::<u8>::new()),
        })],
    };
    let err = ep.add_identity_constrained(constrained).await.unwrap_err();
    match err {
        AgentError::Other(boxed) => {
            let s = boxed.to_string();
            assert!(
                s.contains("destination constraints"),
                "expected destination-constraint message, got {s}"
            );
        }
        other => panic!("expected AgentError::Other, got {other:?}"),
    }
}

/// ADD_IDENTITY_CONSTRAINED WITHOUT a destination constraint
/// still rejects, but with the generic "cannot add keys" message.
/// Distinguishing the two messages is the M14 contract: silent
/// acceptance is the bug; both refusals are correct, the
/// destination-specific arm just gives a better hint.
#[tokio::test]
async fn endpoint_add_identity_constrained_without_destination_uses_generic_refusal() {
    use ssh_agent_lib::proto::{KeyConstraint, PrivateCredential};
    use ssh_key::private::{Ed25519Keypair, KeypairData};
    let mut ep = Endpoint::default();
    let keypair = Ed25519Keypair::random(&mut ssh_key::rand_core::OsRng);
    let identity = AddIdentity {
        credential: PrivateCredential::Key {
            privkey: KeypairData::Ed25519(keypair),
            comment: "test".into(),
        },
    };
    let constrained = AddIdentityConstrained {
        identity,
        constraints: vec![KeyConstraint::Lifetime(3600)],
    };
    let err = ep.add_identity_constrained(constrained).await.unwrap_err();
    match err {
        AgentError::Other(boxed) => {
            let s = boxed.to_string();
            assert!(
                s.contains("external clients cannot add"),
                "expected generic refusal, got {s}"
            );
        }
        other => panic!("expected AgentError::Other, got {other:?}"),
    }
}

/// Detector helper handles the v01 alias too — the alias is the
/// load-bearing branch in `first_destination_constraint_name` we
/// rely on for any future OpenSSH bump.
#[test]
fn destination_constraint_detector_recognises_v01_alias() {
    use ssh_agent_lib::proto::{KeyConstraint, Unparsed};
    let constraints = vec![KeyConstraint::Extension(Extension {
        name: "restrict-destination-v01@openssh.com".into(),
        details: Unparsed::from(Vec::<u8>::new()),
    })];
    let name = super::first_destination_constraint_name(&constraints);
    assert_eq!(name, Some("restrict-destination-v01@openssh.com"));
}

/// Detector helper returns `None` when no destination constraint
/// is present, even when other extension constraints are.
#[test]
fn destination_constraint_detector_ignores_other_extensions() {
    use ssh_agent_lib::proto::{KeyConstraint, Unparsed};
    let constraints = vec![
        KeyConstraint::Lifetime(3600),
        KeyConstraint::Confirm,
        KeyConstraint::Extension(Extension {
            name: "some-other-extension@example.com".into(),
            details: Unparsed::from(Vec::<u8>::new()),
        }),
    ];
    let name = super::first_destination_constraint_name(&constraints);
    assert_eq!(name, None);
}
