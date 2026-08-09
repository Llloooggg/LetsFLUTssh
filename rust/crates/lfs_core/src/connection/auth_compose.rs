//! Credential-overlay composer for the connect cascade.
//!
//! Mirrors the precedence the Dart-era `_authFromConfig` walked:
//!
//! 1. **Session-staged path.** When `session_id` is set and the
//!    DB row carries credentials, stage them via
//!    [`crate::db::sessions::stage_secrets_into_store`] under the
//!    canonical `sess.<slot>.<id>` ids and return the matching
//!    `Pubkey`/`Password` ref. The staged ids belong to the
//!    session lifecycle (cleared on disconnect via the session
//!    store evict path); they are NOT transient.
//! 2. **Manager-key path.** When `key_id` is non-empty, stage
//!    the private PEM via
//!    [`crate::db::ssh_keys::stage_secret_into_store`] under
//!    `key.priv.<id>`. The typed `passphrase` is added as a
//!    transient secret keyed `key.passphrase.<id>` when the
//!    session itself didn't already stage one — passphrase is
//!    a per-connect value, not a per-key value, so it must not
//!    survive the connect handshake.
//! 3. **Quick-connect fallback.** Inline `key_data` / `password`
//!    / `passphrase` get copied once into the SecretStore under
//!    fresh `conn.<slot>.<uuid>` ids. Every id added here is a
//!    transient — the caller must drop them after the connect
//!    attempt reaches a terminal state (`Connected` /
//!    `Disconnected`) so plaintext bytes don't survive in the
//!    SecretStore beyond the dial.
//!
//! Plaintext discipline: the input strings (`key_data`,
//! `password`, `passphrase`) cross the FRB boundary once on the
//! quick-connect path; the staged paths read straight from
//! sqlite into the SecretStore and never round-trip back through
//! Dart.
//!
//! Empty-auth case (T0 / plaintext-tier dials). When every
//! credential slot is empty — no `session_id` with staged rows,
//! no `key_id`, no inline `key_data` / `password` / `passphrase`
//! — `prepare_auth` falls through to the empty-auth path: it
//! stages an empty-bytes blob under a fresh `conn.password.<uuid>`
//! transient and returns it as a [`PreparedAuthRef::Password`].
//! Funnelling the zero-credential dial through the same
//! Ref/SecretStore shape as every other path keeps russh from
//! seeing an alternate "no credentials" code branch through the
//! bus; russh surfaces "no credentials" naturally when the server
//! rejects the empty password. The transient is cleared by the
//! same terminal-state cleanup that drops the non-empty quick-
//! connect ids.

use crate::db::{sessions, ssh_key_certificates, ssh_keys};
use crate::error::Error;

/// Inputs to [`prepare_auth`]. All fields are optional / can be
/// empty — the function walks them in precedence order and picks
/// the first viable path.
#[derive(Debug, Clone, Default)]
pub struct PrepareAuthInput {
    /// DB session id when the user is connecting to a saved
    /// session. `None` for quick-connect.
    pub session_id: Option<String>,
    /// Manager-key id when the session references a key from the
    /// `ssh_keys` table. Empty string = no manager key linked.
    pub key_id: String,
    /// Inline PEM the user pasted into the quick-connect dialog
    /// or the per-session override. Empty when only a manager
    /// key is in play.
    pub key_data: String,
    /// Inline password the user typed for this connect attempt.
    /// Empty when only a manager key / saved session is in play.
    pub password: String,
    /// Inline passphrase the user typed for this connect attempt.
    /// Used to unlock either the inline `key_data` or the
    /// manager-key PEM.
    pub passphrase: String,
    /// FIDO2 PIN the user typed for this connect attempt. Forwarded
    /// to the CTAP2 layer when the resolved manager key is hardware-
    /// bound (`sk-*`) and carries the user-verification bit. Empty
    /// for touch-only credentials and for every non-sk-* path.
    pub pin: String,
}

