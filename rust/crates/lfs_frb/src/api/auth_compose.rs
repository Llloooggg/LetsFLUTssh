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
