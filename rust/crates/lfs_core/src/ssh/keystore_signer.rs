//! `russh::auth::Signer` adapter that routes per-message SSH
//! userauth signatures through the Android Hardware Keystore /
//! StrongBox JNI bridge in `lfs_os_security::android::keystore_signer`.
//!
//! Mirrors the Hello / Enclave / PKCS#11 / TPM signer shapes — the
//! signer holds the AndroidKeyStore alias + the algorithm; every
//! `auth_sign` invocation hops into the JNI bridge's
//! `tokio::task::spawn_blocking` (which the bridge then routes
//! through the main thread to fire `BiometricPrompt.CryptoObject`).
//!
//! Private key material lives in the AndroidKeyStore (TEE or
//! StrongBox); the host never sees the raw bytes. Every sign fires
//! a BiometricPrompt that the user must approve — this is the
//! load-bearing contrast with the silent-TPM and Enclave paths,
//! which dispatch their own OS prompts but typically inside a
//! short auth window (Apple's cached LAContext / Linux fprintd
//! grace period).

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, EcdsaCurve, HashAlg};
use russh::Signer;

use crate::error::Error;

/// Keystore SSH algorithm — pinned at create time. Re-derived from
/// the row's `ssh_keys.key_type` column when the connect path
/// re-binds the signer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeystoreAlgo {
    /// ECDSA P-256 — the StrongBox-eligible default; widest hardware
    /// coverage on Android.
    EcdsaP256,
    /// Ed25519 — Android 13+ only (KeyMint v2). StrongBox NOT
    /// guaranteed.
    Ed25519,
    /// RSA-2048 PKCS#1 v1.5 — widest TEE compatibility. RSA-3072 /
    /// 4096 are intentionally not surfaced; StrongBox rejects them.
    Rsa2048,
}

impl KeystoreAlgo {
    pub fn from_key_type(key_type: &str) -> Result<Self, Error> {
        match key_type {
            "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Self::EcdsaP256),
            "ed25519" | "ssh-ed25519" => Ok(Self::Ed25519),
            "rsa" | "ssh-rsa" | "rsa-2048" => Ok(Self::Rsa2048),
            other => Err(Error::Keystore(format!(
                "unknown key_type for Keystore signer: {other}"
            ))),
        }
    }

    /// Default SSH wire-name for the algorithm.
    pub fn wire_algorithm(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::Ed25519 => "ssh-ed25519",
            // AndroidKeyStore RSA keys are configured for SHA-256 at
            // create time; the russh outer layer may still ask for
            // SHA-512 via the `hash_alg` argument, but the
            // AndroidKeyStore `Signature` algorithm name is fixed
            // (`SHA256withRSA`) so we surface SHA-256 here.
            Self::Rsa2048 => "rsa-sha2-256",
        }
    }

    /// Russh `Algorithm` shape — drives the userauth public-key
    /// type selection.
    pub fn russh_algorithm(self) -> Algorithm {
        match self {
            Self::EcdsaP256 => Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            },
            Self::Ed25519 => Algorithm::Ed25519,
            Self::Rsa2048 => Algorithm::Rsa { hash: None },
        }
    }
}

/// Keystore SSH Signer wrapping a stored AndroidKeyStore alias.
pub struct KeystoreSigner {
    /// AndroidKeyStore alias the `KeyStore.getEntry(alias, null)`
    /// lookup re-binds to on every sign. Persisted on
    /// `ssh_keys.keystore_alias`.
    pub keystore_alias: String,
    pub algo: KeystoreAlgo,
    /// Free-form label — for log-prefix use only; never crosses the
    /// JNI boundary.
    pub label: String,
}

#[derive(Debug)]
pub enum KeystoreSignerError {
    Send(russh::SendError),
    Keystore(Error),
}

impl std::fmt::Display for KeystoreSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Keystore(e) => write!(f, "keystore signer: {e}"),
        }
    }
}

impl std::error::Error for KeystoreSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Keystore(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for KeystoreSignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for KeystoreSignerError {
    fn from(e: Error) -> Self {
        Self::Keystore(e)
    }
}

impl From<KeystoreSignerError> for Error {
    fn from(e: KeystoreSignerError) -> Self {
        match e {
            KeystoreSignerError::Send(s) => Error::Io(s.to_string()),
            KeystoreSignerError::Keystore(err) => err,
        }
    }
}

impl Signer for KeystoreSigner {
    type Error = KeystoreSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        _hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        let keystore_alias = self.keystore_alias.clone();
        let algo = self.algo;
        let wire_alg = algo.wire_algorithm().to_string();

        async move {
            let (mut buf, sig_wrapper) = sign_native(&keystore_alias, algo, &to_sign, &wire_alg)
                .await
                .map(|sig_body| {
                    let wrapped =
                        crate::ssh::wire::encode_userauth_signature_field(&wire_alg, &sig_body);
                    (to_sign, wrapped)
                })?;
            buf.extend_from_slice(&sig_wrapper);
            Ok(buf)
        }
    }
}

#[cfg(target_os = "android")]
async fn sign_native(
    keystore_alias: &str,
    algo: KeystoreAlgo,
    to_sign: &[u8],
    _wire_alg: &str,
) -> Result<Vec<u8>, Error> {
    use lfs_os_security::android::keystore_signer as ks;
    let ks_algo = match algo {
        KeystoreAlgo::EcdsaP256 => ks::KeystoreAlgo::EcdsaP256,
        KeystoreAlgo::Ed25519 => ks::KeystoreAlgo::Ed25519,
        KeystoreAlgo::Rsa2048 => ks::KeystoreAlgo::Rsa2048,
    };
    let outcome = ks::sign(keystore_alias.to_string(), ks_algo, to_sign.to_vec()).await;
    match outcome {
        ks::SignResult::Signed(bytes) => match algo {
            KeystoreAlgo::EcdsaP256 => crate::ssh::wire::ecdsa_der_to_ssh_mpint(&bytes),
            KeystoreAlgo::Ed25519 => crate::ssh::wire::ed25519_sig_body(&bytes),
            KeystoreAlgo::Rsa2048 => Ok(crate::ssh::wire::rsa_pkcs1_v15_sig_body(&bytes)),
        },
        ks::SignResult::Invalidated => Err(Error::Keystore(
            "invalidated: biometric enrolment changed, re-register the public key".into(),
        )),
        ks::SignResult::StrongBoxUnavailable => Err(Error::Keystore(
            "strongbox unavailable: device refused the StrongBox-bound key".into(),
        )),
        ks::SignResult::UserNotAuthenticated => Err(Error::Keystore(
            "user not authenticated: BiometricPrompt auth window expired".into(),
        )),
        ks::SignResult::Cancelled => Err(Error::Keystore(
            "cancelled: user dismissed the BiometricPrompt".into(),
        )),
        ks::SignResult::Other(s) => Err(Error::Keystore(s)),
    }
}

#[cfg(not(target_os = "android"))]
async fn sign_native(
    _keystore_alias: &str,
    _algo: KeystoreAlgo,
    _to_sign: &[u8],
    _wire_alg: &str,
) -> Result<Vec<u8>, Error> {
    Err(Error::Keystore(
        "Android Hardware Keystore SSH keys unavailable on this platform".into(),
    ))
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_keystore_signer.rs"]
mod tests;
