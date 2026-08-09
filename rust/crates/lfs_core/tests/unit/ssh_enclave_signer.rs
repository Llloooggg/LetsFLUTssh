/// Unit tests extracted from ssh/enclave_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn algorithm_string_is_p256_ecdsa() {
    assert_eq!(ssh_algorithm_string(), "ecdsa-sha2-nistp256");
}

#[test]
fn algorithm_returns_ecdsa_p256() {
    match algorithm() {
        Algorithm::Ecdsa { curve } => {
            assert_eq!(curve, russh::keys::ssh_key::EcdsaCurve::NistP256);
        }
        other => panic!("expected ECDSA P-256, got {other:?}"),
    }
}

#[test]
fn signer_error_round_trips_to_core_error() {
    let core: Error = EnclaveSignerError::Enclave(Error::Enclave("oops".into())).into();
    assert!(matches!(core, Error::Enclave(_)));
    let io: Error = EnclaveSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}
