/// Unit tests extracted from ssh/keystore_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn keystore_algo_round_trips_through_key_type_tag() {
    for (tag, expected) in [
        ("ecdsa-sha2-nistp256", KeystoreAlgo::EcdsaP256),
        ("ecdsa-p256", KeystoreAlgo::EcdsaP256),
        ("ed25519", KeystoreAlgo::Ed25519),
        ("ssh-ed25519", KeystoreAlgo::Ed25519),
        ("rsa", KeystoreAlgo::Rsa2048),
        ("ssh-rsa", KeystoreAlgo::Rsa2048),
        ("rsa-2048", KeystoreAlgo::Rsa2048),
    ] {
        assert_eq!(KeystoreAlgo::from_key_type(tag).unwrap(), expected);
    }
}

#[test]
fn keystore_algo_rejects_unknown_tag() {
    let err = KeystoreAlgo::from_key_type("ecdsa-p521").unwrap_err();
    assert!(matches!(err, Error::Keystore(_)));
}

#[test]
fn keystore_signer_error_round_trips_to_core_error() {
    let core: Error = KeystoreSignerError::Keystore(Error::Keystore("oops".into())).into();
    assert!(matches!(core, Error::Keystore(_)));
    let io: Error = KeystoreSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}

#[test]
fn russh_algorithm_maps_per_variant() {
    assert!(matches!(
        KeystoreAlgo::EcdsaP256.russh_algorithm(),
        Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256
        }
    ));
    assert!(matches!(
        KeystoreAlgo::Ed25519.russh_algorithm(),
        Algorithm::Ed25519
    ));
    assert!(matches!(
        KeystoreAlgo::Rsa2048.russh_algorithm(),
        Algorithm::Rsa { .. }
    ));
}

#[test]
fn wire_algorithm_returns_canonical_names() {
    assert_eq!(
        KeystoreAlgo::EcdsaP256.wire_algorithm(),
        "ecdsa-sha2-nistp256"
    );
    assert_eq!(KeystoreAlgo::Ed25519.wire_algorithm(), "ssh-ed25519");
    assert_eq!(KeystoreAlgo::Rsa2048.wire_algorithm(), "rsa-sha2-256");
}
