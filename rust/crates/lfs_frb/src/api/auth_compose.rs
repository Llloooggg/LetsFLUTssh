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

/// Discriminator for [`DbPreparedAuth`]. The `kind` field
/// branches the Dart caller into the matching `SshAuth*Ref`
/// variant — `"password"` carries `secret_id`, `"pubkey"`
/// carries `key_secret_id` + optional `passphrase_secret_id`.
#[derive(Debug, Clone)]
pub struct DbPreparedAuth {
    /// `"password"` or `"pubkey"`.
    pub kind: String,
    /// For `"password"`: the SecretStore id of the staged
    /// password. For `"pubkey"`: the SecretStore id of the
    /// staged private-key PEM.
    pub primary_secret_id: String,
    /// For `"pubkey"` only — `Some(id)` when a passphrase was
    /// staged alongside the key, `None` otherwise. Always
    /// `None` for `"password"`.
    pub passphrase_secret_id: Option<String>,
    /// Every SecretStore id the caller must drop after the
    /// connect attempt settles. Empty when every staged secret
    /// belongs to a longer-lived owner (saved-session or
    /// manager-key without a typed passphrase).
    pub transient_secret_ids: Vec<String>,
}

impl From<auth_compose::PreparedAuth> for DbPreparedAuth {
    fn from(p: auth_compose::PreparedAuth) -> Self {
        match p.auth {
            auth_compose::PreparedAuthRef::Password { secret_id } => DbPreparedAuth {
                kind: "password".into(),
                primary_secret_id: secret_id,
                passphrase_secret_id: None,
                transient_secret_ids: p.transient_secret_ids,
            },
            auth_compose::PreparedAuthRef::Pubkey {
                key_secret_id,
                passphrase_secret_id,
            } => DbPreparedAuth {
                kind: "pubkey".into(),
                primary_secret_id: key_secret_id,
                passphrase_secret_id,
                transient_secret_ids: p.transient_secret_ids,
            },
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
