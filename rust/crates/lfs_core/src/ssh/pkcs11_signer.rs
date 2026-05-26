//! `russh::auth::Signer` adapter that routes per-message SSH userauth
//! signatures through a PKCS#11 (Cryptoki) hardware token.
//!
//! Mirrors the shape `ssh::sk_signer::FidoSigner` already shipped for
//! FIDO2 sk-* keys. The signer holds the resolved module path +
//! token serial + `CKA_ID` + SSH algorithm string captured at import
//! and the PIN (if the token's `CKF_LOGIN_REQUIRED` and
//! `CKF_PROTECTED_AUTHENTICATION_PATH` flags say one is needed).
//! Every `auth_sign` call hops into `tokio::task::spawn_blocking` so
//! the slow `C_Sign` round-trip runs on a blocking worker rather
//! than the FRB executor.
//!
//! Private-key material lives on the token; we never see it. The
//! token's `CKA_ID` + serial + module-path triple is the only
//! disambiguation surface we need at sign time.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, HashAlg};
use russh::Signer;
use zeroize::Zeroizing;

use crate::error::Error;

/// PKCS#11 Signer wrapping a stored hardware key.
pub struct Pkcs11Signer {
    pub module_path: String,
    pub token_serial: String,
    pub cka_id: Vec<u8>,
    /// SSH algorithm string we offered for this row at import time
    /// (`rsa-sha2-256` / `rsa-sha2-512` / `ecdsa-sha2-nistp256` /
    /// `ecdsa-sha2-nistp384` / `ecdsa-sha2-nistp521` / `ssh-ed25519`).
    pub algorithm: String,
    /// PIN — owned `Zeroizing<String>` so the bytes wipe when the
    /// Signer drops at the end of the connect attempt. `None` for
    /// protected-authentication-path or no-login tokens.
    pub pin: Option<Zeroizing<String>>,
}

#[derive(Debug)]
pub enum Pkcs11SignerError {
    Send(russh::SendError),
    Pkcs11(Error),
}

impl std::fmt::Display for Pkcs11SignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Send(e) => write!(f, "russh transport: {e}"),
            Self::Pkcs11(e) => write!(f, "pkcs11 signer: {e}"),
        }
    }
}

impl std::error::Error for Pkcs11SignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Send(e) => Some(e),
            Self::Pkcs11(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for Pkcs11SignerError {
    fn from(e: russh::SendError) -> Self {
        Self::Send(e)
    }
}

impl From<Error> for Pkcs11SignerError {
    fn from(e: Error) -> Self {
        Self::Pkcs11(e)
    }
}

impl From<Pkcs11SignerError> for Error {
    fn from(e: Pkcs11SignerError) -> Self {
        match e {
            Pkcs11SignerError::Send(send) => Error::Io(send.to_string()),
            Pkcs11SignerError::Pkcs11(err) => err,
        }
    }
}

impl Signer for Pkcs11Signer {
    type Error = Pkcs11SignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        _hash_alg: Option<HashAlg>,
        to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        // Clone everything the blocking task needs — `Signer::auth_sign`
        // is called once per signature, so the per-call clone cost is
        // dwarfed by the C_Sign latency.
        let module_path = self.module_path.clone();
        let token_serial = self.token_serial.clone();
        let cka_id = self.cka_id.clone();
        let algorithm = self.algorithm.clone();
        let pin = self.pin.as_deref().map(|s| s.to_string());

        async move {
            // Hand the userauth buffer + the wrapped result back out of
            // the blocking task — `russh::Signer::auth_sign` returns
            // the appended buffer, and Vec<u8> moves cheaply.
            let (mut buf, sig_blob) =
                tokio::task::spawn_blocking(move || -> Result<(Vec<u8>, Vec<u8>), Error> {
                    use lfs_os_security::pkcs11;
                    let module = pkcs11::module::load(std::path::Path::new(&module_path))
                        .map_err(|e| Error::Pkcs11(e.to_string()))?;
                    let slots = module
                        .pkcs11()
                        .get_slots_with_token()
                        .map_err(|e| Error::Pkcs11(format!("get_slots: {e}")))?;
                    let slot = slots
                        .into_iter()
                        .find(|s| {
                            module
                                .pkcs11()
                                .get_token_info(*s)
                                .ok()
                                .map(|t| t.serial_number().trim() == token_serial.trim())
                                .unwrap_or(false)
                        })
                        .ok_or_else(|| {
                            Error::Pkcs11(
                                "unplugged: matching token not present in any reader".into(),
                            )
                        })?;
                    let session = pkcs11::session::for_slot(&module, slot);
                    let req = pkcs11::sign::SignRequest {
                        session: &session,
                        pin: pin.as_deref(),
                        cka_id: &cka_id,
                        algorithm: &algorithm,
                        to_sign: &to_sign,
                    };
                    let out = pkcs11::sign::sign_with_pkcs11(req)
                        .map_err(|e| Error::Pkcs11(e.to_string()))?;
                    // Compose the userauth `signature` field:
                    //   string(algorithm) || string(sig_blob)
                    let mut wrapped =
                        Vec::with_capacity(algorithm.len() + out.ssh_sig_body.len() + 8);
                    wrapped.extend_from_slice(&(algorithm.len() as u32).to_be_bytes());
                    wrapped.extend_from_slice(algorithm.as_bytes());
                    wrapped.extend_from_slice(&(out.ssh_sig_body.len() as u32).to_be_bytes());
                    wrapped.extend_from_slice(&out.ssh_sig_body);
                    Ok((to_sign, wrapped))
                })
                .await
                .map_err(|e| {
                    Pkcs11SignerError::Pkcs11(Error::Pkcs11(format!("spawn_blocking: {e}")))
                })??;
            buf.extend_from_slice(&sig_blob);
            Ok(buf)
        }
    }
}

