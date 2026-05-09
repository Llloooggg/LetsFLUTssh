//! FRB adapter for `lfs_core::connection::auth_compose`. Exposes
//! the credential-overlay composer the Dart `ConnectionManager`
//! used to drive Dart-side as a single async call.
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
}

impl From<DbPrepareAuthInput> for auth_compose::PrepareAuthInput {
    fn from(d: DbPrepareAuthInput) -> Self {
        Self {
            session_id: d.session_id,
            key_id: d.key_id,
            key_data: d.key_data,
            password: d.password,
            passphrase: d.passphrase,
        }
    }
}

/// FRB-tagged enum mirroring `lfs_core::connection::auth_compose::PreparedAuthRef`.
/// FRB codegen emits a sealed Dart class with `_Password` /
/// `_Pubkey` subclasses; the caller pattern-matches instead of
/// branching on a string discriminant. Replaces an earlier
/// `DbPreparedAuth { kind: String, … }` shape that was the only
/// remaining stringly-typed FRB enum in the auth surface.
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
        };
        let core: auth_compose::PrepareAuthInput = db.into();
        assert_eq!(core.session_id.as_deref(), Some("sess-1"));
        assert_eq!(core.key_id, "key-x");
        assert_eq!(core.key_data, "-----BEGIN…");
        assert_eq!(core.password, "hunter2");
        assert_eq!(core.passphrase, "pass-x");
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
        };
        let core: auth_compose::PrepareAuthInput = db.into();
        assert!(core.session_id.is_none());
    }
}
