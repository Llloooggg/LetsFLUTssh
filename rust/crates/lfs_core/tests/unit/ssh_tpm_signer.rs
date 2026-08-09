/// Unit tests extracted from ssh/tpm_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn tpm_algo_round_trips_through_key_type_tag() {
    for (tag, expected) in [
        ("ecdsa-sha2-nistp256", TpmAlgo::EcdsaP256),
        ("ecdsa-p256", TpmAlgo::EcdsaP256),
        ("rsa-2048", TpmAlgo::Rsa2048),
        ("rsa", TpmAlgo::Rsa2048),
        ("ssh-rsa", TpmAlgo::Rsa2048),
    ] {
        assert_eq!(TpmAlgo::from_key_type(tag).unwrap(), expected);
    }
}

#[test]
fn tpm_algo_rejects_ed25519() {
    let err = TpmAlgo::from_key_type("ed25519").unwrap_err();
    assert!(matches!(err, Error::Tpm(_)));
}

#[test]
fn tpm_signer_error_round_trips_to_core_error() {
    let core: Error = TpmSignerError::Tpm(Error::Tpm("oops".into())).into();
    assert!(matches!(core, Error::Tpm(_)));
    let io: Error = TpmSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}

#[test]
fn russh_algorithm_maps_per_variant() {
    assert!(matches!(
        TpmAlgo::EcdsaP256.russh_algorithm(),
        Algorithm::Ecdsa {
            curve: EcdsaCurve::NistP256
        }
    ));
    assert!(matches!(
        TpmAlgo::Rsa2048.russh_algorithm(),
        Algorithm::Rsa { .. }
    ));
}

#[test]
fn wire_algorithm_defaults_rsa_to_sha256() {
    assert_eq!(TpmAlgo::EcdsaP256.wire_algorithm(), "ecdsa-sha2-nistp256");
    assert_eq!(TpmAlgo::Rsa2048.wire_algorithm(), "rsa-sha2-256");
}
