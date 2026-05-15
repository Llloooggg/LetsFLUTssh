//! FRB adapter for `lfs_core::connection::auth_compose`. Exposes
//! the credential-overlay composer as a single async call the Dart
//! `ConnectionManager` drives.
//!
//! The Dart caller passes the (session_id, key_id, key_data,
//! password, passphrase) bag; the Rust composer walks the
//! precedence (saved-session staged → manager-key staged →
//! quick-connect inline), stages every byte into the
//! SecretStore under canonical ids, and returns the typed ref +
//! the list of transient ids the caller must drop after the
//! connect attempt reaches a terminal state.

use lfs_core::connection::auth_compose;

use super::db::run_db;

/// FRB mirror of `lfs_core::connection::auth_compose::PrepareAuthInput`.
#[derive(Debug, Clone)]
pub struct DbPrepareAuthInput {
    pub session_id: Option<String>,
    pub key_id: String,
    pub key_data: String,
    pub password: String,
    pub passphrase: String,
    /// FIDO2 PIN the user typed for this connect attempt — forwarded
    /// when the resolved manager key is hardware-bound (`sk-*`) and
    /// requires user verification. Empty for touch-only credentials
    /// and for every non-sk-* path.
    pub pin: String,
}

impl From<DbPrepareAuthInput> for auth_compose::PrepareAuthInput {
    fn from(d: DbPrepareAuthInput) -> Self {
        Self {
            session_id: d.session_id,
            key_id: d.key_id,
            key_data: d.key_data,
            password: d.password,
            passphrase: d.passphrase,
            pin: d.pin,
        }
    }
}

