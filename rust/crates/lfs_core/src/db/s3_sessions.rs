//! S3 session details DAO. One row per `sessions` row whose
//! `kind = 's3'`; carries the S3 transport-config tuple (access key
//! id, region, endpoint, addressing style, default bucket, default
//! prefix).
//!
//! **Why a join table.** S3-specific config has no meaningful
//! defaults on a kind=ssh / kind=webdav session, and the SSH path
//! is the dominant one in practice. Inlining the columns on
//! `sessions` would force every session read to pay the
//! join-shaped width even when the columns are unused. The join
//! table mirrors `webdav_session_details`; the schema docstring
//! for `webdav_sessions` explains the same trade-off in detail.
//!
//! **Secret discipline.** The secret access key never lands on a
//! column here — `lfs_core::secrets::SecretStore` holds it under
//! `session.s3.<session_id>` and the connect path resolves it
//! from there. Same posture as the SSH and WebDAV auth paths.

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;

/// Canonical SecretStore id for an S3 session's secret access
/// key. Connect-path callers compose the id through this helper
/// so a staging audit (`SecretStore::list_ids`) can grep for it
/// without having to know every call site.
pub fn s3_secret_id(session_id: &str) -> String {
    format!("session.s3.{session_id}")
}

/// One S3 session row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct S3SessionRow {
    pub session_id: String,
    pub access_key_id: String,
    /// AWS region wire value (`us-east-1`, `eu-west-2`, `auto` for
    /// Cloudflare R2). Stored verbatim so a future region-aware
    /// transport probe can read it without parsing.
    pub region: String,
    /// Endpoint URL — `https://...`. Empty selects the AWS-default
    /// endpoint for the resolved region. Non-empty value is used
    /// verbatim (MinIO, Wasabi, R2, Spaces, Scaleway, B2-S3).
    pub endpoint: String,
    /// Addressing style. `false` (default) selects virtual-host
    /// addressing (`<bucket>.s3.<region>.amazonaws.com`); `true`
    /// selects path addressing (`<endpoint>/<bucket>/...`).
    /// MinIO and some private S3 deployments require path style.
    pub path_style: bool,
    pub default_bucket: String,
    pub default_prefix: String,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<S3SessionRow> {
    let path_style_int: i64 = row.get("path_style")?;
    Ok(S3SessionRow {
        session_id: row.get("session_id")?,
        access_key_id: row.get("access_key_id")?,
        region: row.get("region")?,
        endpoint: row.get("endpoint")?,
        path_style: path_style_int != 0,
        default_bucket: row.get("default_bucket")?,
        default_prefix: row.get("default_prefix")?,
    })
}

/// Fetch the S3 detail row paired with `session_id`. Returns
/// `None` when the session is not an S3 kind or has not been
/// configured yet — not an error.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix \
             FROM s3_session_details WHERE session_id = ?1",
        )
        .map_err(|e| Error::Db(format!("s3_session_details get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("s3_session_details get query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Db(format!("s3_session_details get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or replace the S3 detail row for `row.session_id`. The
/// caller is responsible for stamping the matching `sessions` row
/// with `kind = 's3'`.
pub fn upsert(conn: &impl DbAccess, row: &S3SessionRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO s3_session_details ( \
               session_id, access_key_id, region, endpoint, path_style, \
               default_bucket, default_prefix \
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
             ON CONFLICT(session_id) DO UPDATE SET \
               access_key_id  = excluded.access_key_id, \
               region         = excluded.region, \
               endpoint       = excluded.endpoint, \
               path_style     = excluded.path_style, \
               default_bucket = excluded.default_bucket, \
               default_prefix = excluded.default_prefix",
            params![
                row.session_id,
                row.access_key_id,
                row.region,
                row.endpoint,
                i64::from(row.path_style),
                row.default_bucket,
                row.default_prefix,
            ],
        )
        .map_err(|e| Error::Db(format!("s3_session_details upsert: {e}")))?;
    Ok(())
}

/// Physically remove every row. Used by the archive-import replace
/// mode before re-populating. No tombstone column today.
pub fn delete_all(conn: &impl DbAccess) -> Result<usize, Error> {
    conn.raw()
        .execute("DELETE FROM s3_session_details", [])
        .map_err(|e| Error::Db(format!("s3_session_details delete_all: {e}")))
}

/// Remove the S3 detail row for `session_id`. Returns the number
/// of rows affected — `0` is the idempotent no-op when the session
/// was never an S3 kind. The session row itself is not touched.
pub fn delete(conn: &impl DbAccess, session_id: &str) -> Result<usize, Error> {
    let n = conn
        .raw()
        .execute(
            "DELETE FROM s3_session_details WHERE session_id = ?1",
            params![session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete: {e}")))?;
    Ok(n)
}

/// Every S3 detail row, ordered by `session_id`. Used by archive
/// export. Most callers want [`get`] instead.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix \
             FROM s3_session_details ORDER BY session_id ASC",
        )
        .map_err(|e| Error::Db(format!("s3_session_details list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("s3_session_details list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("s3_session_details list row: {e}")))?);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
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
        }
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
    fn delete_returns_one_when_row_existed_zero_when_absent() {
        let db = db();
        seed_session(&db, "s1");
        db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
        let n = db.with_conn(|c| delete(c, "s1")).unwrap();
        assert_eq!(n, 1);
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
    fn list_all_orders_by_session_id_ascending() {
        let db = db();
        seed_session(&db, "s1");
        seed_session(&db, "s2");
        seed_session(&db, "s3");
        db.with_conn(|c| upsert(c, &s3("s2"))).unwrap();
        db.with_conn(|c| upsert(c, &s3("s1"))).unwrap();
        db.with_conn(|c| upsert(c, &s3("s3"))).unwrap();
        let all = db.with_conn(list_all).unwrap();
        assert_eq!(
            all.iter()
                .map(|r| r.session_id.as_str())
                .collect::<Vec<_>>(),
            vec!["s1", "s2", "s3"]
        );
    }

    #[test]
    fn s3_secret_id_is_stable() {
        assert_eq!(s3_secret_id("abc"), "session.s3.abc");
    }
}
