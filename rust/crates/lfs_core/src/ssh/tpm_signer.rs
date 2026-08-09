//! `russh::auth::Signer` adapter that routes per-message SSH userauth
//! signatures through the TPM 2.0 module.
//!
//! Mirrors the Hello / Enclave / PKCS#11 signer shapes — the signer
//! holds the algorithm + the blob bytes (Linux) or the CNG name
//! (Windows silent variant); every `auth_sign` invocation hops into
//! `tokio::task::spawn_blocking` so the TPM round trip — `TPM2_Load`
//! and `TPM2_Sign` on Linux, `NCryptSignHash` on Windows — doesn't
//! stall the FRB worker.
//!
//! Private key material lives in the TPM; the host never sees the
//! raw bytes. On Linux the wrapped-blob mode pays a `TPM2_Load`
//! call (~5-20 ms) on every sign; persistent-handle mode skips it.
//! On Windows the silent variant runs unattended — no Hello prompt
//! fires.

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, EcdsaCurve, HashAlg};
use russh::Signer;
use zeroize::Zeroizing;

use crate::error::Error;

/// TPM SSH algorithm — pinned at create time. Re-derived from the
/// row's `ssh_keys.key_type` column when the connect path re-binds
/// the signer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TpmAlgo {
    EcdsaP256,
    Rsa2048,
}

impl TpmAlgo {
    pub fn from_key_type(key_type: &str) -> Result<Self, Error> {
        match key_type {
            "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Self::EcdsaP256),
            "rsa" | "ssh-rsa" | "rsa-2048" => Ok(Self::Rsa2048),
            other => Err(Error::Tpm(format!(
                "unknown key_type for TPM signer: {other}"
            ))),
        }
    }

    /// Default SSH wire-name.
    pub fn wire_algorithm(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "ecdsa-sha2-nistp256",
            // Default to SHA-256 — TPM 2.0 RSA-2048 is typically
            // deployed against older OpenSSH servers where SHA-256
            // has the widest acceptance. The russh outer layer may
            // promote to SHA-512 when the server-side flag selects
            // it; the wire name comes back through `hash_alg` on
            // `auth_sign`.
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
            Self::Rsa2048 => Algorithm::Rsa { hash: None },
        }
    }
}

/// TPM provider variant — set at create time.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TpmProvider {
    /// Linux ESAPI driver with the wrapped blob bytes.
    TssEsapiBlob(Vec<u8>),
    /// Windows Microsoft Platform Crypto Provider silent variant —
    /// carries the CNG persistent-key name.
    CngPcpSilent(String),
}

/// TPM SSH Signer wrapping a stored key.
pub struct TpmSigner {
    pub provider: TpmProvider,
    pub algo: TpmAlgo,
    /// PIN bytes resolved from the SecretStore (`tpm.pin.<key_id>`)
    /// at connect-prepare time. `None` for empty-auth keys. Held in
    /// `Zeroizing` so the secret is wiped on drop, matching the
    /// PKCS#11 signer's PIN discipline.
    pub pin: Option<Zeroizing<Vec<u8>>>,
    pub label: String,
}

#[derive(Debug)]
pub enum TpmSignerError {
    Send(russh::SendError),
    Tpm(Error),
}

impl std::fmt::Display for TpmSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Tpm(e) => write!(f, "tpm signer: {e}"),
        }
    }
}

impl std::error::Error for TpmSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Tpm(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for TpmSignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for TpmSignerError {
    fn from(e: Error) -> Self {
        Self::Tpm(e)
    }
}

impl From<TpmSignerError> for Error {
    fn from(e: TpmSignerError) -> Self {
        match e {
            TpmSignerError::Send(s) => Error::Io(s.to_string()),
            TpmSignerError::Tpm(err) => err,
        }
    }
}

impl Signer for TpmSigner {
    type Error = TpmSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        let provider = self.provider.clone();
        let algo = self.algo;
        let pin = self.pin.clone();
        let wire_alg = match algo {
            TpmAlgo::EcdsaP256 => "ecdsa-sha2-nistp256".to_string(),
            TpmAlgo::Rsa2048 => match hash_alg {
                Some(HashAlg::Sha512) => "rsa-sha2-512".to_string(),
                _ => "rsa-sha2-256".to_string(),
            },
        };

        async move {
            let (mut buf, sig_wrapper) =
                tokio::task::spawn_blocking(move || -> Result<(Vec<u8>, Vec<u8>), Error> {
                    let raw_wire = sign_native(
                        &provider,
                        algo,
                        pin.as_ref().map(|p| p.as_slice()),
                        &to_sign,
                        &wire_alg,
                    )?;
                    let wrapped =
                        crate::ssh::wire::encode_userauth_signature_field(&wire_alg, &raw_wire);
                    Ok((to_sign, wrapped))
                })
                .await
                .map_err(|e| TpmSignerError::Tpm(Error::Tpm(format!("spawn_blocking: {e}"))))??;
            buf.extend_from_slice(&sig_wrapper);
            Ok(buf)
        }
    }
}