/// Parse `key_type` short tag (`rsa` / `ecdsa-p256` / ...) into the
/// matching russh `Algorithm`. Mirrors what `ssh::sk` does for the
/// `sk-*` short tags.
pub fn algorithm_for_key_type(key_type: &str) -> Result<Algorithm, Error> {
    match key_type {
        "rsa" | "ssh-rsa" => Ok(Algorithm::Rsa { hash: None }),
        "ecdsa-p256" | "ecdsa-sha2-nistp256" => Ok(Algorithm::Ecdsa {
            curve: russh::keys::ssh_key::EcdsaCurve::NistP256,
        }),
        "ecdsa-p384" | "ecdsa-sha2-nistp384" => Ok(Algorithm::Ecdsa {
            curve: russh::keys::ssh_key::EcdsaCurve::NistP384,
        }),
        "ecdsa-p521" | "ecdsa-sha2-nistp521" => Ok(Algorithm::Ecdsa {
            curve: russh::keys::ssh_key::EcdsaCurve::NistP521,
        }),
        "ed25519" | "ssh-ed25519" => Ok(Algorithm::Ed25519),
        other => Err(Error::Pkcs11(format!(
            "unrecognised key_type {other:?} for pkcs11 signer"
        ))),
    }
}

/// Map the stored `key_type` short tag to the SSH algorithm string
/// the signer announces in the `userauth signature` outer wrapper.
pub fn ssh_algorithm_string(key_type: &str) -> &'static str {
    match key_type {
        "rsa" => "rsa-sha2-512",
        "ecdsa-p256" => "ecdsa-sha2-nistp256",
        "ecdsa-p384" => "ecdsa-sha2-nistp384",
        "ecdsa-p521" => "ecdsa-sha2-nistp521",
        "ed25519" => "ssh-ed25519",
        other => other_to_static(other),
    }
}

fn other_to_static(s: &str) -> &'static str {
    // Fallback: surface as a non-empty static — the connect path
    // refuses unknown algorithms downstream so this only fires on
    // pre-validated `key_type` strings.
    match s {
        "ssh-ed25519" => "ssh-ed25519",
        "ecdsa-sha2-nistp256" => "ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp384" => "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521" => "ecdsa-sha2-nistp521",
        "rsa-sha2-256" => "rsa-sha2-256",
        "rsa-sha2-512" => "rsa-sha2-512",
        _ => "ssh-ed25519",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn algorithm_for_key_type_round_trips() {
        assert!(matches!(
            algorithm_for_key_type("ed25519").unwrap(),
            Algorithm::Ed25519
        ));
        assert!(matches!(
            algorithm_for_key_type("ecdsa-p256").unwrap(),
            Algorithm::Ecdsa { .. }
        ));
        assert!(matches!(
            algorithm_for_key_type("rsa").unwrap(),
            Algorithm::Rsa { .. }
        ));
    }

    #[test]
    fn algorithm_for_key_type_rejects_unknown() {
        let err = algorithm_for_key_type("gost-pubkey").unwrap_err();
        assert!(matches!(err, Error::Pkcs11(_)));
    }

    #[test]
    fn ssh_algorithm_string_table() {
        assert_eq!(ssh_algorithm_string("rsa"), "rsa-sha2-512");
        assert_eq!(ssh_algorithm_string("ecdsa-p256"), "ecdsa-sha2-nistp256");
        assert_eq!(ssh_algorithm_string("ed25519"), "ssh-ed25519");
    }

    #[test]
    fn signer_error_round_trips_to_core_error() {
        let core: Error = Pkcs11SignerError::Pkcs11(Error::AuthFailed("rejected".into())).into();
        assert!(matches!(core, Error::AuthFailed(_)));
        let io: Error = Pkcs11SignerError::Send(russh::SendError {}).into();
        assert!(matches!(io, Error::Io(_)));
    }
}