/// FRB-tagged enum mirroring `lfs_core::connection::auth_compose::PreparedAuthRef`.
/// FRB codegen emits a sealed Dart class with `_Password` /
/// `_Pubkey` / `_PubkeyCert` subclasses; the caller pattern-matches
/// instead of branching on a string discriminant.
#[derive(Debug, Clone)]
pub enum DbPreparedAuthRef {
    /// Password auth — `secret_id` points at the staged password.
    Password { secret_id: String },
    /// Pubkey auth — `key_secret_id` points at the staged private
    /// key PEM. `passphrase_secret_id` is `Some(id)` when a
    /// passphrase was staged alongside; `None` for unencrypted keys.
    Pubkey {
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    /// Pubkey + OpenSSH-certificate auth — `cert_secret_id` points
    /// at the staged cert blob paired with `key_secret_id`. Picked
    /// ahead of `Pubkey` whenever the manager key has a cert
    /// attached.
    PubkeyCert {
        key_secret_id: String,
        cert_secret_id: String,
        passphrase_secret_id: Option<String>,
    },
    /// FIDO2 hardware-bound `sk-*` SSH key resolved from the manager.
    /// Carries the captured `public_openssh` body + the opaque CTAP2
    /// credential id + the `application` RP-id. `has_user_verification`
    /// drives the Dart-side PIN-prompt UX; `pin_secret_id` resolves a
    /// transient staged PIN (`None` for touch-only).
    PubkeySk {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        has_user_verification: bool,
        pin_secret_id: Option<String>,
    },
    /// FIDO2 hardware-bound `sk-*` SSH key AND a paired OpenSSH
    /// certificate resolved from the manager. Picked ahead of
    /// `PubkeySk` whenever the resolved manager-key row has a cert
    /// attached — the cert is the strictly stronger credential
    /// (CA-signed), matching the precedence the software path
    /// already enforces between `PubkeyCert` and `Pubkey`.
    PubkeySkCert {
        public_openssh: String,
        credential_id: Vec<u8>,
        application: String,
        has_user_verification: bool,
        cert_secret_id: String,
        pin_secret_id: Option<String>,
    },
    /// PKCS#11 hardware-token key resolved from the manager. The Dart
    /// connect path routes this through the same dispatcher that
    /// shipped FIDO2; the surface mirrors the underlying
    /// `lfs_core::connection::ConnectAuthRef::PubkeyPkcs11` shape.
    PubkeyPkcs11 {
        public_openssh: String,
        module_path: String,
        token_serial: String,
        cka_id: Vec<u8>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Apple Secure Enclave hardware key. `application_tag` is the
    /// opaque `kSecAttrApplicationTag` bytes captured at create
    /// time; no PIN slot — the OS handles its own biometric /
    /// passcode prompt inside `SecKeyCreateSignature`.
    PubkeyEnclave {
        public_openssh: String,
        application_tag: Vec<u8>,
    },
    /// Windows Hello (NCrypt / Microsoft Platform Crypto Provider)
    /// hardware key. `credential_name` is the CNG persistent-key
    /// name captured at create time; no PIN slot — Hello fires at
    /// the OS layer inside `NCryptSignHash` per the UI policy chosen
    /// when the key landed.
    PubkeyHello {
        public_openssh: String,
        credential_name: String,
        key_type: String,
    },
    /// TPM 2.0-bound hardware key. `provider` discriminates the
    /// Linux ESAPI driver (`"tss-esapi"` + `blob` populated) from
    /// the Windows PCP silent variant (`"cng-pcp"` + `cng_key_name`
    /// populated); `pin_secret_id` carries the staged transient PIN
    /// for PIN-bound rows, `None` for empty-auth keys.
    PubkeyTpm {
        public_openssh: String,
        provider: String,
        blob: Option<Vec<u8>>,
        cng_key_name: Option<String>,
        key_type: String,
        pin_secret_id: Option<String>,
    },
    /// Android Hardware Keystore / StrongBox-bound hardware key.
    /// `keystore_alias` is the AndroidKeyStore alias persisted at
    /// create time; the connect path's `Session::connect_pubkey_keystore_owned`
    /// reaches into the AndroidKeyStore via JNI on every sign. No
    /// PIN slot — the BiometricPrompt fires at the OS layer.
    PubkeyKeystore {
        public_openssh: String,
        keystore_alias: String,
        key_type: String,
    },
}

#[derive(Debug, Clone)]
pub struct DbPreparedAuth {
    /// Tagged auth ref — Dart pattern-matches on the variant.
    pub auth: DbPreparedAuthRef,
    /// Every SecretStore id the caller must drop after the
    /// connect attempt settles. Empty when every staged secret
    /// belongs to a longer-lived owner (saved-session or
    /// manager-key without a typed passphrase).
    pub transient_secret_ids: Vec<String>,
}

impl From<auth_compose::PreparedAuth> for DbPreparedAuth {
    fn from(p: auth_compose::PreparedAuth) -> Self {
        let auth = match p.auth {
            auth_compose::PreparedAuthRef::Password { secret_id } => {
                DbPreparedAuthRef::Password { secret_id }
            }
            auth_compose::PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } => DbPreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            } => DbPreparedAuthRef::PubkeyCert {
                key_secret_id,
                cert_secret_id,
                passphrase_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeySk {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                pin_secret_id,
            } => DbPreparedAuthRef::PubkeySk {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                pin_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeySkCert {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                cert_secret_id,
                pin_secret_id,
            } => DbPreparedAuthRef::PubkeySkCert {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                cert_secret_id,
                pin_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeyPkcs11 {
                public_openssh,
                module_path,
                token_serial,
                cka_id,
                key_type,
                pin_secret_id,
            } => DbPreparedAuthRef::PubkeyPkcs11 {
                public_openssh,
                module_path,
                token_serial,
                cka_id,
                key_type,
                pin_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeyEnclave {
                public_openssh,
                application_tag,
            } => DbPreparedAuthRef::PubkeyEnclave {
                public_openssh,
                application_tag,
            },
            auth_compose::PreparedAuthRef::PubkeyHello {
                public_openssh,
                credential_name,
                key_type,
            } => DbPreparedAuthRef::PubkeyHello {
                public_openssh,
                credential_name,
                key_type,
            },
            auth_compose::PreparedAuthRef::PubkeyTpm {
                public_openssh,
                provider,
                blob,
                cng_key_name,
                key_type,
                pin_secret_id,
            } => DbPreparedAuthRef::PubkeyTpm {
                public_openssh,
                provider,
                blob,
                cng_key_name,
                key_type,
                pin_secret_id,
            },
            auth_compose::PreparedAuthRef::PubkeyKeystore {
                public_openssh,
                keystore_alias,
                key_type,
            } => DbPreparedAuthRef::PubkeyKeystore {
                public_openssh,
                keystore_alias,
                key_type,
            },
        };
        DbPreparedAuth {
            auth,
            transient_secret_ids: p.transient_secret_ids,
        }
    }
}

/// Compose the credential overlay + return the typed ref the
/// connect actor dispatches against. Every secret byte stages
/// inside Rust — the Dart `ConnectionManager` no longer copies
/// plaintext through the SecretStore on the connect path.
pub async fn connection_prepare_auth(input: DbPrepareAuthInput) -> Result<DbPreparedAuth, String> {
    let core_input: auth_compose::PrepareAuthInput = input.into();
    run_db(move |c| auth_compose::prepare_auth(c, &core_input))
        .await
        .map(DbPreparedAuth::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    // The async `connection_prepare_auth` endpoint stages secrets
    // through the SQLCipher session store; covered by the Dart
    // `auth_compose_test.dart` integration suite. The standalone
    // tests below pin the wire-shape `From` mappings + the
    // tagged-enum `DbPreparedAuthRef` round-trips that cross the
    // FRB boundary on every connect attempt.

    #[test]
    fn db_prepare_auth_input_carries_every_field_through() {
        let db = DbPrepareAuthInput {
            session_id: Some("sess-1".into()),
            key_id: "key-x".into(),
            key_data: "-----BEGIN…".into(),
            password: "hunter2".into(),
            passphrase: "pass-x".into(),
            pin: "654321".into(),
        };
        let core: auth_compose::PrepareAuthInput = db.into();
        assert_eq!(core.session_id.as_deref(), Some("sess-1"));
        assert_eq!(core.key_id, "key-x");
        assert_eq!(core.key_data, "-----BEGIN…");
        assert_eq!(core.password, "hunter2");
        assert_eq!(core.passphrase, "pass-x");
        assert_eq!(core.pin, "654321");
    }

    #[test]
    fn db_prepared_auth_password_variant_carries_secret_id() {
        let core = auth_compose::PreparedAuth {
            auth: auth_compose::PreparedAuthRef::Password {
                secret_id: "sid-pw".into(),
            },
            transient_secret_ids: vec!["sid-pw".into()],
        };
        let db: DbPreparedAuth = core.into();
        match db.auth {
            DbPreparedAuthRef::Password { secret_id } => assert_eq!(secret_id, "sid-pw"),
            _ => panic!("expected Password variant"),
        }
        assert_eq!(db.transient_secret_ids, vec!["sid-pw".to_string()]);
    }

    #[test]
    fn db_prepared_auth_pubkey_variant_with_passphrase_carries_both_ids() {
        let core = auth_compose::PreparedAuth {
            auth: auth_compose::PreparedAuthRef::Pubkey {
                key_secret_id: "sid-key".into(),
                passphrase_secret_id: Some("sid-phr".into()),
            },
            transient_secret_ids: vec!["sid-phr".into()],
        };
        let db: DbPreparedAuth = core.into();
        match db.auth {
            DbPreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } => {
                assert_eq!(key_secret_id, "sid-key");
                assert_eq!(passphrase_secret_id.as_deref(), Some("sid-phr"));
            }
            _ => panic!("expected Pubkey variant"),
        }
    }

    #[test]
    fn db_prepared_auth_pubkey_variant_without_passphrase_carries_none() {
        let core = auth_compose::PreparedAuth {
            auth: auth_compose::PreparedAuthRef::Pubkey {
                key_secret_id: "sid-key-bare".into(),
                passphrase_secret_id: None,
            },
            transient_secret_ids: Vec::new(),
        };
        let db: DbPreparedAuth = core.into();
        match db.auth {
            DbPreparedAuthRef::Pubkey {
                passphrase_secret_id,
                ..
            } => assert!(passphrase_secret_id.is_none()),
            _ => panic!("expected Pubkey variant"),
        }
        assert!(db.transient_secret_ids.is_empty());
    }

    #[test]
    fn db_prepare_auth_input_round_trips_session_id_none() {
        // Quick-connect path — no session_id pinned. Pin the
        // contract that None propagates verbatim.
        let db = DbPrepareAuthInput {
            session_id: None,
            key_id: "key".into(),
            key_data: String::new(),
            password: "pw".into(),
            passphrase: String::new(),
            pin: String::new(),
        };
        let core: auth_compose::PrepareAuthInput = db.into();
        assert!(core.session_id.is_none());
    }

    #[test]
    fn db_prepared_auth_pubkey_sk_variant_carries_every_field() {
        let core = auth_compose::PreparedAuth {
            auth: auth_compose::PreparedAuthRef::PubkeySk {
                public_openssh: "sk-ssh-ed25519@openssh.com AAAA...".into(),
                credential_id: vec![0xDE, 0xAD, 0xBE, 0xEF],
                application: "ssh:".into(),
                has_user_verification: true,
                pin_secret_id: Some("key.pin.sk1".into()),
            },
            transient_secret_ids: vec!["key.pin.sk1".into()],
        };
        let db: DbPreparedAuth = core.into();
        match db.auth {
            DbPreparedAuthRef::PubkeySk {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                pin_secret_id,
            } => {
                assert!(public_openssh.starts_with("sk-ssh-ed25519"));
                assert_eq!(credential_id, vec![0xDE, 0xAD, 0xBE, 0xEF]);
                assert_eq!(application, "ssh:");
                assert!(has_user_verification);
                assert_eq!(pin_secret_id.as_deref(), Some("key.pin.sk1"));
            }
            _ => panic!("expected PubkeySk variant"),
        }
    }

    #[test]
    fn db_prepared_auth_pubkey_sk_cert_variant_carries_every_field() {
        let core = auth_compose::PreparedAuth {
            auth: auth_compose::PreparedAuthRef::PubkeySkCert {
                public_openssh: "sk-ssh-ed25519@openssh.com AAAA...".into(),
                credential_id: vec![0xDE, 0xAD, 0xBE, 0xEF],
                application: "ssh:".into(),
                has_user_verification: true,
                cert_secret_id: "key.cert.sk1".into(),
                pin_secret_id: Some("key.pin.sk1".into()),
            },
            transient_secret_ids: vec!["key.pin.sk1".into()],
        };
        let db: DbPreparedAuth = core.into();
        match db.auth {
            DbPreparedAuthRef::PubkeySkCert {
                public_openssh,
                credential_id,
                application,
                has_user_verification,
                cert_secret_id,
                pin_secret_id,
            } => {
                assert!(public_openssh.starts_with("sk-ssh-ed25519"));
                assert_eq!(credential_id, vec![0xDE, 0xAD, 0xBE, 0xEF]);
                assert_eq!(application, "ssh:");
                assert!(has_user_verification);
                assert_eq!(cert_secret_id, "key.cert.sk1");
                assert_eq!(pin_secret_id.as_deref(), Some("key.pin.sk1"));
            }
            _ => panic!("expected PubkeySkCert variant"),
        }
    }
}
