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

use rusqlite::Connection;

use crate::db::{sessions, ssh_keys};
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
}

/// Typed ref returned by [`prepare_auth`]. Mirrors the Dart-era
/// `SshAuthPasswordRef` / `SshAuthPubkeyRef` family case-for-case.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PreparedAuthRef {
    Password {
        secret_id: String,
    },
    Pubkey {
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
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
pub fn prepare_auth(conn: &Connection, input: &PrepareAuthInput) -> Result<PreparedAuth, Error> {
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

    // 2. Manager-key path.
    if !input.key_id.is_empty() && ssh_keys::stage_secret_into_store(conn, &input.key_id)? {
        let mut passphrase_secret_id = session_passphrase_id.clone();
        if !input.passphrase.is_empty() && passphrase_secret_id.is_none() {
            let id = format!("key.passphrase.{}", input.key_id);
            crate::app::instance()
                .secrets
                .put(&id, input.passphrase.as_bytes());
            transients.push(id.clone());
            passphrase_secret_id = Some(id);
        }
        return Ok(PreparedAuth {
            auth: PreparedAuthRef::Pubkey {
                key_secret_id: format!("key.priv.{}", input.key_id),
                passphrase_secret_id,
            },
            transient_secret_ids: transients,
        });
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
    use rusqlite::Connection as RusqliteConn;

    fn fresh_db() -> Db {
        let conn = RusqliteConn::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON").unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn insert_session(
        conn: &Connection,
        id: &str,
        password: &str,
        key_data: &str,
        passphrase: &str,
    ) {
        conn.execute(
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

    fn insert_key(conn: &Connection, id: &str, pem: &str) {
        conn.execute(
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
