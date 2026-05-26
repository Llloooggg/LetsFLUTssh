//! `russh::auth::Signer` adapter that routes per-message SSH userauth
//! signatures through a FIDO2 hardware authenticator.
//!
//! russh `0.59` re-exports the `Signer` trait publicly (verified in
//! `russh/src/lib_inner.rs`), so the connect path implements it
//! directly inside `lfs_core` without an in-process agent shim or an
//! upstream russh patch. The signer holds the credential metadata
//! captured at import (`credential_id`, `application`, optional PIN)
//! and forwards every CTAP2 getAssertion to
//! [`crate::fido2::get_assertion`], then composes the userauth
//! signature trailer via [`crate::ssh::sk::encode_sk_signature`] +
//! [`crate::ssh::sk::encode_signature`].
//!
//! Wire flow per signing round trip:
//!
//! 1. russh calls `auth_sign(&AgentIdentity, hash_alg, to_sign)` with
//!    the userauth signature input (already including session id, the
//!    `SSH_MSG_USERAUTH_REQUEST` header, and the public-key blob).
//! 2. We SHA-256 the buffer — CTAP2 expects a 32-byte challenge.
//! 3. The CTAP2 layer drives the HID transport, prompts for touch /
//!    PIN, and returns `SkAssertion { signature, flags, counter }`.
//! 4. [`crate::ssh::sk::encode_sk_signature`] wraps the bytes into the
//!    SSH `sk-*` trailer (Ed25519: `sig || flags || counter`; ECDSA:
//!    `mpint(r) || mpint(s) || flags || counter`).
//! 5. [`crate::ssh::sk::encode_signature`] wraps that into the SSH
//!    userauth signature string `string(algorithm || sig_blob)`. We
//!    append it to `to_sign` and return — russh's `authenticate_*_with`
//!    loop ships the appended buffer as `SSH_MSG_USERAUTH_REQUEST`.
//!
//! Private key material never lands here — the signing key lives on
//! the hardware authenticator and never leaves the device.

use std::future::Future;

use russh::keys::agent::AgentIdentity;
use russh::keys::ssh_key::{Algorithm, HashAlg};
use russh::Signer;

use crate::error::Error;
use crate::ssh::sk::{self, FidoCredential};

/// `russh::auth::Signer` implementation for an imported FIDO2
/// `sk-ed25519` / `sk-ecdsa-sha2-nistp256` SSH key.
pub struct FidoSigner {
    /// SSH key algorithm — drives the wire-format encoder. Must be
    /// one of [`Algorithm::SkEd25519`] / [`Algorithm::SkEcdsaSha2NistP256`];
    /// other variants fail loudly at sign time.
    pub algorithm: Algorithm,
    /// Captured-at-import credential metadata. Cloned across the await
    /// chain because every `auth_sign` invocation drives a fresh CTAP2
    /// getAssertion round trip.
    pub credential: FidoCredential,
}

/// Error type for [`FidoSigner`]. The `Signer` trait requires
/// `Error: From<russh::SendError>`; the FIDO arm of the variant
/// carries the typed `crate::error::Error` from the CTAP2 layer.
#[derive(Debug)]
pub enum SkSignerError {
    /// russh mpsc channel teardown — typically the session was dropped
    /// mid-userauth. Maps to `Error::Io` at the connect boundary.
    Send(russh::SendError),
    /// FIDO2 / CTAP2 round-trip or wire-encoding failure. Carries the
    /// typed core error so the connect path can route a `wrong PIN`
    /// retry differently from a `no device reachable` cancel.
    Fido(Error),
}

impl std::fmt::Display for SkSignerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SkSignerError::Send(e) => write!(f, "russh transport: {e}"),
            SkSignerError::Fido(e) => write!(f, "fido2 signer: {e}"),
        }
    }
}

impl std::error::Error for SkSignerError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            SkSignerError::Send(e) => Some(e),
            SkSignerError::Fido(e) => Some(e),
        }
    }
}

impl From<russh::SendError> for SkSignerError {
    fn from(e: russh::SendError) -> Self {
        SkSignerError::Send(e)
    }
}

impl From<Error> for SkSignerError {
    fn from(e: Error) -> Self {
        SkSignerError::Fido(e)
    }
}

impl From<SkSignerError> for Error {
    fn from(e: SkSignerError) -> Self {
        match e {
            SkSignerError::Send(send) => Error::Io(send.to_string()),
            SkSignerError::Fido(err) => err,
        }
    }
}

impl Signer for FidoSigner {
    type Error = SkSignerError;

    fn auth_sign(
        &mut self,
        _key: &AgentIdentity,
        _hash_alg: Option<HashAlg>,
        mut to_sign: Vec<u8>,
    ) -> impl Future<Output = Result<Vec<u8>, Self::Error>> + Send {
        // Clone the inputs the async tail needs — the borrow on
        // `self` here ends before the future polls, freeing russh to
        // re-enter `auth_sign` on the next round (server-side may
        // issue multiple sign requests during partial-success
        // authentication chains).
        let algorithm = self.algorithm.clone();
        let credential = self.credential.clone();

        async move {
            let signature = sk::sign_for_userauth(&algorithm, &credential, &to_sign)
                .await
                .map_err(SkSignerError::from)?;
            to_sign.extend_from_slice(&signature);
            Ok(to_sign)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dummy_credential() -> FidoCredential {
        FidoCredential {
            credential_id: b"cred-id".to_vec(),
            application: "ssh:".into(),
            pin: None,
        }
    }

    #[test]
    fn signer_error_send_wraps_via_from() {
        let send = russh::SendError {};
        let wrapped: SkSignerError = send.into();
        assert!(matches!(wrapped, SkSignerError::Send(_)));
    }

    #[test]
    fn signer_error_fido_wraps_via_from() {
        let err = Error::Fido2("nope".into());
        let wrapped: SkSignerError = err.into();
        assert!(matches!(wrapped, SkSignerError::Fido(Error::Fido2(_))));
    }

    #[test]
    fn signer_error_displays_both_arms() {
        let s = format!("{}", SkSignerError::Send(russh::SendError {}));
        assert!(s.starts_with("russh transport"));
        let f = format!("{}", SkSignerError::Fido(Error::Fido2("x".into())));
        assert!(f.contains("fido2 signer"));
    }

    #[test]
    fn signer_error_round_trips_to_core_error() {
        let core: Error = SkSignerError::Fido(Error::AuthFailed("rejected".into())).into();
        assert!(matches!(core, Error::AuthFailed(_)));
        let io: Error = SkSignerError::Send(russh::SendError {}).into();
        assert!(matches!(io, Error::Io(_)));
    }

    #[test]
    fn builds_with_supported_algorithms() {
        // Smoke: the public fields accept both sk-* variants. The
        // actual signing path requires a connected authenticator and
        // is exercised via the integration test (gated `#[ignore]`).
        let _ = FidoSigner {
            algorithm: Algorithm::SkEd25519,
            credential: dummy_credential(),
        };
        let _ = FidoSigner {
            algorithm: Algorithm::SkEcdsaSha2NistP256,
            credential: dummy_credential(),
        };
    }
}
