/// Unit tests extracted from ssh/software_rsa_signer.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use rand_core_06::OsRng;
use rsa::pkcs1v15::{SigningKey, VerifyingKey};
use rsa::signature::{SignatureEncoding, Signer as _, Verifier as _};
use russh::keys::ssh_key::Algorithm;
use sha2_v10::{Sha256, Sha512};

fn rsa_private_key_for(keypair: &RsaKeypair) -> rsa::RsaPrivateKey {
    let der = rsa_keypair_to_pkcs8_der(keypair).unwrap();
    use rsa::pkcs8::DecodePrivateKey;
    rsa::RsaPrivateKey::from_pkcs8_der(der.as_ref()).unwrap()
}

fn generate_rsa_2048() -> PrivateKey {
    let kp = RsaKeypair::random(&mut rand::rng(), 2048).unwrap();
    PrivateKey::new(KeypairData::Rsa(kp), "test-rsa".to_string()).unwrap()
}

/// The whole safety claim in one assertion: PKCS#1 v1.5 is
/// deterministic, so ring's signature over a message MUST equal the
/// RustCrypto `rsa` crate's signature for the same key + message.
/// Identical bytes prove we changed only the implementation that
/// computes the signature, not the protocol output on the wire.
#[test]
fn ring_signature_matches_rsa_crate_byte_for_byte() {
    let key = generate_rsa_2048();
    let KeypairData::Rsa(keypair) = key.key_data() else {
        unreachable!()
    };
    let signer = SoftwareRsaSigner::try_new(&key).unwrap().unwrap();
    let rsa_key = rsa_private_key_for(keypair);
    let msg = b"userauth transcript bytes to sign";

    // SHA-256
    let (_, pad256) = rsa_hash_params(Some(HashAlg::Sha256));
    let ring256 = ring_sign_raw(&signer.key_pair, pad256, msg).unwrap();
    let rsa256 = SigningKey::<Sha256>::new(rsa_key.clone())
        .sign(msg)
        .to_vec();
    assert_eq!(
        ring256, rsa256,
        "SHA-256 RSA signature must match rsa crate"
    );

    // SHA-512
    let (_, pad512) = rsa_hash_params(Some(HashAlg::Sha512));
    let ring512 = ring_sign_raw(&signer.key_pair, pad512, msg).unwrap();
    let rsa512 = SigningKey::<Sha512>::new(rsa_key).sign(msg).to_vec();
    assert_eq!(
        ring512, rsa512,
        "SHA-512 RSA signature must match rsa crate"
    );
}

#[test]
fn ring_signature_verifies_under_public_key() {
    let key = generate_rsa_2048();
    let KeypairData::Rsa(keypair) = key.key_data() else {
        unreachable!()
    };
    let signer = SoftwareRsaSigner::try_new(&key).unwrap().unwrap();
    let rsa_key = rsa_private_key_for(keypair);
    let msg = b"verify me";

    let (_, pad256) = rsa_hash_params(Some(HashAlg::Sha256));
    let raw = ring_sign_raw(&signer.key_pair, pad256, msg).unwrap();

    let verifying = VerifyingKey::<Sha256>::new(rsa_key.to_public_key());
    let sig = rsa::pkcs1v15::Signature::try_from(raw.as_slice()).unwrap();
    verifying.verify(msg, &sig).expect("signature must verify");
}

/// Authoritative format check: the userauth `signature` field is
/// ONE outer SSH string wrapping `string(alg) || string(raw)`.
/// Decode the produced bytes exactly as russh's SERVER does — read
/// one string, then parse the inner as an ssh-key `Signature` — and
/// confirm it round-trips. The pre-fix wrap omitted the outer
/// string, so the server read a wrong length and rejected every
/// software RSA credential.
#[test]
fn userauth_signature_field_matches_server_decode() {
    use russh::keys::ssh_key::encoding::Decode;
    use russh::keys::ssh_key::{Algorithm, Signature};

    let raw_sig = vec![0x42u8; 256];
    let to_sign = vec![0xAAu8, 0xBB, 0xCC];
    let out = wrap_userauth_signature(to_sign.clone(), "rsa-sha2-256", &raw_sig);

    // to_sign is preserved verbatim as the prefix russh writes
    // before the signature field.
    assert_eq!(&out[..3], &to_sign[..]);

    // The server reads the signature field as ONE SSH string...
    let mut reader = &out[3..];
    let inner = Vec::<u8>::decode(&mut reader).unwrap();
    assert!(
        reader.is_empty(),
        "exactly one outer string follows to_sign"
    );
    // ...then decodes the inner blob as an ssh-key Signature.
    let sig = Signature::decode(&mut inner.as_slice()).unwrap();
    assert!(matches!(
        sig.algorithm(),
        Algorithm::Rsa {
            hash: Some(HashAlg::Sha256)
        }
    ));
    assert_eq!(sig.as_bytes(), &raw_sig[..]);
}

#[test]
fn hash_params_default_to_sha256() {
    assert_eq!(rsa_hash_params(None).0, "rsa-sha2-256");
    assert_eq!(rsa_hash_params(Some(HashAlg::Sha256)).0, "rsa-sha2-256");
    assert_eq!(rsa_hash_params(Some(HashAlg::Sha512)).0, "rsa-sha2-512");
}

#[test]
fn try_new_returns_none_for_non_rsa_key() {
    let key = PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).unwrap();
    assert!(SoftwareRsaSigner::try_new(&key).unwrap().is_none());
}

/// The fallback mechanism `try_new` relies on: ring rejects RSA
/// below its 2048-bit floor, so a legacy sub-2048 import drops to
/// the legacy path instead of erroring the connection.
#[test]
fn ring_rejects_sub_2048_pkcs8() {
    use rsa::pkcs8::EncodePrivateKey;
    let small = rsa::RsaPrivateKey::new(&mut OsRng, 1024).unwrap();
    let der = small.to_pkcs8_der().unwrap();
    assert!(RsaKeyPair::from_pkcs8(der.as_bytes()).is_err());
}

#[test]
fn signer_error_round_trips_to_core_error() {
    let core: Error = SoftwareRsaSignerError::Sign(Error::Auth("oops".into())).into();
    assert!(matches!(core, Error::Auth(_)));
    let io: Error = SoftwareRsaSignerError::Send(russh::SendError {}).into();
    assert!(matches!(io, Error::Io(_)));
}
