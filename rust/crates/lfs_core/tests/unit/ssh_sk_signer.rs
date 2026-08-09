/// Unit tests extracted from ssh/sk_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn dummy_credential() -> FidoCredential {
    FidoCredential {
        credential_id: b"cred-id".to_vec(),
        application: "ssh:".into(),
        pin: None,
    }
}

#[test]
fn signer_error_send_wraps_via_from() {
    let send = russh::SendError {};
    let wrapped: SkSignerError = send.into();
    assert!(matches!(wrapped, SkSignerError::Send(_)));
}

#[test]
fn signer_error_fido_wraps_via_from() {
    let err = Error::Fido2("nope".into());
    let wrapped: SkSignerError = err.into();
    assert!(matches!(wrapped, SkSignerError::Fido(Error::Fido2(_))));
}

#[test]
fn signer_error_displays_both_arms() {
    let s = format!("{}", SkSignerError::Send(russh::SendError {}));
    assert!(s.starts_with("russh transport"));
    let f = format!("{}", SkSignerError::Fido(Error::Fido2("x".into())));
    assert!(f.contains("fido2 signer"));
}

#[test]
fn signer_error_round_trips_to_core_error() {
    let core: Error = SkSignerError::Fido(Error::AuthFailed("rejected".into())).into();
    assert!(matches!(core, Error::AuthFailed(_)));
    let io: Error = SkSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}

#[test]
fn builds_with_supported_algorithms() {
    // Smoke: the public fields accept both sk-* variants. The
    // actual signing path requires a connected authenticator and
    // is exercised via the integration test (gated `#[ignore]`).
    let _ = FidoSigner {
        algorithm: Algorithm::SkEd25519,
        credential: dummy_credential(),
    };
    let _ = FidoSigner {
        algorithm: Algorithm::SkEcdsaSha2NistP256,
        credential: dummy_credential(),
    };
}
