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

/// Backend discriminator. Schema v9 introduced the explicit
/// `ssh_keys.backend` TEXT column; the dispatcher reads it through
/// the typed [`KeyBackend`] enum on the row. Each future
/// hardware-bound Signer task extends this enum + the matching
/// dispatch arm in lockstep — adding variants before their Signer
/// exists trips dead-code-analysis and the project's lints policy
/// bars suppression.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendKind {
    Software,
    Fido2,
    Pkcs11,
    Enclave,
    Hello,
    /// TPM 2.0 — Linux `tss-esapi` driver (blob mode or persistent
    /// NV handle) and the Windows Microsoft Platform Crypto Provider
    /// **silent** variant (no UI policy set, signs unattended). The
    /// Hello-gated NCrypt path is a separate backend
    /// ([`BackendKind::Hello`]) because the user-visible security
    /// contract differs — Hello rows fire a PIN/fingerprint/face
    /// prompt on every sign; silent TPM rows do not.
    Tpm,
    /// Android Hardware Keystore / StrongBox HSM. The agent endpoint
    /// itself is `#[cfg(any(target_os = "linux", target_os = "macos",
    /// target_os = "windows"))]` — Android has no in-process agent
    /// surface — so this variant only ever surfaces on the connect
    /// path's typed dispatcher. The dispatch arm here exists for
    /// symmetry; the agent-side `dispatch_sign_by_kind` surfaces a
    /// typed `Error::Keystore("unavailable on this platform")` on
    /// the desktop targets where the agent endpoint exists.
    Keystore,
}

