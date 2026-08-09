/// Unit tests extracted from connection/auth_compose.rs
/// Declared via `#[path] mod tests;` in the source file.
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
