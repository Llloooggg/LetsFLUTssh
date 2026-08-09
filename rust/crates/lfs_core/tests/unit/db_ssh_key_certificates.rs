/// Unit tests extracted from db/ssh_key_certificates.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::db::{bootstrap_schema, ssh_keys, Connection, Db};

fn db() -> Db {
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    Db::from_raw_for_tests(conn)
}

fn seed_key(db: &Db, id: &str) {
    db.with_conn(|c| {
        ssh_keys::upsert(
            c,
            &ssh_keys::SshKeyRow {
                id: id.into(),
                label: "lab".into(),
                private_key: "PRIV".into(),
                public_key: "ssh-ed25519 AAAA".into(),
                key_type: "ssh-ed25519".into(),
                is_generated: false,
                created_at_ms: 0,
                credential_id: None,
                application_string: None,
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Ask,
                backend: ssh_keys::KeyBackend::Software,
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
                imported_as_stub: false,
            },
        )
    })
    .unwrap();
}

fn cert(key_id: &str) -> CertRecord {
    let mut critical = BTreeMap::new();
    critical.insert("force-command".to_string(), "echo hi".to_string());
    CertRecord {
        key_id: key_id.into(),
        certificate: vec![0xDE, 0xAD, 0xBE, 0xEF],
        valid_after: 1_700_000_000,
        valid_before: 1_700_086_400,
        principals: vec!["alice".to_string(), "root".to_string()],
        critical_options: critical,
        fingerprint: "SHA256:abc".into(),
    }
}

#[test]
fn upsert_then_get_round_trips_every_field() {
    let db = db();
    seed_key(&db, "k1");
    db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
    let got = db.with_conn(|c| get(c, "k1")).unwrap().unwrap();
    assert_eq!(got, cert("k1"));
}

#[test]
fn get_returns_none_when_no_cert_attached() {
    let db = db();
    seed_key(&db, "k1");
    assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_none());
}

#[test]
fn upsert_replaces_existing_row_for_same_key() {
    let db = db();
    seed_key(&db, "k1");
    db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
    let updated = CertRecord {
        certificate: vec![0x01, 0x02],
        valid_before: 2_000_000_000,
        fingerprint: "SHA256:def".into(),
        ..cert("k1")
    };
    db.with_conn(|c| upsert(c, &updated)).unwrap();
    let got = db.with_conn(|c| get(c, "k1")).unwrap().unwrap();
    assert_eq!(got.certificate, vec![0x01, 0x02]);
    assert_eq!(got.valid_before, 2_000_000_000);
    assert_eq!(got.fingerprint, "SHA256:def");
}

#[test]
fn delete_returns_one_when_row_existed_zero_when_absent() {
    let db = db();
    seed_key(&db, "k1");
    db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
    let n = db.with_conn(|c| delete(c, "k1")).unwrap();
    assert_eq!(n, 1);
    let n = db.with_conn(|c| delete(c, "k1")).unwrap();
    assert_eq!(n, 0);
}

#[test]
fn cascade_delete_drops_cert_when_parent_key_is_purged() {
    // The FK declares ON DELETE CASCADE so the join row never
    // outlives its parent's physical removal. `ssh_keys::delete`
    // soft-deletes the parent under the v3 tombstone contract,
    // so the cert survives until the sync-purge runs through
    // `ssh_keys::purge_tombstones`. Once the parent leaves the
    // table for good, the cascade physically drops the cert.
    let db = db();
    seed_key(&db, "k1");
    db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
    db.with_conn(|c| ssh_keys::delete(c, "k1")).unwrap();
    // Cert still present while the parent key is tombstoned.
    assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_some());
    // Physical purge of the parent fires the cascade.
    db.with_conn(|c| ssh_keys::purge_tombstones(c, i64::MAX))
        .unwrap();
    assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_none());
}

#[test]
fn list_all_orders_by_key_id_ascending() {
    let db = db();
    seed_key(&db, "k1");
    seed_key(&db, "k2");
    seed_key(&db, "k3");
    db.with_conn(|c| upsert(c, &cert("k2"))).unwrap();
    db.with_conn(|c| upsert(c, &cert("k1"))).unwrap();
    db.with_conn(|c| upsert(c, &cert("k3"))).unwrap();
    let all = db.with_conn(list_all).unwrap();
    assert_eq!(
        all.iter().map(|r| r.key_id.as_str()).collect::<Vec<_>>(),
        vec!["k1", "k2", "k3"]
    );
}

#[test]
fn certificate_secret_id_is_stable() {
    // Connect-path callers compose the id; the canonical form
    // belongs to one place so a staging audit can grep for it.
    assert_eq!(certificate_secret_id("abc"), "key.cert.abc");
}
