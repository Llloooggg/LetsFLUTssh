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
mod tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn fresh_db() -> Db {
        let conn = crate::db::Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn insert_session(
        conn: &impl crate::db::DbAccess,
        id: &str,
        password: &str,
        key_data: &str,
        passphrase: &str,
    ) {
        // Slim `sessions` row first — the v16 schema split moved
        // the SSH credential columns onto `ssh_session_details`.
        conn.raw()
            .execute(
                "INSERT INTO sessions (id, label, kind, sort_order, notes, extras, \
                 created_at, updated_at) VALUES (?1, ?2, 'ssh', 0, '', '', 0, 0)",
                rusqlite::params![id, "label"],
            )
            .unwrap();
        // SSH-specific join row carries host / user / auth_type +
        // the credential triplet the prepare_auth path reads back.
        conn.raw()
            .execute(
                "INSERT INTO ssh_session_details (\
                   session_id, host, port, user, auth_type, password, key_path, \
                   key_data, key_id, passphrase, updated_at\
                 ) VALUES (?1, 'host', 22, 'user', 'password', ?2, '', ?3, NULL, ?4, 0)",
                rusqlite::params![id, password, key_data, passphrase],
            )
            .unwrap();
    }

    fn insert_key(conn: &impl crate::db::DbAccess, id: &str, pem: &str) {
        conn.raw()
            .execute(
                "INSERT INTO ssh_keys (\
                id, label, private_key, public_key, key_type, created_at\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![id, "label", pem, "", "ed25519", 0_i64],
            )
            .unwrap();
    }

