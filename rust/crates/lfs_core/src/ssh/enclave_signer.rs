//! `russh::auth::Signer` adapter that routes per-message SSH userauth
//! signatures through Apple's Secure Enclave.
//!
//! Mirrors the shape `ssh::pkcs11_signer::Pkcs11Signer` ships for
//! smart-card tokens. The signer holds the on-chip application-tag
//! bytes captured at create time; every `auth_sign` invocation hops
//! into `tokio::task::spawn_blocking` so the (rare but not free)
//! `SecKeyCreateSignature` round trip doesn't stall the FRB worker.
//!
//! Private key material lives on the chip — we never see it. The
//! `application_tag` blob is the only disambiguation surface the
//! Keychain needs at sign time.

#![cfg(any(target_os = "macos", target_os = "ios"))]

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, HashAlg};
use russh::Signer;

use crate::error::Error;

/// Apple Secure Enclave Signer wrapping a stored hardware key.
///
/// `application_tag` is the opaque bytes the Keychain
/// `SecItemCopyMatching` resolves to the on-chip private key.
/// Captured at create time, persisted in `ssh_keys.enclave_tag`,
/// re-passed verbatim on every sign.
pub struct EnclaveSigner {
    pub application_tag: Vec<u8>,
    pub label: String,
}

#[derive(Debug)]
pub enum EnclaveSignerError {
    Send(russh::SendError),
    Enclave(Error),
}

impl std::fmt::Display for EnclaveSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Enclave(e) => write!(f, "enclave signer: {e}"),
        }
    }
}

impl std::error::Error for EnclaveSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Enclave(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for EnclaveSignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for EnclaveSignerError {
    fn from(e: Error) -> Self {
        Self::Enclave(e)
    }
}

impl From<EnclaveSignerError> for Error {
    fn from(e: EnclaveSignerError) -> Self {
        match e {
            EnclaveSignerError::Send(send) => Error::Io(send.to_string()),
            EnclaveSignerError::Enclave(err) => err,
        }
    }
}

impl Signer for EnclaveSigner {
    type Error = EnclaveSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        _hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        let application_tag = self.application_tag.clone();

        async move {
            let (mut buf, sig_wrapper) =
                tokio::task::spawn_blocking(move || -> Result<(Vec<u8>, Vec<u8>), Error> {
                    use lfs_os_security::apple_se_ssh;
                    let handle = apple_se_ssh::EnclaveKeyHandle {
                        application_tag: application_tag.clone(),
                        label: String::new(),
                    };
                    // The OS performs SHA-256 internally — pass the
                    // raw userauth input, not a pre-hash. Returned
                    // bytes are DER `SEQUENCE { INTEGER r, INTEGER s }`.
                    let der = apple_se_ssh::sign(&handle, &to_sign, None)
                        .map_err(|e| Error::Enclave(e.to_string()))?;
                    let sig_blob = crate::ssh::wire::ecdsa_der_to_ssh_mpint(&der)?;
                    let wrapped = crate::ssh::wire::encode_userauth_signature_field(
                        "ecdsa-sha2-nistp256",
                        &sig_blob,
                    );
                    Ok((to_sign, wrapped))
                })
                .await
                .map_err(|e| {
                    EnclaveSignerError::Enclave(Error::Enclave(format!("spawn_blocking: {e}")))
                })??;
            buf.extend_from_slice(&sig_wrapper);
            Ok(buf)
        }
    }
}

/// Wire-format algorithm string for SE-bound SSH keys. Always
/// `ecdsa-sha2-nistp256` — the SE silicon only implements P-256
/// ECDSA, no other variant exists.
pub fn ssh_algorithm_string() -> &'static str {
    "ecdsa-sha2-nistp256"
}

/// Russh `Algorithm` shape for SE-bound keys. Returns
/// `Algorithm::Ecdsa { curve: NistP256 }`.
pub fn algorithm() -> Algorithm {
    Algorithm::Ecdsa {
        curve: russh::keys::ssh_key::EcdsaCurve::NistP256,
    }
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_enclave_signer.rs"]
mod tests;
