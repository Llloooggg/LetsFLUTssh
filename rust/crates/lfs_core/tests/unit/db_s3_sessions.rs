/// Unit tests extracted from db/s3_sessions.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::db::{bootstrap_schema, sessions, Connection, Db};

fn db() -> Db {
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    Db::from_raw_for_tests(conn)
}

fn seed_session(db: &Db, id: &str) {
    db.with_conn(|c| {
        sessions::upsert(
            c,
            &sessions::SessionRow {
                id: id.into(),
                label: id.into(),
                kind: sessions::SESSION_KIND_S3.into(),
                host: "example.com".into(),
                port: 443,
                user: "".into(),
                auth_type: "password".into(),
                ..Default::default()
            },
        )
    })
    .unwrap();
}

fn s3(session_id: &str) -> S3SessionRow {
    S3SessionRow {
        session_id: session_id.into(),
        access_key_id: "AKIAIOSFODNN7EXAMPLE".into(),
        region: "us-east-1".into(),
        endpoint: "".into(),
        path_style: false,
        default_bucket: "my-bucket".into(),
        default_prefix: "logs/".into(),
        trusted_cert_pem: None,
        insecure_skip_verify: false,
    }
}

fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
    db.with_conn(|c| {
        let row: Option<i64> = c
            .raw()
            .query_row(
                "SELECT deleted_at FROM s3_session_details WHERE session_id = ?1",
                params![id],
                |r| r.get(0),
            )
            .ok()
            .flatten();
        Ok(row)
    })
    .unwrap()
}

#[test]
fn upsert_then_get_round_trips_every_field() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
    assert_eq!(got, s3("s1"));
}

#[test]
fn get_returns_none_when_no_detail_attached() {
    let db = db();
    seed_session(&db, "s1");
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
}

#[test]
fn upsert_replaces_existing_row_for_same_session() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    let updated = S3SessionRow {
        endpoint: "https://minio.local:9000".into(),
        path_style: true,
        region: "auto".into(),
        ..s3("s1")
    };
    db.with_conn(|c| upsert(c, &updated)).unwrap();
    let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
    assert_eq!(got.endpoint, "https://minio.local:9000");
    assert!(got.path_style);
    assert_eq!(got.region, "auto");
}

#[test]
fn delete_writes_tombstone_instead_of_removing_row() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    let n = db.with_conn(|c| delete(c, "s1")).unwrap();
    assert_eq!(n, 1);
    assert!(raw_deleted_at(&db, "s1").is_some());
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
    let n = db.with_conn(|c| delete(c, "s1")).unwrap();
    assert_eq!(n, 0);
}

#[test]
fn cascade_drops_detail_when_parent_session_is_purged() {
    // ON DELETE CASCADE: the join row never outlives its
    // parent's physical removal. `sessions::delete` soft-deletes
    // the parent so the detail row survives until the sync
    // purge runs through `sessions::purge_tombstones`.
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| sessions::delete(c, "s1")).unwrap();
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
    db.with_conn(|c| sessions::purge_tombstones(c, i64::MAX))
        .unwrap();
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
}

#[test]
fn list_all_orders_by_session_id_and_skips_tombstones() {
    let db = db();
    seed_session(&db, "s1");
    seed_session(&db, "s2");
    seed_session(&db, "s3");
    db.with_conn(|c| upsert(c, &s3("s2"))).unwrap();
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| upsert(c, &s3("s3"))).unwrap();
    db.with_conn(|c| delete(c, "s2")).unwrap();
    let all = db.with_conn(list_all).unwrap();
    assert_eq!(
        all.iter()
            .map(|r| r.session_id.as_str())
            .collect::<Vec<_>>(),
        vec!["s1", "s3"]
    );
}

#[test]
fn upsert_revives_tombstoned_row() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| delete(c, "s1")).unwrap();
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
    assert!(raw_deleted_at(&db, "s1").is_none());
}

#[test]
fn purge_tombstones_physically_removes_old_rows() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| delete(c, "s1")).unwrap();
    let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
    assert_eq!(n, 1);
}

#[test]
fn apply_tombstone_lww_blocks_stale_stamp() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert_with_stamp(c, &s3("s1"), 100))
        .unwrap();
    let n = db.with_conn(|c| apply_tombstone(c, "s1", 50)).unwrap();
    assert_eq!(n, 0);
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
    let n = db.with_conn(|c| apply_tombstone(c, "s1", 200)).unwrap();
    assert_eq!(n, 1);
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
}

#[test]
fn s3_secret_id_is_stable() {
    assert_eq!(s3_secret_id("abc"), "session.s3.abc");
}

#[test]
fn set_secret_access_key_roundtrips_into_has_and_stage() {
    // Save → reopen → connect path. Mirrors the WebDAV test —
    // the S3 path had the same regression (in-memory-only secret
    // staging) and gets the same coverage so future refactors
    // can't silently re-introduce it on one side.
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    let n = db
        .with_conn(|c| set_secret_access_key(c, "s1", "AKIA-SECRET"))
        .unwrap();
    assert_eq!(n, 1);
    assert!(db.with_conn(|c| has_secret_access_key(c, "s1")).unwrap());

    let store = SecretStore::new();
    let staged = db
        .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
        .unwrap();
    assert!(staged);
    let bytes = store.get(&s3_secret_id("s1")).expect("staged slot");
    assert_eq!(bytes.as_slice(), b"AKIA-SECRET");
}

#[test]
fn set_secret_access_key_empty_clears_and_unstages() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| set_secret_access_key(c, "s1", "first"))
        .unwrap();
    db.with_conn(|c| set_secret_access_key(c, "s1", ""))
        .unwrap();
    assert!(!db.with_conn(|c| has_secret_access_key(c, "s1")).unwrap());
    let store = SecretStore::new();
    assert!(!db
        .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
        .unwrap());
}

#[test]
fn set_secret_access_key_returns_zero_when_row_missing() {
    let db = db();
    seed_session(&db, "s1");
    let n = db
        .with_conn(|c| set_secret_access_key(c, "s1", "x"))
        .unwrap();
    assert_eq!(n, 0);
}

#[test]
fn upsert_after_set_secret_preserves_credential() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
    db.with_conn(|c| set_secret_access_key(c, "s1", "keep-me"))
        .unwrap();
    let row = S3SessionRow {
        region: "eu-west-2".into(),
        ..s3("s1")
    };
    db.with_conn(|c| upsert(c, &row)).unwrap();
    assert!(db.with_conn(|c| has_secret_access_key(c, "s1")).unwrap());
}

#[test]
fn stage_secret_into_store_returns_false_on_missing_row() {
    let db = db();
    seed_session(&db, "s1");
    let store = SecretStore::new();
    let staged = db
        .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
        .unwrap();
    assert!(!staged);
}
