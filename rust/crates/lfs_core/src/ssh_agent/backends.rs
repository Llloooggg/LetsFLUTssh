//! Backend dispatcher.
//!
//! The agent endpoint sees one [`SignRequest`](ssh_agent_lib::proto::SignRequest)
//! per external SIGN_REQUEST and needs to route it to the right
//! signer based on the stored `ssh_keys.backend` discriminator. This
//! module concentrates that switch in one file so future Signer
//! impls (PKCS#11 / TPM / Secure Enclave / Windows NCrypt / Android
//! Hardware Keystore) plug in here without touching the
//! endpoint-level [`super::endpoint`] machinery.
//!
//! ## Today's surface
//!
//! Only FIDO2 is wired (`backend == 'fido2'`). Other backends
//! return [`Unsupported`](BackendError::Unsupported) until their
//! respective Signer lands. The stored `backend` column is
//! currently always one of:
//!
//! - `'software'` — never reaches this dispatcher (the endpoint
//!   filters software keys out at `request_identities` time so
//!   plaintext PEM material is never exposed through the socket).
//! - `'fido2'` — routed to [`fido2_sign`].
//!
//! Future variants the schema reserves (and the dispatcher will
//! grow arms for, one task each):
//! `'pkcs11'`, `'tpm'`, `'enclave'`, `'hello'`, `'keystore'`.

use crate::db::ssh_keys::SshKeyRow;
use crate::error::Error;

/// Backend dispatcher error. Wraps the underlying signer failure
/// plus the structural variants the dispatcher itself produces.
#[derive(Debug, thiserror::Error)]
pub enum BackendError {
    /// Underlying signer (CTAP2 today; future PKCS#11 / TPM /
    /// Enclave / NCrypt / Keystore) reported an error. Detail is
    /// the typed core error verbatim.
    #[error("agent signer failed: {0}")]
    Signer(Error),

    /// The stored row is a software key — the endpoint filtered
    /// listing should have excluded it before the SIGN_REQUEST
    /// arrived. Defensive arm: surfaces a clear error in the
    /// logs and refuses the sign rather than silently leaking
    /// plaintext PEM material through the agent socket.
    #[error("software keys are never exposed through the agent endpoint")]
    SoftwareKeyRefused,
}

/// SSH userauth-style sign output. Carries the bytes the agent
/// puts on the wire as the `Signature` response — see
/// [`ssh-agent draft §3.6.1`](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-3.6.1).
/// The `algorithm` field is the wire name OpenSSH uses
/// (`ssh-ed25519`, `ecdsa-sha2-nistp256`, `sk-ssh-ed25519@openssh.com`,
/// …).
#[derive(Debug, Clone)]
pub struct SignOutput {
    pub algorithm: String,
    pub signature: Vec<u8>,
}

/// Backend discriminator. Today we resolve from the live
/// `ssh_keys` columns (`credential_id IS NOT NULL` -> `Fido2`,
/// otherwise `Software`). Each future hardware-bound Signer task
/// extends this enum + the matching dispatch arm in lockstep —
/// adding variants before their Signer exists trips
/// dead-code-analysis and the project's lints policy bars
/// suppression.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendKind {
    Software,
    Fido2,
}

impl BackendKind {
    /// Resolve the backend discriminator from a stored `ssh_keys`
    /// row. Today the schema does not carry an explicit `backend`
    /// column; the hardware-key column rollout introduces it,
    /// and at that point this resolver re-routes through the
    /// explicit text. Returning a typed enum keeps the
    /// dispatcher's switch compile-checked at every site.
    pub fn from_row(row: &SshKeyRow) -> Self {
        if row.credential_id.is_some() {
            Self::Fido2
        } else {
            Self::Software
        }
    }
}

/// Dispatch a SIGN_REQUEST. Returns the wire-format signature
/// bytes the endpoint hands back as the `Signature` response.
///
/// `data` is the buffer the external client wants signed — agent
/// protocol §3.6 says it's the SSH userauth signature input
/// (session id + `SSH_MSG_USERAUTH_REQUEST` header + the public
/// key blob). For FIDO2 we SHA-256 it (CTAP2 expects a 32-byte
/// challenge); other backends may sign over the raw bytes
/// directly.
///
/// `flags` is the protocol §3.6.1 flag bitfield. For RSA keys it
/// drives the `rsa-sha2-256` / `rsa-sha2-512` selection; we
/// ignore flags for Ed25519 / ECDSA sk-* paths (the algorithm
/// is captured at import).
pub async fn dispatch_sign(
    row: &SshKeyRow,
    data: &[u8],
    flags: u32,
) -> Result<SignOutput, BackendError> {
    dispatch_sign_by_kind(BackendKind::from_row(row), row, data, flags).await
}

/// Inner dispatcher that takes the resolved [`BackendKind`]
/// directly. Split out so the future hardware-bound rollout can
/// route through an explicit `ssh_keys.backend` text column
/// without duplicating the match.
pub async fn dispatch_sign_by_kind(
    kind: BackendKind,
    row: &SshKeyRow,
    data: &[u8],
    _flags: u32,
) -> Result<SignOutput, BackendError> {
    match kind {
        BackendKind::Software => Err(BackendError::SoftwareKeyRefused),
        BackendKind::Fido2 => fido2_sign(row, data).await,
    }
}