/// Typed ref returned by [`prepare_auth`]. Mirrors the Dart-era
/// `SshAuthPasswordRef` / `SshAuthPubkeyRef` / `SshAuthPubkeyCertRef`
/// family case-for-case. `PubkeyCert` is selected ahead of `Pubkey`
/// whenever the manager-key path resolves a cert pairing for the
/// referenced `key_id` — the cert is the strictly stronger
/// credential (CA-signed) so picking the bare pubkey when a cert is
/// available would force the user to re-authenticate every time the
/// short-lived cert rotates server-side.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PreparedAuthRef {
    Password {
        secret_id: String,
    },
    Pubkey {
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    PubkeyCert {
        key_secret_id: String,
        cert_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    /// FIDO2 hardware-bound `sk-*` SSH key resolved from the manager.
    /// `public_openssh` is the captured `id_*.pub` body the connect
    /// path re-parses to recover the SSH `Algorithm`. Together with
    /// `credential_id` and `application`, this is the metadata the
    /// device matches against on every CTAP2 getAssertion.
    ///
    /// `has_user_verification` drives the touch-only vs PIN UX: when
    /// `true`, the Dart caller stages a PIN under `pin_secret_id`
    /// before the dispatch so the Rust connect path can read it
    /// without a re-prompt; when `false`, `pin_secret_id` is `None`
    /// and the device accepts a touch-only assertion.
    PubkeySk {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        has_user_verification: bool,
        pin_secret_id: Option<String>,
    },
    /// FIDO2 hardware-bound `sk-*` SSH key AND a paired OpenSSH
    /// certificate. Selected ahead of [`PreparedAuthRef::PubkeySk`]
    /// whenever the manager-key row resolves a cert pairing — the
    /// cert is the strictly stronger credential (CA-signed) so
    /// picking the bare sk-* path when a cert is available would
    /// force re-certification on every short-lived cert rotation.
    /// Mirrors the same precedence rule the software path enforces
    /// between [`PreparedAuthRef::PubkeyCert`] and
    /// [`PreparedAuthRef::Pubkey`].
    ///
    /// `cert_secret_id` points at the staged cert blob (same
    /// `key.cert.<key_id>` namespace the software path uses). The
    /// FIDO2 metadata block matches the bare sk-* variant: the
    /// device signs every userauth round trip; private key material
    /// never crosses the FRB boundary.
    PubkeySkCert {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        has_user_verification: bool,
        cert_secret_id: String,
        pin_secret_id: Option<String>,
    },
    /// PKCS#11 hardware-token key resolved from the manager.
    /// `module_path` + `token_serial` + `cka_id` carry the
    /// disambiguation surface the sign path needs at runtime;
    /// `pin_secret_id` points at a staged transient PIN entry the
    /// Dart caller seeded before dispatch (None for
    /// protected-authentication-path / no-login tokens).
    PubkeyPkcs11 {
        public_openssh: String,
        module_path: String,
        token_serial: String,
        cka_id: Vec<u8>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Apple Secure Enclave SSH key resolved from the manager.
    /// `application_tag` is the opaque `kSecAttrApplicationTag`
    /// bytes captured at create time and persisted on
    /// `ssh_keys.enclave_tag`. No PIN slot — the OS handles the
    /// biometric / passcode prompt inside `SecKeyCreateSignature`.
    PubkeyEnclave {
        public_openssh: String,
        application_tag: Vec<u8>,
    },
    /// Windows Hello (NCrypt / Microsoft Platform Crypto Provider)
    /// SSH key resolved from the manager. `credential_name` is the
    /// CNG persistent-key name captured at create time and persisted
    /// on `ssh_keys.hello_credential_name`. `key_type` drives the
    /// SSH wire-name selection (`ecdsa-sha2-nistp256` /
    /// `ecdsa-sha2-nistp384` / `rsa-2048`). No PIN slot — the Hello
    /// prompt (PIN / fingerprint / face) fires at the OS layer
    /// inside `NCryptSignHash` per the UI policy chosen at create
    /// time.
    PubkeyHello {
        public_openssh: String,
        credential_name: String,
        key_type: String,
    },
    /// TPM 2.0-bound SSH key resolved from the manager. Carries
    /// the provider discriminator + the matching storage ingredient
    /// (`blob` for `tss-esapi`, `cng_key_name` for `cng-pcp`) +
    /// the per-sign PIN-secret id for PIN-bound keys.
    PubkeyTpm {
        public_openssh: String,
        provider: String,
        blob: Option<Vec<u8>>,
        cng_key_name: Option<String>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Android Hardware Keystore / StrongBox SSH key resolved from
    /// the manager. `keystore_alias` is the AndroidKeyStore alias
    /// captured at create time and persisted on
    /// `ssh_keys.keystore_alias`. `key_type` drives the SSH wire-name
    /// selection (`ecdsa-sha2-nistp256` / `ssh-ed25519` / `rsa-2048`).
    /// No PIN slot — the per-op authorisation hops through
    /// `BiometricPrompt.CryptoObject` at the OS layer inside the
    /// signer (`UserNotAuthenticatedException` on the bare
    /// `Signature.initSign` triggers the prompt).
    PubkeyKeystore {
        public_openssh: String,
        keystore_alias: String,
        key_type: String,
    },
}

/// Aggregated output. `auth` carries the ref the connect actor
/// dispatches against; `transient_secret_ids` lists every store
/// entry the caller must drop after the connect attempt reaches
/// a terminal state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedAuth {
    pub auth: PreparedAuthRef,
    pub transient_secret_ids: Vec<String>,
}

/// Compose the auth ref + transient secret bookkeeping.
///
/// Errors: only the underlying sqlite errors from the staged
/// paths surface here. A missing row / empty column is not an
/// error — it falls through to the next precedence level. The
/// quick-connect fallback always succeeds (an empty-auth dial
/// stages an empty password under a transient id so russh
/// receives a Ref-shaped variant).
pub fn prepare_auth(
    conn: &impl crate::db::DbAccess,
    input: &PrepareAuthInput,
) -> Result<PreparedAuth, Error> {
    let mut transients: Vec<String> = Vec::new();
    let mut session_passphrase_id: Option<String> = None;

    if let Some(prepared) =
        try_saved_session(conn, input, &mut transients, &mut session_passphrase_id)?
    {
        return Ok(prepared);
    }
    if let Some(prepared) = try_manager_key(conn, input, &mut transients, &session_passphrase_id)? {
        return Ok(prepared);
    }
    Ok(quick_connect_fallback(
        input,
        transients,
        session_passphrase_id,
    ))
}

/// Precedence 1 — saved-session secrets staged into the store. Sets
/// `session_passphrase_id` for downstream paths even when it falls
/// through (no key / password staged).
fn try_saved_session(
    conn: &impl crate::db::DbAccess,
    input: &PrepareAuthInput,
    transients: &mut Vec<String>,
    session_passphrase_id: &mut Option<String>,
) -> Result<Option<PreparedAuth>, Error> {
    let Some(session_id) = &input.session_id else {
        return Ok(None);
    };
    let Some(staged) = sessions::stage_secrets_into_store(conn, session_id)? else {
        return Ok(None);
    };
    if staged.has_passphrase {
        *session_passphrase_id = Some(format!("sess.passphrase.{session_id}"));
    }
    if staged.has_key_data {
        return Ok(Some(PreparedAuth {
            auth: PreparedAuthRef::Pubkey {
                key_secret_id: format!("sess.key.{session_id}"),
                passphrase_secret_id: session_passphrase_id.clone(),
            },
            transient_secret_ids: std::mem::take(transients),
        }));
    }
    if staged.has_password {
        return Ok(Some(PreparedAuth {
            auth: PreparedAuthRef::Password {
                secret_id: format!("sess.password.{session_id}"),
            },
            transient_secret_ids: std::mem::take(transients),
        }));
    }
    Ok(None)
}

/// Precedence 2 — manager-key path. Hardware backends
/// (Enclave / Hello / TPM / Keystore / PKCS#11) short-circuit ahead
/// of the FIDO2 `sk-*` and software-pubkey paths because their
/// `private_key` column is empty by design. Cert-paired variants are
/// picked over the plain pubkey: the CA-signed cert is strictly
/// stronger. Returns None to fall through to the quick-connect path.
fn try_manager_key(
    conn: &impl crate::db::DbAccess,
    input: &PrepareAuthInput,
    transients: &mut Vec<String>,
    session_passphrase_id: &Option<String>,
) -> Result<Option<PreparedAuth>, Error> {
    if input.key_id.is_empty() {
        return Ok(None);
    }
    let Some(row) = ssh_keys::get(conn, &input.key_id)? else {
        return Ok(None);
    };

    let hardware_ref = match row.backend {
        ssh_keys::KeyBackend::Enclave => Some(enclave_ref(&row)?),
        ssh_keys::KeyBackend::Hello => Some(hello_ref(&row)?),
        ssh_keys::KeyBackend::Tpm => Some(tpm_ref(&row, input, transients)?),
        ssh_keys::KeyBackend::Keystore => Some(keystore_ref(&row)?),
        ssh_keys::KeyBackend::Pkcs11 => Some(pkcs11_ref(&row, input, transients)?),
        _ => None,
    };
    if let Some(auth) = hardware_ref {
        return Ok(Some(PreparedAuth {
            auth,
            transient_secret_ids: std::mem::take(transients),
        }));
    }

    if let (Some(credential_id), Some(application)) = (&row.credential_id, &row.application_string)
    {
        let auth = sk_ref(conn, input, &row, credential_id, application, transients)?;
        return Ok(Some(PreparedAuth {
            auth,
            transient_secret_ids: std::mem::take(transients),
        }));
    }

    software_pubkey_auth(conn, input, transients, session_passphrase_id)
}

// Apple Secure Enclave — `private_key` is empty (on-chip); the OS
// handles its own prompt inside SecKeyCreateSignature, so no Dart-
// side PIN pre-staging.
fn enclave_ref(row: &ssh_keys::SshKeyRow) -> Result<PreparedAuthRef, Error> {
    let application_tag = row
        .enclave_tag
        .clone()
        .ok_or_else(|| Error::Auth("enclave row missing enclave_tag".into()))?;
    Ok(PreparedAuthRef::PubkeyEnclave {
        public_openssh: row.public_key.clone(),
        application_tag,
    })
}

// Windows Hello — `private_key` is empty (TPM-bound); the Hello
// prompt fires inside `NCryptSignHash` at the OS layer.
fn hello_ref(row: &ssh_keys::SshKeyRow) -> Result<PreparedAuthRef, Error> {
    let credential_name = row
        .hello_credential_name
        .clone()
        .ok_or_else(|| Error::Auth("hello row missing hello_credential_name".into()))?;
    Ok(PreparedAuthRef::PubkeyHello {
        public_openssh: row.public_key.clone(),
        credential_name,
        key_type: row.key_type.clone(),
    })
}

// TPM 2.0 — the connect path reaches the wrapped blob (`tss-esapi`)
// or CNG name (`cng-pcp`) and signs through
// `Session::connect_pubkey_tpm_owned`. PIN-bound rows stage the PIN
// under `tpm.pin.<key_id>` so the signer resolves it without crossing
// FRB on every sign.
fn tpm_ref(
    row: &ssh_keys::SshKeyRow,
    input: &PrepareAuthInput,
    transients: &mut Vec<String>,
) -> Result<PreparedAuthRef, Error> {
    let provider = row
        .tpm_provider
        .clone()
        .ok_or_else(|| Error::Auth("tpm row missing tpm_provider".into()))?;
    let pin_secret_id = if row.tpm_pin_required && !input.pin.is_empty() {
        Some(stage_pin(transients, "tpm.pin", &input.key_id, &input.pin))
    } else {
        None
    };
    Ok(PreparedAuthRef::PubkeyTpm {
        public_openssh: row.public_key.clone(),
        provider,
        blob: row.tpm_blob.clone(),
        cng_key_name: row.cng_key_name.clone(),
        key_type: row.key_type.clone(),
        pin_secret_id,
    })
}

// Android Hardware Keystore — `private_key` is empty (the
// AndroidKeyStore holds the key); every sign hops through
// `Session::connect_pubkey_keystore_owned`, which fires
// `BiometricPrompt.CryptoObject` for the per-op auth.
fn keystore_ref(row: &ssh_keys::SshKeyRow) -> Result<PreparedAuthRef, Error> {
    let keystore_alias = row
        .keystore_alias
        .clone()
        .ok_or_else(|| Error::Auth("keystore row missing keystore_alias".into()))?;
    Ok(PreparedAuthRef::PubkeyKeystore {
        public_openssh: row.public_key.clone(),
        keystore_alias,
        key_type: row.key_type.clone(),
    })
}

// PKCS#11 — `private_key` is empty (hardware-bound); falling through
// would try to stage zero bytes for the connect.
fn pkcs11_ref(
    row: &ssh_keys::SshKeyRow,
    input: &PrepareAuthInput,
    transients: &mut Vec<String>,
) -> Result<PreparedAuthRef, Error> {
    let module_path = row
        .pkcs11_module_path
        .clone()
        .ok_or_else(|| Error::Auth("pkcs11 row missing module_path".into()))?;
    let token_serial = row
        .pkcs11_token_serial
        .clone()
        .ok_or_else(|| Error::Auth("pkcs11 row missing token_serial".into()))?;
    let cka_id = row
        .pkcs11_object_id
        .clone()
        .ok_or_else(|| Error::Auth("pkcs11 row missing object_id".into()))?;
    let pin_secret_id = if !input.pin.is_empty() {
        Some(stage_pin(
            transients,
            "pkcs11.pin",
            &input.key_id,
            &input.pin,
        ))
    } else {
        None
    };
    Ok(PreparedAuthRef::PubkeyPkcs11 {
        public_openssh: row.public_key.clone(),
        module_path,
        token_serial,
        cka_id,
        key_type: row.key_type.clone(),
        pin_secret_id,
    })
}

// FIDO2 `sk-*` row. `public_key` carries the captured `id_*.pub`
// body the connect path re-parses to recover the SSH `Algorithm`.
// PIN staging is transient under `key.pin.<id>`. A paired cert wins
// over the plain credential — the CA-signed credential is stronger.
fn sk_ref(
    conn: &impl crate::db::DbAccess,
    input: &PrepareAuthInput,
    row: &ssh_keys::SshKeyRow,
    credential_id: &[u8],
    application: &str,
    transients: &mut Vec<String>,
) -> Result<PreparedAuthRef, Error> {
    let pin_secret_id = if row.has_user_verification && !input.pin.is_empty() {
        Some(stage_pin(transients, "key.pin", &input.key_id, &input.pin))
    } else {
        None
    };
    if ssh_key_certificates::stage_secret_into_store(conn, &input.key_id)? {
        return Ok(PreparedAuthRef::PubkeySkCert {
            public_openssh: row.public_key.clone(),
            credential_id: credential_id.to_vec(),
            application: application.to_string(),
            has_user_verification: row.has_user_verification,
            cert_secret_id: ssh_key_certificates::certificate_secret_id(&input.key_id),
            pin_secret_id,
        });
    }
    Ok(PreparedAuthRef::PubkeySk {
        public_openssh: row.public_key.clone(),
        credential_id: credential_id.to_vec(),
        application: application.to_string(),
        has_user_verification: row.has_user_verification,
        pin_secret_id,
    })
}

// Software pubkey — stages the private-key bytes (and passphrase, if
// not already carried from the session). Returns None when no key
// bytes stage, so the caller falls through to quick-connect.
fn software_pubkey_auth(
    conn: &impl crate::db::DbAccess,
    input: &PrepareAuthInput,
    transients: &mut Vec<String>,
    session_passphrase_id: &Option<String>,
) -> Result<Option<PreparedAuth>, Error> {
    if !ssh_keys::stage_secret_into_store(conn, &input.key_id)? {
        return Ok(None);
    }
    let mut passphrase_secret_id = session_passphrase_id.clone();
    if !input.passphrase.is_empty() && passphrase_secret_id.is_none() {
        let id = format!("key.passphrase.{}", input.key_id);
        crate::app::instance()
            .secrets
            .put(&id, input.passphrase.as_bytes());
        transients.push(id.clone());
        passphrase_secret_id = Some(id);
    }
    let key_secret_id = format!("key.priv.{}", input.key_id);
    let auth = if ssh_key_certificates::stage_secret_into_store(conn, &input.key_id)? {
        PreparedAuthRef::PubkeyCert {
            key_secret_id,
            cert_secret_id: ssh_key_certificates::certificate_secret_id(&input.key_id),
            passphrase_secret_id,
        }
    } else {
        PreparedAuthRef::Pubkey {
            key_secret_id,
            passphrase_secret_id,
        }
    };
    Ok(Some(PreparedAuth {
        auth,
        transient_secret_ids: std::mem::take(transients),
    }))
}

// Precedence 3 — quick-connect fallback. Every id under `conn.*` is
// transient; the caller drops them after the dial settles. Empty
// auth still stages an empty password so the actor receives a
// Ref-shaped variant — russh surfaces "no credentials" naturally and
// no alternate plaintext code path leaks through the bus.
fn quick_connect_fallback(
    input: &PrepareAuthInput,
    mut transients: Vec<String>,
    session_passphrase_id: Option<String>,
) -> PreparedAuth {
    let transient_id = crate::id::random_handle_hex_32();
    let store = &crate::app::instance().secrets;

    if !input.key_data.is_empty() {
        let key_secret_id = format!("conn.key.{transient_id}");
        store.put(&key_secret_id, input.key_data.as_bytes());
        transients.push(key_secret_id.clone());
        let mut passphrase_secret_id = session_passphrase_id;
        if !input.passphrase.is_empty() && passphrase_secret_id.is_none() {
            let id = format!("conn.passphrase.{transient_id}");
            store.put(&id, input.passphrase.as_bytes());
            transients.push(id.clone());
            passphrase_secret_id = Some(id);
        }
        return PreparedAuth {
            auth: PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            transient_secret_ids: transients,
        };
    }

    if !input.password.is_empty() {
        let id = format!("conn.password.{transient_id}");
        store.put(&id, input.password.as_bytes());
        transients.push(id.clone());
        return PreparedAuth {
            auth: PreparedAuthRef::Password { secret_id: id },
            transient_secret_ids: transients,
        };
    }

    let id = format!("conn.password.{transient_id}");
    store.put(&id, b"");
    transients.push(id.clone());
    PreparedAuth {
        auth: PreparedAuthRef::Password { secret_id: id },
        transient_secret_ids: transients,
    }
}

/// Stage a PIN under `<prefix>.<key_id>` in the secret store, record
/// it as transient, and return the id. Shared by the TPM / PKCS#11 /
/// `sk-*` paths, which differ only in the id prefix.
fn stage_pin(transients: &mut Vec<String>, prefix: &str, key_id: &str, pin: &str) -> String {
    let id = format!("{prefix}.{key_id}");
    crate::app::instance().secrets.put(&id, pin.as_bytes());
    transients.push(id.clone());
    id
}
#[cfg(test)]
#[path = "../../tests/unit/connection_auth_compose.rs"]
mod tests;
