/// Unit tests extracted from ssh/pkcs11_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn algorithm_for_key_type_round_trips() {
    assert!(matches!(
        algorithm_for_key_type("ed25519").unwrap(),
        Algorithm::Ed25519
    ));
    assert!(matches!(
        algorithm_for_key_type("ecdsa-p256").unwrap(),
        Algorithm::Ecdsa { .. }
    ));
    assert!(matches!(
        algorithm_for_key_type("rsa").unwrap(),
        Algorithm::Rsa { .. }
    ));
}

#[test]
fn algorithm_for_key_type_rejects_unknown() {
    let err = algorithm_for_key_type("gost-pubkey").unwrap_err();
    assert!(matches!(err, Error::Pkcs11(_)));
}

#[test]
fn ssh_algorithm_string_table() {
    assert_eq!(ssh_algorithm_string("rsa"), "rsa-sha2-512");
    assert_eq!(ssh_algorithm_string("ecdsa-p256"), "ecdsa-sha2-nistp256");
    assert_eq!(ssh_algorithm_string("ed25519"), "ssh-ed25519");
}

#[test]
fn signer_error_round_trips_to_core_error() {
    let core: Error = Pkcs11SignerError::Pkcs11(Error::AuthFailed("rejected".into())).into();
    assert!(matches!(core, Error::AuthFailed(_)));
    let io: Error = Pkcs11SignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}
