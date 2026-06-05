//! `russh::Signer` adapter that signs **software** RSA keys through
//! `ring` (constant-time, blinded) instead of the RustCrypto `rsa`
//! crate's variable-time private-key path.
//!
//! ## Why
//! The default `ssh-key` userauth path signs RSA via
//! `rsa::pkcs1v15::SigningKey`, whose variable-time modular
//! exponentiation is RUSTSEC-2023-0071 (Marvin). Re-routing the
//! online signing operation through ring removes the only
//! network-observable secret-timing surface of the `rsa` crate in
//! this client. The `rsa` crate is still touched here — but only to
//! re-shape the already-parsed key components (`n/e/d/p/q`) into
//! PKCS#8 DER for ring. That is a one-shot offline encode, never the
//! online signing op, so it presents no timing oracle. See
//! `osv-scanner.toml` / SECURITY.md for the full reachability note.
//!
//! ## Fallback discipline — additive, never subtractive
//! `try_new` returns `Ok(None)` (rather than an error) when the key
//! is not RSA, or when ring declines it (RSA below ring's 2048-bit
//! floor, or otherwise unsupported). The caller then keeps the
//! existing `PrivateKeyWithHashAlg` path, so no key that authenticates
//! today stops authenticating. Net effect: a strict improvement for
//! the common case (>=2048-bit `rsa-sha2`), zero capability loss.

use std::future::Future;
use std::sync::Arc;

use ring::rand::SystemRandom;
use ring::signature::{RsaEncoding, RsaKeyPair, RSA_PKCS1_SHA256, RSA_PKCS1_SHA512};
use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::private::{KeypairData, RsaKeypair};
use russh::keys::ssh_key::{HashAlg, Mpint};
use russh::keys::PrivateKey;
use russh::Signer;
use zeroize::Zeroizing;

use crate::error::Error;

/// Constant-time software RSA signer. Holds the ring key behind an
/// `Arc` so each `auth_sign` can hand it to a blocking task without
/// reborrowing `&mut self` across the await.
pub struct SoftwareRsaSigner {
    key_pair: Arc<RsaKeyPair>,
}

impl SoftwareRsaSigner {
    /// Build a ring-backed signer from a parsed software RSA private
    /// key. `Ok(None)` selects the caller's fallback: the key is not
    /// RSA, or ring rejected it (sub-2048-bit / unsupported shape).
    pub fn try_new(key: &PrivateKey) -> Result<Option<Self>, Error> {
        let KeypairData::Rsa(keypair) = key.key_data() else {
            return Ok(None);
        };
        let der = rsa_keypair_to_pkcs8_der(keypair)?;
        match RsaKeyPair::from_pkcs8(der.as_ref()) {
            Ok(key_pair) => Ok(Some(Self {
                key_pair: Arc::new(key_pair),
            })),
            // ring declines RSA below 2048 bits (and other malformed
            // shapes) — fall back to the legacy path rather than
            // failing the connection.
            Err(_) => Ok(None),
        }
    }
}

/// Re-encode parsed RSA key components into PKCS#8 DER for ring.
/// Offline, one-shot, no private-key modexp — touches the `rsa` crate
/// only as an ASN.1 encoder. The DER is wrapped in `Zeroizing` so the
/// plaintext key material is scrubbed once ring has ingested it.
fn rsa_keypair_to_pkcs8_der(keypair: &RsaKeypair) -> Result<Zeroizing<Vec<u8>>, Error> {
    use rsa::pkcs8::EncodePrivateKey;
    use rsa::BigUint;

    let component = |m: &Mpint, name: &str| -> Result<BigUint, Error> {
        let bytes = m.as_positive_bytes().ok_or_else(|| {
            Error::KeyParse(format!("rsa component {name} is not a positive mpint"))
        })?;
        Ok(BigUint::from_bytes_be(bytes))
    };

    let n = component(keypair.public().n(), "n")?;
    let e = component(keypair.public().e(), "e")?;
    let d = component(keypair.private().d(), "d")?;
    let p = component(keypair.private().p(), "p")?;
    let q = component(keypair.private().q(), "q")?;

    let rsa_key = rsa::RsaPrivateKey::from_components(n, e, d, vec![p, q])
        .map_err(|e| Error::KeyParse(format!("rsa from_components: {e}")))?;
    let der = rsa_key
        .to_pkcs8_der()
        .map_err(|e| Error::KeyParse(format!("rsa pkcs8 encode: {e}")))?;
    Ok(Zeroizing::new(der.as_bytes().to_vec()))
}