    #[test]
    fn quick_connect_with_password_stages_transient() {
        let db = fresh_db();
        db.with_conn(|c| {
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    password: "hunter2".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            assert!(matches!(r.auth, PreparedAuthRef::Password { .. }));
            // The transient id must match the secret id in the ref.
            let PreparedAuthRef::Password { secret_id } = r.auth else {
                unreachable!()
            };
            assert_eq!(r.transient_secret_ids.len(), 1);
            assert_eq!(r.transient_secret_ids[0], secret_id);
            assert!(secret_id.starts_with("conn.password."));
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn quick_connect_with_inline_key_and_passphrase_stages_two_transients() {
        let db = fresh_db();
        db.with_conn(|c| {
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_data: "PEM".into(),
                    passphrase: "phrase".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } = r.auth
            else {
                panic!("expected Pubkey");
            };
            assert!(key_secret_id.starts_with("conn.key."));
            let pp_id = passphrase_secret_id.expect("passphrase id");
            assert!(pp_id.starts_with("conn.passphrase."));
            assert_eq!(r.transient_secret_ids.len(), 2);
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn quick_connect_empty_stages_empty_password_transient() {
        // Empty-auth dial — the actor still gets a Ref-shaped
        // variant; russh surfaces "no credentials" naturally.
        let db = fresh_db();
        db.with_conn(|c| {
            let r = prepare_auth(c, &PrepareAuthInput::default()).unwrap();
            assert!(matches!(r.auth, PreparedAuthRef::Password { .. }));
            assert_eq!(r.transient_secret_ids.len(), 1);
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn saved_session_with_key_data_returns_pubkey_no_transients() {
        let db = fresh_db();
        db.with_conn(|c| {
            insert_session(c, "s1", "", "PEM", "phrase");
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    session_id: Some("s1".into()),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } = r.auth
            else {
                panic!("expected Pubkey");
            };
            assert_eq!(key_secret_id, "sess.key.s1");
            assert_eq!(passphrase_secret_id.as_deref(), Some("sess.passphrase.s1"));
            // Saved-session-staged ids belong to the session
            // lifecycle, not the connect cascade.
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn saved_session_with_password_returns_password_no_transients() {
        let db = fresh_db();
        db.with_conn(|c| {
            insert_session(c, "s2", "pw", "", "");
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    session_id: Some("s2".into()),
                    ..Default::default()
                },
            )
            .unwrap();
            assert!(matches!(
                r.auth,
                PreparedAuthRef::Password { ref secret_id } if secret_id == "sess.password.s2"
            ));
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_with_typed_passphrase_marks_passphrase_transient() {
        let db = fresh_db();
        db.with_conn(|c| {
            insert_key(c, "k1", "PEM");
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "k1".into(),
                    passphrase: "phrase".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } = r.auth
            else {
                panic!("expected Pubkey");
            };
            assert_eq!(key_secret_id, "key.priv.k1");
            assert_eq!(passphrase_secret_id.as_deref(), Some("key.passphrase.k1"));
            // The manager-key PEM is owned by the key lifecycle;
            // the typed passphrase is per-connect → transient.
            assert_eq!(
                r.transient_secret_ids,
                vec!["key.passphrase.k1".to_string()]
            );
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_without_typed_passphrase_no_transients() {
        let db = fresh_db();
        db.with_conn(|c| {
            insert_key(c, "k2", "PEM");
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "k2".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::Pubkey {
                passphrase_secret_id,
                ..
            } = r.auth
            else {
                panic!("expected Pubkey");
            };
            assert!(passphrase_secret_id.is_none());
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    fn insert_cert(conn: &impl crate::db::DbAccess, key_id: &str, blob: &[u8]) {
        conn.raw()
            .execute(
                "INSERT INTO ssh_key_certificates (\
                key_id, certificate, valid_after, valid_before, \
                principals, critical_options, fingerprint\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![key_id, blob, 0_i64, 0_i64, "[]", "{}", "SHA256:fp",],
            )
            .unwrap();
    }

    #[test]
    fn manager_key_with_paired_cert_returns_pubkey_cert_variant() {
        // The cert is the strictly stronger credential — when one
        // is paired to the key the composer must select it over the
        // plain pubkey path. Otherwise the user re-certifies on
        // every connect.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_key(c, "k1", "PEM");
            insert_cert(c, "k1", &[0xDE, 0xAD]);
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "k1".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            } = r.auth
            else {
                panic!("expected PubkeyCert");
            };
            assert_eq!(key_secret_id, "key.priv.k1");
            assert_eq!(cert_secret_id, "key.cert.k1");
            assert!(passphrase_secret_id.is_none());
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_without_paired_cert_keeps_returning_plain_pubkey() {
        // Sanity check that the cert lookup does not regress the
        // no-cert path. Same shape as
        // `manager_key_without_typed_passphrase_no_transients` but
        // covers the explicit ordering the new branch must preserve.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_key(c, "k1", "PEM");
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "k1".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            assert!(matches!(r.auth, PreparedAuthRef::Pubkey { .. }));
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    fn insert_sk_key(
        conn: &impl crate::db::DbAccess,
        id: &str,
        public_openssh: &str,
        credential_id: &[u8],
        application: &str,
        has_user_verification: bool,
    ) {
        conn.raw()
            .execute(
                "INSERT INTO ssh_keys (\
                id, label, private_key, public_key, key_type, created_at, \
                credential_id, application_string, has_user_verification\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                rusqlite::params![
                    id,
                    "sk-label",
                    "",
                    public_openssh,
                    "sk-ssh-ed25519@openssh.com",
                    0_i64,
                    credential_id,
                    application,
                    if has_user_verification { 1_i64 } else { 0_i64 },
                ],
            )
            .unwrap();
    }

    #[test]
    fn manager_key_with_credential_id_routes_to_pubkey_sk_variant() {
        // Hardware-bound row — composer must short-circuit ahead of
        // the plain-pubkey path. The captured `public_key` flows
        // through `public_openssh`; touch-only (no UV) skips PIN
        // staging.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_sk_key(
                c,
                "sk1",
                "sk-ssh-ed25519@openssh.com AAAA...",
                &[0xCA, 0xFE],
                "ssh:",
                false,
            );
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "sk1".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeySk {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                pin_secret_id,
            } = r.auth
            else {
                panic!("expected PubkeySk");
            };
            assert_eq!(public_openssh, "sk-ssh-ed25519@openssh.com AAAA...");
            assert_eq!(credential_id, vec![0xCA, 0xFE]);
            assert_eq!(application, "ssh:");
            assert!(!has_user_verification);
            assert!(pin_secret_id.is_none());
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_sk_with_user_verification_and_typed_pin_stages_transient() {
        // Hardware-bound row with UV bit set — composer stages the
        // typed PIN as `key.pin.<id>` transient and routes the id
        // through the ref so the Rust connect path can forward it
        // to the CTAP2 layer without a re-prompt.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_sk_key(
                c,
                "sk2",
                "sk-ssh-ed25519@openssh.com AAAA...",
                &[0xDE, 0xAD],
                "ssh:",
                true,
            );
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "sk2".into(),
                    pin: "123456".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeySk {
                has_user_verification,
                pin_secret_id,
                ..
            } = r.auth
            else {
                panic!("expected PubkeySk");
            };
            assert!(has_user_verification);
            assert_eq!(pin_secret_id.as_deref(), Some("key.pin.sk2"));
            assert_eq!(r.transient_secret_ids, vec!["key.pin.sk2".to_string()]);
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_sk_with_paired_cert_returns_pubkey_sk_cert_variant() {
        // Cert-paired hardware-bound row — composer must pick the
        // cert-bearing variant ahead of the bare sk-* path. Mirrors
        // the software-key precedence between PubkeyCert and Pubkey;
        // the cert is the strictly stronger credential because the
        // server's `TrustedUserCAKeys` carries the CA fingerprint.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_sk_key(
                c,
                "sk-cert",
                "sk-ssh-ed25519@openssh.com AAAA...",
                &[0xCA, 0xFE],
                "ssh:",
                false,
            );
            insert_cert(c, "sk-cert", &[0xDE, 0xAD, 0xBE, 0xEF]);
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "sk-cert".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeySkCert {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                cert_secret_id,
                pin_secret_id,
            } = r.auth
            else {
                panic!("expected PubkeySkCert");
            };
            assert_eq!(public_openssh, "sk-ssh-ed25519@openssh.com AAAA...");
            assert_eq!(credential_id, vec![0xCA, 0xFE]);
            assert_eq!(application, "ssh:");
            assert!(!has_user_verification);
            assert_eq!(cert_secret_id, "key.cert.sk-cert");
            assert!(pin_secret_id.is_none());
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_sk_with_paired_cert_and_uv_stages_pin_and_picks_cert_variant() {
        // UV bit set + cert paired — composer stages the PIN under
        // the transient `key.pin.<id>` namespace AND returns the
        // cert-bearing variant. PIN handling matches the bare sk-*
        // path; the cert selection matches the software cert path.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_sk_key(
                c,
                "sk-uv-cert",
                "sk-ssh-ed25519@openssh.com AAAA...",
                &[0x01],
                "ssh:",
                true,
            );
            insert_cert(c, "sk-uv-cert", &[0xDE, 0xAD]);
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "sk-uv-cert".into(),
                    pin: "123456".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeySkCert {
                has_user_verification,
                cert_secret_id,
                pin_secret_id,
                ..
            } = r.auth
            else {
                panic!("expected PubkeySkCert");
            };
            assert!(has_user_verification);
            assert_eq!(cert_secret_id, "key.cert.sk-uv-cert");
            assert_eq!(pin_secret_id.as_deref(), Some("key.pin.sk-uv-cert"));
            assert_eq!(
                r.transient_secret_ids,
                vec!["key.pin.sk-uv-cert".to_string()]
            );
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn manager_key_sk_with_user_verification_but_no_pin_drops_pin_id() {
        // UV bit set but the caller passed no PIN — the dispatcher
        // still proceeds. CTAP2 surfaces the missing-PIN error on
        // the device round trip; we don't pre-fail here so the
        // Rust connect path stays the only failure surface.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_sk_key(
                c,
                "sk3",
                "sk-ssh-ed25519@openssh.com AAAA...",
                &[0x01],
                "ssh:",
                true,
            );
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "sk3".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeySk { pin_secret_id, .. } = r.auth else {
                panic!("expected PubkeySk");
            };
            assert!(pin_secret_id.is_none());
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    fn insert_hello_key(
        conn: &impl crate::db::DbAccess,
        id: &str,
        public_openssh: &str,
        credential_name: &str,
        key_type: &str,
    ) {
        conn.raw()
            .execute(
                "INSERT INTO ssh_keys (\
                id, label, private_key, public_key, key_type, created_at, \
                backend, hello_credential_name\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    id,
                    "hello-label",
                    "",
                    public_openssh,
                    key_type,
                    0_i64,
                    "hello",
                    credential_name,
                ],
            )
            .unwrap();
    }

    #[test]
    fn manager_key_with_hello_backend_routes_to_pubkey_hello_variant() {
        // Hello-bound row — composer short-circuits ahead of the
        // every software / sk / pkcs11 / enclave branch. No PIN
        // surface — Windows fires the Hello prompt at the OS layer
        // inside `NCryptSignHash`.
        let db = fresh_db();
        db.with_conn(|c| {
            insert_hello_key(
                c,
                "hk1",
                "ecdsa-sha2-nistp256 AAAA...",
                "letsflutssh-ssh-abcdef-1234",
                "ecdsa-sha2-nistp256",
            );
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "hk1".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            let PreparedAuthRef::PubkeyHello {
                public_openssh,
                credential_name,
                key_type,
            } = r.auth
            else {
                panic!("expected PubkeyHello");
            };
            assert_eq!(public_openssh, "ecdsa-sha2-nistp256 AAAA...");
            assert_eq!(credential_name, "letsflutssh-ssh-abcdef-1234");
            assert_eq!(key_type, "ecdsa-sha2-nistp256");
            assert!(r.transient_secret_ids.is_empty());
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn hello_row_without_credential_name_surfaces_typed_auth_error() {
        // Defensive arm — DB corruption case where a `backend='hello'`
        // row landed without the CNG persistent-key name. The
        // composer must refuse rather than route the connect path
        // at an empty `NCryptOpenKey` lookup.
        let db = fresh_db();
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "INSERT INTO ssh_keys (\
                    id, label, private_key, public_key, key_type, created_at, \
                    backend\
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                    rusqlite::params![
                        "hk2",
                        "lab",
                        "",
                        "PUB",
                        "ecdsa-sha2-nistp256",
                        0_i64,
                        "hello"
                    ],
                )
                .unwrap();
            let err = prepare_auth(
                c,
                &PrepareAuthInput {
                    key_id: "hk2".into(),
                    ..Default::default()
                },
            )
            .unwrap_err();
            assert!(matches!(err, Error::Auth(_)));
            Ok::<(), Error>(())
        })
        .unwrap();
    }

    #[test]
    fn missing_session_falls_through_to_quick_connect() {
        let db = fresh_db();
        db.with_conn(|c| {
            // session_id set but the row doesn't exist — fall
            // through to quick-connect with the typed password.
            let r = prepare_auth(
                c,
                &PrepareAuthInput {
                    session_id: Some("ghost".into()),
                    password: "fallback".into(),
                    ..Default::default()
                },
            )
            .unwrap();
            assert!(matches!(r.auth, PreparedAuthRef::Password { .. }));
            assert_eq!(r.transient_secret_ids.len(), 1);
            Ok::<(), Error>(())
        })
        .unwrap();
    }
}
