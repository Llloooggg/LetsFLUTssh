/// Unit tests extracted from db/webdav_sessions.rs
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
                kind: sessions::SESSION_KIND_WEBDAV.into(),
                host: "example.com".into(),
                port: 443,
                user: "alice".into(),
                auth_type: "password".into(),
                ..Default::default()
            },
        )
    })
    .unwrap();
}

fn webdav(session_id: &str) -> WebDavSessionRow {
    WebDavSessionRow {
        session_id: session_id.into(),
        base_url: "https://example.com/remote.php/dav/files/alice/".into(),
        username: "alice".into(),
        auth_method: "basic".into(),
        trusted_cert_pem: None,
        insecure_skip_verify: false,
    }
}

fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
    db.with_conn(|c| {
        let row: Option<i64> = c
            .raw()
            .query_row(
                "SELECT deleted_at FROM webdav_session_details WHERE session_id = ?1",
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
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
    assert_eq!(got, webdav("s1"));
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
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    let pem = "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----\n";
    let updated = WebDavSessionRow {
        base_url: "https://example.com/webdav/".into(),
        auth_method: "digest".into(),
        trusted_cert_pem: Some(pem.into()),
        insecure_skip_verify: true,
        ..webdav("s1")
    };
    db.with_conn(|c| upsert(c, &updated)).unwrap();
    let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
    assert_eq!(got.base_url, "https://example.com/webdav/");
    assert_eq!(got.auth_method, "digest");
    assert_eq!(got.trusted_cert_pem.as_deref(), Some(pem));
    assert!(got.insecure_skip_verify);
}

#[test]
fn delete_writes_tombstone_instead_of_removing_row() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    let n = db.with_conn(|c| delete(c, "s1")).unwrap();
    assert_eq!(n, 1);
    assert!(raw_deleted_at(&db, "s1").is_some());
    // The get filter hides tombstoned rows.
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
    // Repeat delete on already-tombstoned row is a no-op.
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
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
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
    db.with_conn(|c| upsert(c, &webdav("s2"))).unwrap();
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    db.with_conn(|c| upsert(c, &webdav("s3"))).unwrap();
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
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    db.with_conn(|c| delete(c, "s1")).unwrap();
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
    assert!(raw_deleted_at(&db, "s1").is_none());
}

#[test]
fn purge_tombstones_physically_removes_old_rows() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    db.with_conn(|c| delete(c, "s1")).unwrap();
    let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
    assert_eq!(n, 1);
    // Row is physically gone.
    assert_eq!(
        db.with_conn(|c| {
            let n: i64 = c
                .raw()
                .query_row(
                    "SELECT COUNT(*) FROM webdav_session_details WHERE session_id = ?1",
                    params!["s1"],
                    |r| r.get(0),
                )
                .unwrap();
            Ok(n)
        })
        .unwrap(),
        0
    );
}

#[test]
fn apply_tombstone_lww_blocks_stale_stamp() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert_with_stamp(c, &webdav("s1"), 100))
        .unwrap();
    let n = db.with_conn(|c| apply_tombstone(c, "s1", 50)).unwrap();
    assert_eq!(n, 0);
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_some());
    let n = db.with_conn(|c| apply_tombstone(c, "s1", 200)).unwrap();
    assert_eq!(n, 1);
    assert!(db.with_conn(|c| get(c, "s1")).unwrap().is_none());
}

#[test]
fn webdav_secret_id_is_stable() {
    // Connect-path callers compose the id; the canonical form
    // belongs to one place so a staging audit can grep for it.
    assert_eq!(webdav_secret_id("abc"), "session.webdav.abc");
}

#[test]
fn set_password_roundtrips_into_has_and_stage() {
    // Save → reopen → connect path. The save-time setter stamps
    // the column; the connect-time stage call reads it into a
    // fresh SecretStore. This is the exact regression that left
    // the user re-typing the WebDAV password every launch when
    // SecretStore was the only landing pad.
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    let n = db
        .with_conn(|c| set_password(c, "s1", "t0p-s3cret"))
        .unwrap();
    assert_eq!(n, 1);
    assert!(db.with_conn(|c| has_password(c, "s1")).unwrap());

    let store = SecretStore::new();
    let staged = db
        .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
        .unwrap();
    assert!(staged);
    let bytes = store.get(&webdav_secret_id("s1")).expect("staged slot");
    assert_eq!(bytes.as_slice(), b"t0p-s3cret");
}

#[test]
fn set_password_empty_string_clears_and_unstages() {
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    db.with_conn(|c| set_password(c, "s1", "first")).unwrap();
    db.with_conn(|c| set_password(c, "s1", "")).unwrap();
    assert!(!db.with_conn(|c| has_password(c, "s1")).unwrap());
    let store = SecretStore::new();
    let staged = db
        .with_conn(|c| stage_secret_into_store(c, &store, "s1"))
        .unwrap();
    assert!(!staged);
    assert!(store.get(&webdav_secret_id("s1")).is_none());
}

#[test]
fn set_password_returns_zero_when_row_missing() {
    // `set_password` requires the detail row to exist first —
    // the save path always upserts before stamping the password,
    // so a setter call without an upsert is a no-op rather than
    // silently minting an orphan row.
    let db = db();
    seed_session(&db, "s1");
    let n = db.with_conn(|c| set_password(c, "s1", "x")).unwrap();
    assert_eq!(n, 0);
    assert!(!db.with_conn(|c| has_password(c, "s1")).unwrap());
}

#[test]
fn set_password_does_not_disturb_other_columns() {
    // Bumping the password must not corrupt base_url / username /
    // auth_method / trusted_cert_pem / insecure_skip_verify —
    // the setter is a single-column UPDATE, but assert it on the
    // wire to catch any future change that switches to an INSERT
    // OR REPLACE shape.
    let db = db();
    seed_session(&db, "s1");
    let pem = "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----\n";
    let row = WebDavSessionRow {
        base_url: "https://nc.example.com/dav/files/alice/".into(),
        auth_method: "digest".into(),
        trusted_cert_pem: Some(pem.into()),
        insecure_skip_verify: true,
        ..webdav("s1")
    };
    db.with_conn(|c| upsert(c, &row)).unwrap();
    db.with_conn(|c| set_password(c, "s1", "after")).unwrap();
    let got = db.with_conn(|c| get(c, "s1")).unwrap().unwrap();
    assert_eq!(got.base_url, row.base_url);
    assert_eq!(got.auth_method, "digest");
    assert_eq!(got.trusted_cert_pem.as_deref(), Some(pem));
    assert!(got.insecure_skip_verify);
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

#[test]
fn upsert_after_set_password_preserves_secret() {
    // Save flow: the dialog upserts metadata then conditionally
    // calls `set_password`. A re-edit that doesn't change the
    // password re-runs `upsert` alone; the existing password
    // column must survive. Without this guarantee, every
    // metadata edit would silently clear the saved credential.
    let db = db();
    seed_session(&db, "s1");
    db.with_conn(|c| upsert(c, &webdav("s1"))).unwrap();
    db.with_conn(|c| set_password(c, "s1", "keep-me")).unwrap();
    // Second upsert (e.g. user toggled auth method from basic to
    // digest) must not wipe the password.
    let row = WebDavSessionRow {
        auth_method: "digest".into(),
        ..webdav("s1")
    };
    db.with_conn(|c| upsert(c, &row)).unwrap();
    assert!(db.with_conn(|c| has_password(c, "s1")).unwrap());
}
