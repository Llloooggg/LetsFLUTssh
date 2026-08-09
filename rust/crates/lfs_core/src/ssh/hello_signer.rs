//! `russh::auth::Signer` adapter that routes per-message SSH userauth
//! signatures through Windows Hello (NCrypt / Microsoft Platform
//! Crypto Provider).
//!
//! Mirrors the Apple Secure Enclave / PKCS#11 signer shapes — the
//! signer holds the CNG persistent-key name captured at create time;
//! every `auth_sign` invocation hops into `tokio::task::spawn_blocking`
//! so the (rare but not free) `NCryptSignHash` round trip — and the
//! Hello PIN / fingerprint / face prompt fired inside it — doesn't
//! stall the FRB worker.
//!
//! Private key material lives in the TPM (or PCP software KSP
//! fallback); the host never sees the raw bytes. The
//! `credential_name` string is the only disambiguation surface
//! `NCryptOpenKey` needs at sign time.

#![cfg(target_os = "windows")]

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, EcdsaCurve, HashAlg};
use russh::Signer;

use crate::error::Error;

/// Algorithm pinned at create time. Re-derived from the row's
/// `ssh_keys.key_type` column when the connect path re-binds the
/// signer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HelloAlgo {
    EcdsaP256,
    EcdsaP384,
    Rsa2048,
}

impl HelloAlgo {
    pub fn from_key_type(key_type: &str) -> Result<Self, Error> {
        match key_type {
            "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Self::EcdsaP256),
            "ecdsa-p384" | "ecdsa-sha2-nistp384" => Ok(Self::EcdsaP384),
            "rsa" | "ssh-rsa" | "rsa-2048" => Ok(Self::Rsa2048),
            other => Err(Error::Hello(format!(
                "unknown key_type for Hello signer: {other}"
            ))),
        }
    }

    /// Map to the NCrypt SSH-side algorithm enum the
    /// `lfs_os_security::windows::ncrypt_ssh` layer reaches for.
    fn ncrypt_algo(self) -> lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo {
        use lfs_os_security::windows::ncrypt_ssh::SshKeyAlgo;
        match self {
            Self::EcdsaP256 => SshKeyAlgo::EcdsaP256,
            Self::EcdsaP384 => SshKeyAlgo::EcdsaP384,
            Self::Rsa2048 => SshKeyAlgo::Rsa2048,
        }
    }

    /// Default SSH wire-name. RSA defaults to `rsa-sha2-512`; the
    /// agent dispatcher may downgrade to `rsa-sha2-256` per the
    /// protocol flag, but the connect path takes the stronger of
    /// the two SHA-2 variants by default.
    pub fn wire_algorithm(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            Self::EcdsaP384 => "ecdsa-sha2-nistp384",
            Self::Rsa2048 => "rsa-sha2-512",
        }
    }

    /// Russh `Algorithm` shape for the resolved Hello key.
    pub fn russh_algorithm(self) -> Algorithm {
        match self {
            Self::EcdsaP256 => Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            },
            Self::EcdsaP384 => Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP384,
            },
            Self::Rsa2048 => Algorithm::Rsa { hash: None },
        }
    }
}

/// Windows Hello Signer wrapping a stored CNG persistent key.
pub struct HelloSigner {
    pub credential_name: String,
    pub algo: HelloAlgo,
    pub label: String,
}

#[derive(Debug)]
pub enum HelloSignerError {
    Send(russh::SendError),
    Hello(Error),
}

impl std::fmt::Display for HelloSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Hello(e) => write!(f, "hello signer: {e}"),
        }
    }
}

impl std::error::Error for HelloSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Hello(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for HelloSignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for HelloSignerError {
    fn from(e: Error) -> Self {
        Self::Hello(e)
    }
}

impl From<HelloSignerError> for Error {
    fn from(e: HelloSignerError) -> Self {
        match e {
            HelloSignerError::Send(s) => Error::Io(s.to_string()),
            HelloSignerError::Hello(err) => err,
        }
    }
}

impl Signer for HelloSigner {
    type Error = HelloSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        let credential_name = self.credential_name.clone();
        let algo = self.algo;
        // For RSA, russh hands the hash algorithm (`HashAlg::Sha256`
        // / `HashAlg::Sha512`) via the negotiated `rsa-sha2-*` arm;
        // ECDSA passes None and we derive the SHA from the curve.
        let wire_alg = match algo {
            HelloAlgo::EcdsaP256 => "ecdsa-sha2-nistp256".to_string(),
            HelloAlgo::EcdsaP384 => "ecdsa-sha2-nistp384".to_string(),
            HelloAlgo::Rsa2048 => match hash_alg {
                Some(HashAlg::Sha256) => "rsa-sha2-256".to_string(),
                Some(HashAlg::Sha512) => "rsa-sha2-512".to_string(),
                _ => "rsa-sha2-512".to_string(),
            },
        };

        async move {
            let (mut buf, sig_wrapper) =
                tokio::task::spawn_blocking(move || -> Result<(Vec<u8>, Vec<u8>), Error> {
                    use lfs_os_security::windows::ncrypt_ssh;
                    let handle = ncrypt_ssh::HelloKeyHandle {
                        credential_name,
                        algo: algo.ncrypt_algo(),
                        label: String::new(),
                    };
                    let raw = ncrypt_ssh::sign_for_ssh(&handle, &to_sign, &wire_alg)
                        .map_err(|e| Error::Hello(e.to_string()))?;
                    // Wrap the NCrypt raw output via the shared SSH
                    // wire helpers (`lfs_os_security` stays free of
                    // `lfs_core` deps — the wrap happens here).
                    let sig_blob = match raw {
                        ncrypt_ssh::HelloSignature::EcdsaRaw(bytes) => {
                            crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes)?
                        }
                        ncrypt_ssh::HelloSignature::RsaPkcs1V15(bytes) => {
                            crate::ssh::wire::rsa_pkcs1_v15_sig_body(&bytes)
                        }
                    };
                    let wrapped =
                        crate::ssh::wire::encode_userauth_signature_field(&wire_alg, &sig_blob);
                    Ok((to_sign, wrapped))
                })
                .await
                .map_err(|e| {
                    HelloSignerError::Hello(Error::Hello(format!("spawn_blocking: {e}")))
                })??;
            buf.extend_from_slice(&sig_wrapper);
            Ok(buf)
        }
    }
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_hello_signer.rs"]
mod tests;