impl BackendKind {
    /// Resolve the backend discriminator from a stored `ssh_keys`
    /// row. Reads the typed `backend` column; pre-v9 software-only
    /// rows surface as `Software`, FIDO2 rows surface as `Fido2`,
    /// PKCS#11 rows surface as `Pkcs11`, Apple Secure Enclave rows
    /// surface as `Enclave`, Hello rows as `Hello`, TPM rows as
    /// `Tpm`. Reserved `Keystore` (Android Hardware Keystore) still
    /// falls through to `Software` until its Signer lands; the
    /// listing path filters those out before the dispatcher sees
    /// them, so the fallback never fires in practice.
    pub fn from_row(row: &SshKeyRow) -> Self {
        use crate::db::ssh_keys::KeyBackend;
        match row.backend {
            KeyBackend::Fido2 => Self::Fido2,
            KeyBackend::Pkcs11 => Self::Pkcs11,
            KeyBackend::Enclave => Self::Enclave,
            KeyBackend::Hello => Self::Hello,
            KeyBackend::Tpm => Self::Tpm,
            KeyBackend::Keystore => Self::Keystore,
            _ => Self::Software,
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
    flags: u32,
) -> Result<SignOutput, BackendError> {
    match kind {
        BackendKind::Software => Err(BackendError::SoftwareKeyRefused),
        BackendKind::Fido2 => fido2_sign(row, data).await,
        BackendKind::Pkcs11 => pkcs11_sign(row, data, flags).await,
        BackendKind::Enclave => enclave_sign(row, data).await,
        BackendKind::Hello => hello_sign(row, data, flags).await,
        BackendKind::Tpm => tpm_sign(row, data, flags).await,
        BackendKind::Keystore => keystore_sign(row, data).await,
    }
}

/// Android Hardware Keystore dispatcher stub. The agent endpoint
/// module is `#[cfg(any(target_os = "linux", target_os = "macos",
/// target_os = "windows"))]` so this arm only runs on desktop —
/// where the Keystore key cannot exist (the chip is Android-only and
/// the listing path filters `backend = 'keystore'` rows out long
/// before the dispatcher sees them). Surface the typed unsupported
/// error so a manually-crafted row never silently downgrades to a
/// software arm.
async fn keystore_sign(_row: &SshKeyRow, _data: &[u8]) -> Result<SignOutput, BackendError> {
    Err(BackendError::Signer(Error::Keystore(
        "Android Hardware Keystore is reachable only on Android in-app sessions".into(),
    )))
}

/// TPM 2.0 dispatcher. Routes to the Linux ESAPI driver (`tss-esapi`)
/// for `tpm_provider = "tss-esapi"` rows and to the Windows PCP
/// silent-variant driver for `tpm_provider = "cng-pcp"` rows. The
/// agent endpoint never collects a PIN at SIGN_REQUEST time — there
/// is no protocol surface for it; PIN-bound TPM keys reach into the
/// SecretStore for an entry under `tpm.pin.<key_id>` that the
/// user-facing UI seeded earlier (typically during the connect
/// flow). Absent that entry on a PIN-bound row, the dispatcher
/// refuses with a typed `Tpm` error so the external client surfaces
/// a clear "no PIN cached" failure rather than hanging on a wrong-
/// auth lockout.
#[cfg(any(target_os = "linux", target_os = "windows"))]
async fn tpm_sign(row: &SshKeyRow, data: &[u8], flags: u32) -> Result<SignOutput, BackendError> {
    let provider = row
        .tpm_provider
        .clone()
        .ok_or_else(|| BackendError::Signer(Error::Tpm("row missing tpm_provider".into())))?;
    let key_type = row.key_type.clone();
    // Inputs captured for the spawn_blocking closure. The Linux blob
    // path needs the row id (PIN-cache lookup) + the `tpm_pin_required`
    // flag + the wrapped blob bytes; the Windows PCP-silent path needs
    // the CNG persistent-key name. Each side gates its bindings via
    // `#[cfg(target_os = "...")]` on the binding so the unused
    // variables don't trip clippy on the other host.
    #[cfg(target_os = "linux")]
    let key_id = row.id.clone();
    #[cfg(target_os = "linux")]
    let pin_required = row.tpm_pin_required;
    #[cfg(target_os = "linux")]
    let blob = row.tpm_blob.clone();
    #[cfg(target_os = "windows")]
    let cng_name = row.cng_key_name.clone();
    let data = data.to_vec();
    let algorithm = ssh_algorithm_for_tpm(&key_type, flags);

    tokio::task::spawn_blocking(move || -> Result<SignOutput, BackendError> {
        let raw = match provider.as_str() {
            #[cfg(target_os = "linux")]
            "tss-esapi" => tpm_sign_tss_esapi(&key_id, &key_type, pin_required, blob, &data)?,
            #[cfg(target_os = "windows")]
            "cng-pcp" => tpm_sign_cng_silent(&key_type, cng_name, &data, &algorithm)?,
            other => {
                return Err(BackendError::Signer(Error::Tpm(format!(
                    "unknown tpm_provider {other:?}"
                ))));
            }
        };
        Ok(SignOutput {
            algorithm: algorithm.clone(),
            signature: raw,
        })
    })
    .await
    .map_err(|e| BackendError::Signer(Error::Tpm(format!("spawn_blocking: {e}"))))?
}

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
async fn tpm_sign(_row: &SshKeyRow, _data: &[u8], _flags: u32) -> Result<SignOutput, BackendError> {
    Err(BackendError::Signer(Error::Tpm(
        "TPM 2.0 SSH keys unavailable on this platform".into(),
    )))
}

/// Linux ESAPI sign-by-blob — reuses
/// [`lfs_os_security::linux::tpm_ssh::sign`]. The agent dispatcher
/// path runs in `spawn_blocking` (the call up here is the inner
/// closure), so the synchronous TPM round trip doesn't stall the
/// Tokio worker pool.
#[cfg(target_os = "linux")]
fn tpm_sign_tss_esapi(
    key_id: &str,
    key_type: &str,
    pin_required: bool,
    blob: Option<Vec<u8>>,
    data: &[u8],
) -> Result<Vec<u8>, BackendError> {
    use lfs_os_security::linux::tpm_ssh::{self, TpmSshAlgorithm};
    let blob = blob
        .ok_or_else(|| BackendError::Signer(Error::Tpm("tss-esapi row missing tpm_blob".into())))?;
    let key = tpm_ssh::import_blob(&blob)
        .map_err(|e| BackendError::Signer(Error::Tpm(format!("import_blob: {e}"))))?;
    // Force the row's algorithm onto the key — the import path
    // recovers it from the public-key shape; if the row was tagged
    // differently surface the mismatch loudly rather than signing
    // under an unexpected algorithm.
    let row_algo = TpmSshAlgorithm::from_key_type(key_type)
        .map_err(|e| BackendError::Signer(Error::Tpm(format!("key_type: {e}"))))?;
    if key.algorithm != row_algo {
        return Err(BackendError::Signer(Error::Tpm(format!(
            "blob algorithm {:?} does not match row key_type {key_type}",
            key.algorithm
        ))));
    }
    let auth: Option<Vec<u8>> = if pin_required {
        let pin_id = format!("tpm.pin.{key_id}");
        match crate::app::instance().secrets.get(&pin_id) {
            Some(z) => Some(z.to_vec()),
            None => {
                return Err(BackendError::Signer(Error::Tpm(
                    "tpm pin required but not cached".into(),
                )));
            }
        }
    } else {
        None
    };
    let cfg = lfs_os_security::linux::tpm::TpmConfig::default();
    let sig = tpm_ssh::sign(&cfg, &key, auth.as_deref(), data)
        .map_err(|e| BackendError::Signer(Error::Tpm(e.to_string())))?;
    let wire = match sig {
        tpm_ssh::TpmSshSignature::EcdsaP256RawConcat(bytes) => {
            crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes).map_err(BackendError::Signer)?
        }
        tpm_ssh::TpmSshSignature::Rsa2048(bytes) => {
            crate::ssh::wire::rsa_pkcs1_v15_to_ssh_blob(&bytes)
        }
    };
    Ok(wire)
}

/// Windows PCP silent-variant sign — reuses
/// [`lfs_os_security::windows::ncrypt_ssh::sign_for_ssh_silent`].
/// `NCryptSignHash` runs unattended per the absence of
/// `NCRYPT_UI_POLICY_PROPERTY` at create time.
#[cfg(target_os = "windows")]
fn tpm_sign_cng_silent(
    key_type: &str,
    cng_name: Option<String>,
    data: &[u8],
    algorithm: &str,
) -> Result<Vec<u8>, BackendError> {
    use lfs_os_security::windows::ncrypt_ssh::{
        self, HelloSignature, SshKeyAlgo, TpmSilentKeyHandle,
    };
    let credential_name = cng_name.ok_or_else(|| {
        BackendError::Signer(Error::Tpm("cng-pcp row missing cng_key_name".into()))
    })?;
    let algo = SshKeyAlgo::from_key_type(key_type)
        .map_err(|e| BackendError::Signer(Error::Tpm(format!("key_type: {e}"))))?;
    let handle = TpmSilentKeyHandle {
        credential_name,
        algo,
        label: String::new(),
    };
    let raw = ncrypt_ssh::sign_for_ssh_silent(&handle, data, algorithm)
        .map_err(|e| BackendError::Signer(Error::Tpm(e.to_string())))?;
    let wire = match raw {
        HelloSignature::EcdsaRaw(bytes) => {
            crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes).map_err(BackendError::Signer)?
        }
        HelloSignature::RsaPkcs1V15(bytes) => crate::ssh::wire::rsa_pkcs1_v15_to_ssh_blob(&bytes),
    };
    Ok(wire)
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn ssh_algorithm_for_tpm(key_type: &str, flags: u32) -> String {
    match key_type {
        "rsa" | "ssh-rsa" | "rsa-2048" => {
            // SSH agent draft §3.6.1: flag 0x02 picks SHA-256, 0x04
            // picks SHA-512. Default to SHA-256 for the TPM path —
            // TPM-bound RSA-2048 keys are typically deployed against
            // older OpenSSH servers and SHA-256 has the widest
            // server-side acceptance. The agent dispatcher can
            // promote to SHA-512 when the server flags request it.
            if flags & 0x04 != 0 {
                "rsa-sha2-512".into()
            } else {
                "rsa-sha2-256".into()
            }
        }
        "ecdsa-p256" | "ecdsa-sha2-nistp256" => "ecdsa-sha2-nistp256".into(),
        other => other.to_string(),
    }
}

/// Apple Secure Enclave dispatcher. Resolves the row's
/// application-tag bytes, asks `lfs_os_security::apple_se_ssh` to
/// sign the userauth buffer, then composes the SSH wire body.
///
/// No PIN handling at the agent boundary — the OS surfaces its
/// own biometric / passcode prompt inside
/// `SecKeyCreateSignature` per the access-control flags chosen
/// at create time. Idle/cached LAContext reuse is wired at the
/// FRB worker boundary (one context per agent session); this
/// dispatcher passes `None` so the OS uses its own per-call
/// prompt unless a previous sign within the cache window
/// authorized the chip.
#[cfg(any(target_os = "macos", target_os = "ios"))]
async fn enclave_sign(row: &SshKeyRow, data: &[u8]) -> Result<SignOutput, BackendError> {
    let application_tag = row
        .enclave_tag
        .clone()
        .ok_or_else(|| BackendError::Signer(Error::Enclave("row missing enclave_tag".into())))?;
    let data = data.to_vec();
    tokio::task::spawn_blocking(move || -> Result<SignOutput, BackendError> {
        use lfs_os_security::apple_se_ssh;
        let handle = apple_se_ssh::EnclaveKeyHandle {
            application_tag,
            label: String::new(),
        };
        let der = apple_se_ssh::sign(&handle, &data, None)
            .map_err(|e| BackendError::Signer(Error::Enclave(e.to_string())))?;
        let sig_blob =
            crate::ssh::wire::ecdsa_der_to_ssh_mpint(&der).map_err(BackendError::Signer)?;
        Ok(SignOutput {
            algorithm: "ecdsa-sha2-nistp256".into(),
            signature: sig_blob,
        })
    })
    .await
    .map_err(|e| BackendError::Signer(Error::Enclave(format!("spawn_blocking: {e}"))))?
}

/// Non-Apple stub — SE keys are macOS / iOS only. The listing
/// path filters `backend = 'enclave'` rows out on every other
/// target so this branch is reached only on impossible cfg
/// combinations.
#[cfg(not(any(target_os = "macos", target_os = "ios")))]
async fn enclave_sign(_row: &SshKeyRow, _data: &[u8]) -> Result<SignOutput, BackendError> {
    Err(BackendError::Signer(Error::Enclave(
        "Apple Secure Enclave unavailable on this platform".into(),
    )))
}

/// Windows Hello dispatcher. Resolves the row's CNG persistent-key
/// name, asks `lfs_os_security::windows::ncrypt_ssh` to sign the
/// userauth buffer, then composes the SSH wire body.
///
/// The Hello prompt (PIN / fingerprint / face) fires inside the
/// `NCryptSignHash` call per the `NCRYPT_UI_POLICY_PROPERTY` set at
/// create time. The agent endpoint never collects a PIN — there is
/// no protocol surface for it, and Hello has no concept of a
/// pre-staged credential. Cancellation by the user surfaces as a
/// typed `Hello` error.
#[cfg(target_os = "windows")]
async fn hello_sign(row: &SshKeyRow, data: &[u8], flags: u32) -> Result<SignOutput, BackendError> {
    let credential_name = row.hello_credential_name.clone().ok_or_else(|| {
        BackendError::Signer(Error::Hello("row missing hello_credential_name".into()))
    })?;
    let key_type = row.key_type.clone();
    let data = data.to_vec();
    tokio::task::spawn_blocking(move || -> Result<SignOutput, BackendError> {
        use lfs_os_security::windows::ncrypt_ssh;
        let algo = ncrypt_ssh::SshKeyAlgo::from_key_type(&key_type).map_err(|e| {
            BackendError::Signer(Error::Hello(format!("unknown key_type {key_type}: {e}")))
        })?;
        let handle = ncrypt_ssh::HelloKeyHandle {
            credential_name: credential_name.clone(),
            algo,
            label: String::new(),
        };
        let algorithm = ssh_algorithm_for_hello(&key_type, flags);
        let raw = ncrypt_ssh::sign_for_ssh(&handle, &data, &algorithm)
            .map_err(|e| BackendError::Signer(Error::Hello(e.to_string())))?;
        // Wrap the NCrypt raw output via the shared SSH wire helpers
        // — the `lfs_os_security` crate stays free of `lfs_core` deps
        // (audit invariant), so the wrap happens here instead.
        let signature = match raw {
            ncrypt_ssh::HelloSignature::EcdsaRaw(bytes) => {
                crate::ssh::wire::ecdsa_raw_concat_to_ssh_mpint(&bytes)
                    .map_err(BackendError::Signer)?
            }
            ncrypt_ssh::HelloSignature::RsaPkcs1V15(bytes) => {
                crate::ssh::wire::rsa_pkcs1_v15_to_ssh_blob(&bytes)
            }
        };
        Ok(SignOutput {
            algorithm,
            signature,
        })
    })
    .await
    .map_err(|e| BackendError::Signer(Error::Hello(format!("spawn_blocking: {e}"))))?
}

/// Non-Windows stub — Hello rows are filtered out of the listing
/// surface on every other platform, so this arm fires only on
/// impossible cfg combinations.
#[cfg(not(target_os = "windows"))]
async fn hello_sign(
    _row: &SshKeyRow,
    _data: &[u8],
    _flags: u32,
) -> Result<SignOutput, BackendError> {
    Err(BackendError::Signer(Error::Hello(
        "Windows Hello unavailable on this platform".into(),
    )))
}

/// SSH wire-name selection for Hello-bound keys. RSA flags follow the
/// agent-protocol §3.6.1 bitfield (0x02 = SHA-256, 0x04 = SHA-512);
/// ECDSA curves map verbatim. Default RSA hash is SHA-512 because
/// stronger-by-default beats backwards compatibility with the
/// SHA-1-era `ssh-rsa` wire-name (which the NCrypt SSH path refuses
/// to emit at all).
#[cfg(target_os = "windows")]
fn ssh_algorithm_for_hello(key_type: &str, flags: u32) -> String {
    match key_type {
        "rsa" | "ssh-rsa" | "rsa-2048" => {
            // §3.6.1: 0x02 picks SHA-256. Anything else (0x04 set or
            // no hash flag at all) lands on SHA-512 — stronger-by-
            // default beats SHA-1-era `ssh-rsa`, which NCrypt SSH
            // refuses to emit anyway.
            if flags & 0x02 != 0 {
                "rsa-sha2-256".into()
            } else {
                "rsa-sha2-512".into()
            }
        }
        "ecdsa-p256" | "ecdsa-sha2-nistp256" => "ecdsa-sha2-nistp256".into(),
        "ecdsa-p384" | "ecdsa-sha2-nistp384" => "ecdsa-sha2-nistp384".into(),
        other => other.to_string(),
    }
}

/// PKCS#11 dispatcher. Resolves the row's module path, token serial,
/// and `CKA_ID`, asks `lfs_os_security::pkcs11` to sign the userauth
/// buffer, then composes the SSH wire body.
///
/// PIN handling for agent-endpoint dispatch: the wire protocol has
/// no surface for a PIN prompt during sign; we reach into the
/// SecretStore for an entry under `pkcs11.pin.<key_id>` that the
/// user-facing UI seeded earlier (typically the import or the
/// recently-completed connect flow). Absent that entry, the
/// dispatcher refuses with a typed `Pkcs11` error so the external
/// client surfaces a clear "no PIN cached" failure rather than
/// hanging on a `C_Login` without a PIN.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
async fn pkcs11_sign(row: &SshKeyRow, data: &[u8], flags: u32) -> Result<SignOutput, BackendError> {
    // Pull module path + CKA_ID out of the row; refuse loudly if a
    // backend='pkcs11' row is missing either ingredient — that
    // shape would be a DB corruption case the schema check at
    // import already rejects.
    let module_path = row.pkcs11_module_path.clone().ok_or_else(|| {
        BackendError::Signer(Error::Pkcs11("row missing pkcs11_module_path".into()))
    })?;
    let object_id = row.pkcs11_object_id.clone().ok_or_else(|| {
        BackendError::Signer(Error::Pkcs11("row missing pkcs11_object_id".into()))
    })?;

    let key_id = row.id.clone();
    let key_type = row.key_type.clone();
    let token_serial = row.pkcs11_token_serial.clone();
    let data = data.to_vec();

    tokio::task::spawn_blocking(move || -> Result<SignOutput, BackendError> {
        let path = std::path::PathBuf::from(&module_path);
        let module = lfs_os_security::pkcs11::module::load(&path)
            .map_err(|e| BackendError::Signer(Error::Pkcs11(format!("load module: {e}"))))?;
        // Walk slots to find one whose token serial matches.
        let slots = module
            .pkcs11()
            .get_slots_with_token()
            .map_err(|e| BackendError::Signer(Error::Pkcs11(format!("get_slots: {e}"))))?;
        let mut matched = None;
        for slot in slots {
            if let Ok(info) = module.pkcs11().get_token_info(slot) {
                let serial = info.serial_number().to_string();
                if token_serial.as_deref() == Some(serial.trim()) {
                    matched = Some(slot);
                    break;
                }
            }
        }
        let slot = matched.ok_or_else(|| {
            BackendError::Signer(Error::Pkcs11(
                "unplugged: matching token not present".into(),
            ))
        })?;
        let session = lfs_os_security::pkcs11::session::for_slot(&module, slot);
        // PIN resolution — read the cached entry under the canonical id.
        let pin_id = format!("pkcs11.pin.{key_id}");
        let pin_bytes = crate::app::instance().secrets.get(&pin_id);
        let pin_str = match pin_bytes.as_ref() {
            Some(b) => Some(
                std::str::from_utf8(b)
                    .map_err(|_| {
                        BackendError::Signer(Error::Pkcs11("pin: cached entry not utf-8".into()))
                    })?
                    .to_string(),
            ),
            None => None,
        };
        // RSA flag selection: 0x02 = rsa-sha2-256, 0x04 = rsa-sha2-512
        // per draft-miller-ssh-agent §3.6.1. ECDSA / Ed25519 ignore flags.
        let algorithm = ssh_algorithm_for_pkcs11(&key_type, flags);
        let req = lfs_os_security::pkcs11::sign::SignRequest {
            session: &session,
            pin: pin_str.as_deref(),
            cka_id: &object_id,
            algorithm: &algorithm,
            to_sign: &data,
        };
        let out = lfs_os_security::pkcs11::sign::sign_with_pkcs11(req)
            .map_err(|e| BackendError::Signer(Error::Pkcs11(e.to_string())))?;
        Ok(SignOutput {
            algorithm,
            signature: out.ssh_sig_body,
        })
    })
    .await
    .map_err(|e| BackendError::Signer(Error::Pkcs11(format!("spawn_blocking: {e}"))))?
}

/// Mobile stub — the desktop-only `lfs_os_security::pkcs11` module
/// is not built on Android / iOS. The agent endpoint itself is also
/// stubbed there, so this branch is reached only on impossible
/// cfg combinations; surface a typed unsupported error so the build
/// stays cfg-clean.
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
async fn pkcs11_sign(
    _row: &SshKeyRow,
    _data: &[u8],
    _flags: u32,
) -> Result<SignOutput, BackendError> {
    Err(BackendError::Signer(Error::Pkcs11(
        "pkcs11 unavailable on this platform".into(),
    )))
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn ssh_algorithm_for_pkcs11(key_type: &str, flags: u32) -> String {
    match key_type {
        "rsa" | "ssh-rsa" => {
            // SSH agent draft §3.6.1: flag 0x02 selects SHA-256,
            // 0x04 selects SHA-512. Default to SHA-512 (the stronger
            // option) when neither bit is set — old `ssh-rsa` SHA-1
            // is server-deprecated and the PKCS#11 sign path refuses
            // it explicitly.
            if flags & 0x02 != 0 {
                "rsa-sha2-256".into()
            } else {
                "rsa-sha2-512".into()
            }
        }
        "ecdsa-p256" | "ecdsa-sha2-nistp256" => "ecdsa-sha2-nistp256".into(),
        "ecdsa-p384" | "ecdsa-sha2-nistp384" => "ecdsa-sha2-nistp384".into(),
        "ecdsa-p521" | "ecdsa-sha2-nistp521" => "ecdsa-sha2-nistp521".into(),
        "ed25519" | "ssh-ed25519" => "ssh-ed25519".into(),
        other => other.to_string(),
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
            backend: crate::db::ssh_keys::KeyBackend::Software,
            pkcs11_uri: None,
            pkcs11_module_path: None,
            pkcs11_token_serial: None,
            pkcs11_object_id: None,
            pkcs11_object_label: None,
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: None,
            tpm_pin_required: false,
            cng_key_name: None,
            keystore_alias: None,
            keystore_strongbox: false,
            keystore_user_auth_required: false,
            keystore_platform: None,
        }
    }

    fn row_fido2_no_creds() -> SshKeyRow {
        SshKeyRow {
            credential_id: Some(vec![1, 2, 3]),
            application_string: Some("ssh:".into()),
            key_type: "sk-ssh-ed25519@openssh.com".into(),
            backend: crate::db::ssh_keys::KeyBackend::Fido2,
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

    #[test]
    fn from_row_resolves_hello_when_backend_is_hello() {
        let row = SshKeyRow {
            backend: crate::db::ssh_keys::KeyBackend::Hello,
            key_type: "ecdsa-sha2-nistp256".into(),
            hello_credential_name: Some("letsflutssh-ssh-abc-1234".into()),
            ..row_software()
        };
        assert_eq!(BackendKind::from_row(&row), BackendKind::Hello);
    }

    #[test]
    fn from_row_resolves_keystore_when_backend_is_keystore() {
        let row = SshKeyRow {
            backend: crate::db::ssh_keys::KeyBackend::Keystore,
            key_type: "ecdsa-sha2-nistp256".into(),
            keystore_alias: Some("lfs-keystore-1234".into()),
            keystore_strongbox: true,
            keystore_user_auth_required: true,
            ..row_software()
        };
        assert_eq!(BackendKind::from_row(&row), BackendKind::Keystore);
    }

    #[tokio::test]
    async fn dispatch_keystore_on_desktop_surfaces_unsupported() {
        let row = SshKeyRow {
            backend: crate::db::ssh_keys::KeyBackend::Keystore,
            key_type: "ecdsa-sha2-nistp256".into(),
            keystore_alias: Some("lfs-keystore-1234".into()),
            keystore_strongbox: true,
            keystore_user_auth_required: true,
            ..row_software()
        };
        let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
        match err {
            BackendError::Signer(Error::Keystore(s)) => {
                assert!(s.contains("Android"), "expected Android note, got {s}");
            }
            other => panic!("expected BackendError::Signer(Error::Keystore), got {other:?}"),
        }
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
