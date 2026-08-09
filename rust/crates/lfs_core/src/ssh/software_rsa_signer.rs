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
#[path = "../../tests/unit/ssh_software_rsa_signer.rs"]
mod tests;
