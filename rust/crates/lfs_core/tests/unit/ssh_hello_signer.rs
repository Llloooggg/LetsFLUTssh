/// Unit tests extracted from ssh/hello_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn hello_algo_round_trips_through_key_type_tag() {
    for (tag, expected) in [
        ("ecdsa-sha2-nistp256", HelloAlgo::EcdsaP256),
        ("ecdsa-sha2-nistp384", HelloAlgo::EcdsaP384),
        ("rsa-2048", HelloAlgo::Rsa2048),
        ("ssh-rsa", HelloAlgo::Rsa2048),
    ] {
        assert_eq!(HelloAlgo::from_key_type(tag).unwrap(), expected);
    }
}

#[test]
fn hello_algo_rejects_unknown_key_type() {
    let err = HelloAlgo::from_key_type("ed25519").unwrap_err();
    assert!(matches!(err, Error::Hello(_)));
}

#[test]
fn hello_signer_error_round_trips_to_core_error() {
    let core: Error = HelloSignerError::Hello(Error::Hello("oops".into())).into();
    assert!(matches!(core, Error::Hello(_)));
    let io: Error = HelloSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}

#[test]
fn russh_algorithm_maps_per_variant() {
    assert!(matches!(
        HelloAlgo::EcdsaP256.russh_algorithm(),
        Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256
        }
    ));
    assert!(matches!(
        HelloAlgo::EcdsaP384.russh_algorithm(),
        Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP384
        }
    ));
    assert!(matches!(
        HelloAlgo::Rsa2048.russh_algorithm(),
        Algorithm::Rsa { .. }
    ));
}