#[cfg(target_os = "linux")]
fn sign_native(
    provider: &TpmProvider,
    algo: TpmAlgo,
    pin: Option<&[u8]>,
    to_sign: &[u8],
    _wire_alg: &str,
) -> Result<Vec<u8>, Error> {
    use lfs_os_security::linux::tpm::TpmConfig;
    use lfs_os_security::linux::tpm_ssh;
    match provider {
        TpmProvider::TssEsapiBlob(blob) => {
            let mut key = tpm_ssh::import_blob(blob).map_err(|e| Error::Tpm(e.to_string()))?;
            let row_algo = match algo {
                TpmAlgo::EcdsaP256 => tpm_ssh::TpmSshAlgorithm::EcdsaP256,
                TpmAlgo::Rsa2048 => tpm_ssh::TpmSshAlgorithm::Rsa2048,
            };
            if key.algorithm != row_algo {
                return Err(Error::Tpm(format!(
                    "blob algorithm {:?} does not match row algorithm {row_algo:?}",
                    key.algorithm
                )));
            }
            let _ = &mut key;
            let cfg = TpmConfig::default();
            let sig =
                tpm_ssh::sign(&cfg, &key, pin, to_sign).map_err(|e| Error::Tpm(e.to_string()))?;
            match sig {
                tpm_ssh::TpmSshSignature::EcdsaP256RawConcat(bytes) => {
                    crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes)
                }
                tpm_ssh::TpmSshSignature::Rsa2048(bytes) => {
                    Ok(crate::ssh::wire::rsa_pkcs1_v15_sig_body(&bytes))
                }
            }
        }
        TpmProvider::CngPcpSilent(_) => {
            Err(Error::Tpm("CNG-PCP silent variant is Windows-only".into()))
        }
    }
}

#[cfg(target_os = "windows")]
fn sign_native(
    provider: &TpmProvider,
    algo: TpmAlgo,
    _pin: Option<&[u8]>,
    to_sign: &[u8],
    wire_alg: &str,
) -> Result<Vec<u8>, Error> {
    use lfs_os_security::windows::ncrypt_ssh::{
        self, HelloSignature, SshKeyAlgo, TpmSilentKeyHandle,
    };
    match provider {
        TpmProvider::CngPcpSilent(name) => {
            let nc_algo = match algo {
                TpmAlgo::EcdsaP256 => SshKeyAlgo::EcdsaP256,
                TpmAlgo::Rsa2048 => SshKeyAlgo::Rsa2048,
            };
            let handle = TpmSilentKeyHandle {
                credential_name: name.clone(),
                algo: nc_algo,
                label: String::new(),
            };
            let raw = ncrypt_ssh::sign_for_ssh_silent(&handle, to_sign, wire_alg)
                .map_err(|e| Error::Tpm(e.to_string()))?;
            match raw {
                HelloSignature::EcdsaRaw(bytes) => {
                    crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes)
                }
                HelloSignature::RsaPkcs1V15(bytes) => {
                    Ok(crate::ssh::wire::rsa_pkcs1_v15_sig_body(&bytes))
                }
            }
        }
        TpmProvider::TssEsapiBlob(_) => Err(Error::Tpm("tss-esapi driver is Linux-only".into())),
    }
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
fn sign_native(
    _provider: &TpmProvider,
    _algo: TpmAlgo,
    _pin: Option<&[u8]>,
    _to_sign: &[u8],
    _wire_alg: &str,
) -> Result<Vec<u8>, Error> {
    Err(Error::Tpm(
        "TPM 2.0 SSH keys unavailable on this platform".into(),
    ))
}
#[cfg(test)]
#[path = "../../tests/unit/ssh_tpm_signer.rs"]
mod tests;