/// FIDO2 dispatcher. SHA-256 the userauth input, ask CTAP2 for
/// an assertion against the stored credential, compose the SSH
/// `sk-*` signature trailer through
/// [`crate::ssh::sk::sign_for_userauth`]. The returned bytes are
/// the full `string(algorithm) || string(sig_blob)` wire body
/// the agent protocol's `Signature` response carries verbatim.
async fn fido2_sign(row: &SshKeyRow, data: &[u8]) -> Result<SignOutput, BackendError> {
    let credential_id = row
        .credential_id
        .as_ref()
        .ok_or_else(|| BackendError::Signer(Error::Fido2("row missing credential_id".into())))?;
    let application = row.application_string.clone().ok_or_else(|| {
        BackendError::Signer(Error::Fido2("row missing application_string".into()))
    })?;

    let algorithm = ssh_algorithm_from_key_type(&row.key_type).map_err(BackendError::Signer)?;
    let algo_label = wire_algorithm_label(&algorithm);

    let credential = crate::ssh::sk::FidoCredential {
        credential_id: credential_id.clone(),
        application,
        // The agent endpoint does not collect a PIN from the
        // external client — there is no protocol surface for it.
        // PIN-required credentials surface a separate confirmation
        // dialog client-side (via the per-key confirm gate) which
        // collects the PIN before reaching this dispatcher. Today
        // we forward `None` and let CTAP2 surface a typed error
        // when UV is required; the dialog flow is wired up in
        // the same task that lands the Settings UI.
        pin: None,
    };

    let signature = crate::ssh::sk::sign_sk_blob_only(&algorithm, &credential, data)
        .await
        .map_err(BackendError::Signer)?;

    Ok(SignOutput {
        algorithm: algo_label,
        signature,
    })
}

/// Map our stored `ssh_keys.key_type` string into a russh
/// `Algorithm` for the SK signer. Stored values:
///
/// - `"sk-ssh-ed25519@openssh.com"`
/// - `"sk-ecdsa-sha2-nistp256@openssh.com"`
fn ssh_algorithm_from_key_type(key_type: &str) -> Result<russh::keys::ssh_key::Algorithm, Error> {
    match key_type {
        "sk-ssh-ed25519@openssh.com" => Ok(russh::keys::ssh_key::Algorithm::SkEd25519),
        "sk-ecdsa-sha2-nistp256@openssh.com" => {
            Ok(russh::keys::ssh_key::Algorithm::SkEcdsaSha2NistP256)
        }
        other => Err(Error::Fido2(format!(
            "agent: key_type {other:?} not a recognised sk-* shape"
        ))),
    }
}

/// Reverse of [`ssh_algorithm_from_key_type`] — the wire label
/// the agent protocol's `Signature` response carries verbatim.
fn wire_algorithm_label(algo: &russh::keys::ssh_key::Algorithm) -> String {
    match algo {
        russh::keys::ssh_key::Algorithm::SkEd25519 => "sk-ssh-ed25519@openssh.com".into(),
        russh::keys::ssh_key::Algorithm::SkEcdsaSha2NistP256 => {
            "sk-ecdsa-sha2-nistp256@openssh.com".into()
        }
        other => format!("{other:?}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::ssh_keys::{AgentPolicy, SshKeyRow};

    fn row_software() -> SshKeyRow {
        SshKeyRow {
            id: "k-sw".into(),
            label: "Software key".into(),
            private_key: "PEM".into(),
            public_key: "PUB".into(),
            key_type: "ssh-ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: AgentPolicy::Ask,
        }
    }

    fn row_fido2_no_creds() -> SshKeyRow {
        SshKeyRow {
            credential_id: Some(vec![1, 2, 3]),
            application_string: Some("ssh:".into()),
            key_type: "sk-ssh-ed25519@openssh.com".into(),
            ..row_software()
        }
    }

    #[test]
    fn from_row_resolves_software_when_no_credential() {
        let row = row_software();
        assert_eq!(BackendKind::from_row(&row), BackendKind::Software);
    }

    #[test]
    fn from_row_resolves_fido2_when_credential_present() {
        let row = row_fido2_no_creds();
        assert_eq!(BackendKind::from_row(&row), BackendKind::Fido2);
    }

    #[tokio::test]
    async fn dispatch_refuses_software_key() {
        let row = row_software();
        let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
        assert!(matches!(err, BackendError::SoftwareKeyRefused));
    }

    #[test]
    fn ssh_algorithm_maps_known_sk_strings() {
        assert!(matches!(
            ssh_algorithm_from_key_type("sk-ssh-ed25519@openssh.com").unwrap(),
            russh::keys::ssh_key::Algorithm::SkEd25519
        ));
        assert!(matches!(
            ssh_algorithm_from_key_type("sk-ecdsa-sha2-nistp256@openssh.com").unwrap(),
            russh::keys::ssh_key::Algorithm::SkEcdsaSha2NistP256
        ));
    }

    #[test]
    fn ssh_algorithm_rejects_unknown_string() {
        let err = ssh_algorithm_from_key_type("rsa-classic").unwrap_err();
        assert!(matches!(err, Error::Fido2(_)));
    }

    #[test]
    fn backend_error_software_refused_renders_message() {
        let err = BackendError::SoftwareKeyRefused;
        let s = err.to_string();
        assert!(s.contains("software keys"));
    }
}