/// Map the negotiated RSA hash to ring's padding scheme and the SSH
/// wire algorithm name. `None`/SHA-1 collapses to SHA-256 — the
/// connect path never advertises a SHA-1 `ssh-rsa` key through this
/// signer (it pins `Some(Sha256)`), and ring cannot emit SHA-1 in any
/// case.
fn rsa_hash_params(hash_alg: Option<HashAlg>) -> (&'static str, &'static dyn RsaEncoding) {
    match hash_alg {
        Some(HashAlg::Sha512) => ("rsa-sha2-512", &RSA_PKCS1_SHA512),
        _ => ("rsa-sha2-256", &RSA_PKCS1_SHA256),
    }
}

/// Produce the raw PKCS#1 v1.5 signature over `msg` via ring. Output
/// length is the modulus length. Deterministic — ring's RSA signing
/// is constant-time and the PKCS#1 v1.5 encoding carries no salt.
fn ring_sign_raw(
    key_pair: &RsaKeyPair,
    padding: &'static dyn RsaEncoding,
    msg: &[u8],
) -> Result<Vec<u8>, Error> {
    let rng = SystemRandom::new();
    let mut sig = vec![0u8; key_pair.public().modulus_len()];
    key_pair
        .sign(padding, &rng, msg, &mut sig)
        .map_err(|_| Error::Auth("ring rsa signing failed".into()))?;
    Ok(sig)
}

/// Assemble the russh userauth response: the signed `to_sign` buffer
/// followed by the SSH `signature` field. That field is ONE outer SSH
/// `string` wrapping the signature blob `string(alg) || string(raw)` —
/// mirroring `ssh::sk::encode_signature` and what russh's own
/// `sign_with_hash_alg(..).encode(buffer)` produces on the bare-key
/// path. Omitting the outer string makes the server read the wrong
/// length and reject the credential.
fn wrap_userauth_signature(mut to_sign: Vec<u8>, wire_alg: &str, raw_sig: &[u8]) -> Vec<u8> {
    to_sign.extend_from_slice(&crate::ssh::wire::encode_userauth_signature_field(
        wire_alg, raw_sig,
    ));
    to_sign
}

#[derive(Debug)]
pub enum SoftwareRsaSignerError {
    Send(russh::SendError),
    Sign(Error),
}

impl std::fmt::Display for SoftwareRsaSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Sign(e) => write!(f, "software rsa signer: {e}"),
        }
    }
}

impl std::error::Error for SoftwareRsaSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Sign(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for SoftwareRsaSignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for SoftwareRsaSignerError {
    fn from(e: Error) -> Self {
        Self::Sign(e)
    }
}

impl From<SoftwareRsaSignerError> for Error {
    fn from(e: SoftwareRsaSignerError) -> Self {
        match e {
            SoftwareRsaSignerError::Send(s) => Error::Io(s.to_string()),
            SoftwareRsaSignerError::Sign(err) => err,
        }
    }
}

impl Signer for SoftwareRsaSigner {
    type Error = SoftwareRsaSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        let key_pair = self.key_pair.clone();
        let (wire_alg, padding) = rsa_hash_params(hash_alg);

        async move {
            // RSA signing is a single pure-CPU modexp; hop into a
            // blocking task so the few-millisecond op never stalls the
            // FRB worker's executor thread, mirroring the hardware
            // signer shapes.
            let signed = tokio::task::spawn_blocking(move || -> Result<Vec<u8>, Error> {
                let raw = ring_sign_raw(&key_pair, padding, &to_sign)?;
                Ok(wrap_userauth_signature(to_sign, wire_alg, &raw))
            })
            .await
            .map_err(|e| {
                SoftwareRsaSignerError::Sign(Error::Auth(format!("spawn_blocking: {e}")))
            })??;
            Ok(signed)
        }
    }
}

#[cfg(test)]
mod tests {
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
}
