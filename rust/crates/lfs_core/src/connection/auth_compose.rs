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

    // 1. Saved-session path.
    if let Some(session_id) = &input.session_id {
        if let Some(staged) = sessions::stage_secrets_into_store(conn, session_id)? {
            if staged.has_passphrase {
                session_passphrase_id = Some(format!("sess.passphrase.{session_id}"));
            }
            if staged.has_key_data {
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::Pubkey {
                        key_secret_id: format!("sess.key.{session_id}"),
                        passphrase_secret_id: session_passphrase_id,
                    },
                    transient_secret_ids: transients,
                });
            }
            if staged.has_password {
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::Password {
                        secret_id: format!("sess.password.{session_id}"),
                    },
                    transient_secret_ids: transients,
                });
            }
        }
    }

    // 2. Manager-key path. Three sub-paths in precedence order:
    //    a) FIDO2 hardware-bound `sk-*` key — `credential_id IS NOT
    //       NULL` on the row. The PEM is the SSH wire-format public
    //       key body, not a usable private key, so this branch
    //       short-circuits ahead of any private-key staging.
    //    b) cert-paired software key — the cert is strictly stronger
    //       (CA-signed) than the plain pubkey it pairs with.
    //    c) plain software pubkey.
    if !input.key_id.is_empty() {
        if let Some(row) = ssh_keys::get(conn, &input.key_id)? {
            // Apple Secure Enclave sub-branch — takes precedence
            // over every software-key path because the row's
            // `private_key` column is empty by design (on-chip)
            // and the OS handles its own auth prompt inside
            // SecKeyCreateSignature; no Dart-side PIN dialog
            // pre-staging is needed.
            if row.backend == ssh_keys::KeyBackend::Enclave {
                let application_tag = row
                    .enclave_tag
                    .clone()
                    .ok_or_else(|| Error::Auth("enclave row missing enclave_tag".into()))?;
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeyEnclave {
                        public_openssh: row.public_key.clone(),
                        application_tag,
                    },
                    transient_secret_ids: transients,
                });
            }
            // Windows Hello sub-branch — same shape as the Enclave
            // arm above: row's `private_key` column is empty by
            // design (TPM-bound) and the Hello prompt fires inside
            // `NCryptSignHash` at the OS layer, no Dart-side PIN
            // pre-staging.
            if row.backend == ssh_keys::KeyBackend::Hello {
                let credential_name = row
                    .hello_credential_name
                    .clone()
                    .ok_or_else(|| Error::Auth("hello row missing hello_credential_name".into()))?;
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeyHello {
                        public_openssh: row.public_key.clone(),
                        credential_name,
                        key_type: row.key_type.clone(),
                    },
                    transient_secret_ids: transients,
                });
            }
            // TPM 2.0 sub-branch — `private_key` is empty by design;
            // the connect path reaches the wrapped blob bytes
            // (`tss-esapi`) or CNG name (`cng-pcp`) via the
            // PreparedAuthRef and signs through
            // `Session::connect_pubkey_tpm_owned`. PIN-bound rows
            // stage the PIN under `tpm.pin.<key_id>` so the signer
            // resolves it without crossing FRB on every sign.
            if row.backend == ssh_keys::KeyBackend::Tpm {
                let provider = row
                    .tpm_provider
                    .clone()
                    .ok_or_else(|| Error::Auth("tpm row missing tpm_provider".into()))?;
                let pin_secret_id = if row.tpm_pin_required && !input.pin.is_empty() {
                    let id = format!("tpm.pin.{}", input.key_id);
                    crate::app::instance()
                        .secrets
                        .put(&id, input.pin.as_bytes());
                    transients.push(id.clone());
                    Some(id)
                } else {
                    None
                };
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeyTpm {
                        public_openssh: row.public_key.clone(),
                        provider,
                        blob: row.tpm_blob.clone(),
                        cng_key_name: row.cng_key_name.clone(),
                        key_type: row.key_type.clone(),
                        pin_secret_id,
                    },
                    transient_secret_ids: transients,
                });
            }
            // Android Hardware Keystore sub-branch — `private_key` is
            // empty by design (the AndroidKeyStore holds the key);
            // every sign hops through
            // `Session::connect_pubkey_keystore_owned` which fires
            // `BiometricPrompt.CryptoObject` for the per-op auth.
            // No Dart-side PIN staging — the OS handles its own
            // biometric / device-unlock prompt inside the signer.
            if row.backend == ssh_keys::KeyBackend::Keystore {
                let keystore_alias = row
                    .keystore_alias
                    .clone()
                    .ok_or_else(|| Error::Auth("keystore row missing keystore_alias".into()))?;
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeyKeystore {
                        public_openssh: row.public_key.clone(),
                        keystore_alias,
                        key_type: row.key_type.clone(),
                    },
                    transient_secret_ids: transients,
                });
            }
            // PKCS#11 sub-branch — the row's `backend = 'pkcs11'`
            // takes precedence over the FIDO2 / cert / plain-pubkey
            // branches because the `private_key` column is empty
            // by design (hardware-bound) and falling through would
            // try to stage zero bytes for the connect.
            if row.backend == ssh_keys::KeyBackend::Pkcs11 {
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
                    let id = format!("pkcs11.pin.{}", input.key_id);
                    crate::app::instance()
                        .secrets
                        .put(&id, input.pin.as_bytes());
                    transients.push(id.clone());
                    Some(id)
                } else {
                    None
                };
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeyPkcs11 {
                        public_openssh: row.public_key.clone(),
                        module_path,
                        token_serial,
                        cka_id,
                        key_type: row.key_type.clone(),
                        pin_secret_id,
                    },
                    transient_secret_ids: transients,
                });
            }
            if let (Some(credential_id), Some(application)) =
                (&row.credential_id, &row.application_string)
            {
                // sk-* row. `public_key` carries the captured
                // `id_*.pub` body the connect path re-parses to
                // recover the SSH `Algorithm`. PIN staging is
                // transient under `key.pin.<id>` so the bytes do
                // not survive the connect handshake. Cert pairing
                // gets the same precedence treatment as the
                // software path — when a cert is attached the
                // composer picks the cert-bearing variant so the
                // user authenticates with the strictly stronger
                // CA-signed credential.
                let pin_secret_id = if row.has_user_verification && !input.pin.is_empty() {
                    let id = format!("key.pin.{}", input.key_id);
                    crate::app::instance()
                        .secrets
                        .put(&id, input.pin.as_bytes());
                    transients.push(id.clone());
                    Some(id)
                } else {
                    None
                };
                if ssh_key_certificates::stage_secret_into_store(conn, &input.key_id)? {
                    return Ok(PreparedAuth {
                        auth: PreparedAuthRef::PubkeySkCert {
                            public_openssh: row.public_key.clone(),
                            credential_id: credential_id.clone(),
                            application: application.clone(),
                            has_user_verification: row.has_user_verification,
                            cert_secret_id: ssh_key_certificates::certificate_secret_id(
                                &input.key_id,
                            ),
                            pin_secret_id,
                        },
                        transient_secret_ids: transients,
                    });
                }
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::PubkeySk {
                        public_openssh: row.public_key.clone(),
                        credential_id: credential_id.clone(),
                        application: application.clone(),
                        has_user_verification: row.has_user_verification,
                        pin_secret_id,
                    },
                    transient_secret_ids: transients,
                });
            }
            if ssh_keys::stage_secret_into_store(conn, &input.key_id)? {
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
                if ssh_key_certificates::stage_secret_into_store(conn, &input.key_id)? {
                    return Ok(PreparedAuth {
                        auth: PreparedAuthRef::PubkeyCert {
                            key_secret_id,
                            cert_secret_id: ssh_key_certificates::certificate_secret_id(
                                &input.key_id,
                            ),
                            passphrase_secret_id,
                        },
                        transient_secret_ids: transients,
                    });
                }
                return Ok(PreparedAuth {
                    auth: PreparedAuthRef::Pubkey {
                        key_secret_id,
                        passphrase_secret_id,
                    },
                    transient_secret_ids: transients,
                });
            }
        }
    }

    // 3. Quick-connect fallback. Every id under `conn.*` is
    //    transient — caller drops them after the dial settles.
    let transient_id = crate::id::random_handle_hex_32();
    let store = &crate::app::instance().secrets;

    if !input.key_data.is_empty() {
        let key_secret_id = format!("conn.key.{transient_id}");
        store.put(&key_secret_id, input.key_data.as_bytes());
        transients.push(key_secret_id.clone());
        let mut passphrase_secret_id = session_passphrase_id.clone();
        if !input.passphrase.is_empty() && passphrase_secret_id.is_none() {
            let id = format!("conn.passphrase.{transient_id}");
            store.put(&id, input.passphrase.as_bytes());
            transients.push(id.clone());
            passphrase_secret_id = Some(id);
        }
        return Ok(PreparedAuth {
            auth: PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            transient_secret_ids: transients,
        });
    }

    if !input.password.is_empty() {
        let id = format!("conn.password.{transient_id}");
        store.put(&id, input.password.as_bytes());
        transients.push(id.clone());
        return Ok(PreparedAuth {
            auth: PreparedAuthRef::Password { secret_id: id },
            transient_secret_ids: transients,
        });
    }

    // Empty auth — stage an empty password as a transient so the
    // actor still receives a Ref-shaped variant. russh surfaces
    // "no credentials" naturally; pushing the bytes via SecretStore
    // avoids leaking an alternate plaintext code path through the
    // bus.
    let id = format!("conn.password.{transient_id}");
    store.put(&id, b"");
    transients.push(id.clone());
    Ok(PreparedAuth {
        auth: PreparedAuthRef::Password { secret_id: id },
        transient_secret_ids: transients,
    })
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
        conn.raw()
            .execute(
                "INSERT INTO sessions (\
                id, label, host, port, user, auth_type, password, key_data, \
                passphrase, key_path, key_id, sort_order, created_at, updated_at, \
                notes, extras\
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, \
                       ?14, ?15, ?16)",
                rusqlite::params![
                    id,
                    "label",
                    "host",
                    22_i64,
                    "user",
                    "password",
                    password,
                    key_data,
                    passphrase,
                    "",
                    Option::<String>::None,
                    0_i64,
                    0_i64,
                    0_i64,
                    "",
                    "",
                ],
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
