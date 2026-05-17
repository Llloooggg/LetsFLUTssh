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
//! **Secret discipline.** The secret access key persists on the
//! `secret_access_key` column (encrypted at rest by SQLCipher,
//! same posture as `ssh_session_details.password` /
//! `webdav_session_details.password`). The connect path calls
//! [`stage_secret_into_store`] right before `s3_connect`, which
//! copies the bytes from the column into the process-singleton
//! `SecretStore` under `session.s3.<session_id>` — the FRB
//! `s3_connect` reads by id so the plaintext never crosses back to
//! Dart. Plaintext travels FRB only one-way (Dart → Rust on save
//! via [`set_secret_access_key`]); the typed [`S3SessionRow`] read
//! path returns metadata only.
//!
//! **Tombstone discipline.** Same shape as `webdav_session_details`:
//! `delete` flips `deleted_at` to `now_unix_ms()` and bumps
//! `updated_at`, `upsert` clears the tombstone + stamps a fresh
//! `updated_at`, `purge_tombstones` removes rows older than a
//! threshold.

use rusqlite::params;

use crate::db::DbAccess;
use crate::error::Error;
use crate::secrets::SecretStore;

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
/// `None` when the session is not an S3 kind, has not been
/// configured yet, or has been tombstoned by a `delete` call.
pub fn get(conn: &impl DbAccess, session_id: &str) -> Result<Option<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix \
             FROM s3_session_details \
             WHERE session_id = ?1 AND deleted_at IS NULL",
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
/// with `kind = 's3'`. Stamps a fresh `updated_at` so the sync
/// LWW gate moves forward; clears any pre-existing tombstone so a
/// revived row is observable again.
pub fn upsert(conn: &impl DbAccess, row: &S3SessionRow) -> Result<(), Error> {
    upsert_with_stamp(conn, row, now_unix_ms())
}

/// Same as [`upsert`] but with an explicit `updated_at_ms` stamp.
/// Used by the sync apply path so the receiver records the peer's
/// timestamp instead of a fresh local one.
pub fn upsert_with_stamp(
    conn: &impl DbAccess,
    row: &S3SessionRow,
    updated_at_ms: i64,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO s3_session_details ( \
               session_id, access_key_id, region, endpoint, path_style, \
               default_bucket, default_prefix, updated_at \
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) \
             ON CONFLICT(session_id) DO UPDATE SET \
               access_key_id  = excluded.access_key_id, \
               region         = excluded.region, \
               endpoint       = excluded.endpoint, \
               path_style     = excluded.path_style, \
               default_bucket = excluded.default_bucket, \
               default_prefix = excluded.default_prefix, \
               updated_at     = excluded.updated_at, \
               deleted_at     = NULL",
            params![
                row.session_id,
                row.access_key_id,
                row.region,
                row.endpoint,
                i64::from(row.path_style),
                row.default_bucket,
                row.default_prefix,
                updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("s3_session_details upsert: {e}")))?;
    Ok(())
}

/// Replace the persisted secret access key for `session_id`. Empty
/// `value` clears the credential. Returns rows affected (`0` when
/// the S3 detail row hasn't been inserted yet — the caller must
/// `upsert` first). Bumps the parent `s3_session_details.updated_at`
/// so the sync LWW gate moves forward; the parent
/// `sessions.updated_at` is bumped too so a listing query that
/// watches the parent row sees the edit.
///
/// `value` reaches us through FRB but never crosses back to Dart —
/// combined with [`stage_secret_into_store`] this lets the edit
/// dialog save a fresh secret access key without ever pre-filling
/// the old one onto the Dart heap.
pub fn set_secret_access_key(
    conn: &impl DbAccess,
    session_id: &str,
    value: &str,
) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE s3_session_details \
                SET secret_access_key = ?1, updated_at = ?2 \
                WHERE session_id = ?3 AND deleted_at IS NULL",
            params![value, now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details set_secret_access_key: {e}")))?;
    if n > 0 {
        conn.raw()
            .execute(
                "UPDATE sessions SET updated_at = ?1 \
                    WHERE id = ?2 AND deleted_at IS NULL",
                params![now_ms, session_id],
            )
            .map_err(|e| {
                Error::Db(format!(
                    "s3_session_details set_secret_access_key parent stamp: {e}"
                ))
            })?;
    }
    Ok(n)
}

/// Cheap presence probe — the edit dialog needs to render the
/// "[Saved] type to change" hint without ever reading the
/// plaintext back over FRB. Returns `false` for a missing row, a
/// tombstoned row, or an empty-string column.
pub fn has_secret_access_key(conn: &impl DbAccess, session_id: &str) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT secret_access_key FROM s3_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    Ok(row.map(|s| !s.is_empty()).unwrap_or(false))
}

/// Read the persisted secret access key and push it into the
/// process-singleton `SecretStore` under [`s3_secret_id`]`(session_id)`.
/// Returns `true` when a non-empty key was staged, `false` otherwise
/// (missing row, tombstoned row, or empty-string column).
///
/// Pairs with [`set_secret_access_key`]: the save path commits to
/// the column, the connect path stages from the column into the
/// SecretStore right before [`crate::s3::client::S3Client`] runs
/// its connect probe.
pub fn stage_secret_into_store(
    conn: &impl DbAccess,
    store: &SecretStore,
    session_id: &str,
) -> Result<bool, Error> {
    let row: Option<String> = conn
        .raw()
        .query_row(
            "SELECT secret_access_key FROM s3_session_details \
                WHERE session_id = ?1 AND deleted_at IS NULL",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    let Some(key) = row else { return Ok(false) };
    if key.is_empty() {
        return Ok(false);
    }
    store.put(&s3_secret_id(session_id), key.as_bytes());
    Ok(true)
}

/// Soft-delete every live row. Tombstones share one stamp so the
/// bulk-clear is a single point on the sync timeline. Used by the
/// archive-import replace mode before re-populating.
pub fn delete_all(conn: &impl DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete_all: {e}")))
}

/// Soft-delete the S3 detail row for `session_id`. Flips
/// `deleted_at` to `now_unix_ms()` and bumps `updated_at`. Returns
/// `0` when the session was never an S3 kind or the row is already
/// tombstoned.
pub fn delete(conn: &impl DbAccess, session_id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND deleted_at IS NULL",
            params![now_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details delete: {e}")))?;
    Ok(n)
}

/// Every live S3 detail row, ordered by `session_id`. Used by
/// archive export. Most callers want [`get`] instead. Tombstoned
/// rows are filtered.
pub fn list_all(conn: &impl DbAccess) -> Result<Vec<S3SessionRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix \
             FROM s3_session_details WHERE deleted_at IS NULL \
             ORDER BY session_id ASC",
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

/// Every row paired with `(updated_at_ms, deleted_at)`. Sync
/// composers emit tombstoned rows so a peer device can replay the
/// removal. Archive composers filter out tombstones to keep the
/// wire payload to live rows.
pub fn list_all_with_tombstones(
    conn: &impl DbAccess,
) -> Result<Vec<(S3SessionRow, i64, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT session_id, access_key_id, region, endpoint, path_style, \
                    default_bucket, default_prefix, updated_at, deleted_at \
             FROM s3_session_details ORDER BY session_id ASC",
        )
        .map_err(|e| {
            Error::Db(format!(
                "s3_session_details list_all_with_tombstones prepare: {e}"
            ))
        })?;
    let rows = stmt
        .query_map([], |r| {
            let row = row_from(r)?;
            let updated_at: i64 = r.get("updated_at")?;
            let deleted_at: Option<i64> = r.get("deleted_at")?;
            Ok((row, updated_at, deleted_at))
        })
        .map_err(|e| {
            Error::Db(format!(
                "s3_session_details list_all_with_tombstones query: {e}"
            ))
        })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| {
            Error::Db(format!(
                "s3_session_details list_all_with_tombstones row: {e}"
            ))
        })?);
    }
    Ok(out)
}

/// Look up a row's `updated_at_ms` regardless of tombstone state.
/// Used by the sync apply LWW gate.
pub fn get_updated_at(conn: &impl DbAccess, session_id: &str) -> Result<Option<i64>, Error> {
    let row: Option<i64> = conn
        .raw()
        .query_row(
            "SELECT updated_at FROM s3_session_details WHERE session_id = ?1",
            params![session_id],
            |r| r.get(0),
        )
        .ok();
    Ok(row)
}

/// Apply a peer tombstone with an explicit stamp. The LWW gate
/// rejects stale stamps (peer's stamp strictly newer than the
/// local `updated_at` to land).
pub fn apply_tombstone(
    conn: &impl DbAccess,
    session_id: &str,
    deleted_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE s3_session_details SET deleted_at = ?1, updated_at = ?1 \
             WHERE session_id = ?2 AND (updated_at IS NULL OR updated_at < ?1)",
            params![deleted_at_ms, session_id],
        )
        .map_err(|e| Error::Db(format!("s3_session_details apply_tombstone: {e}")))
}

/// Physically remove rows whose `deleted_at` is older than
/// `before_ms`. Reserved for sync-merge teardown.
pub fn purge_tombstones(conn: &impl DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM s3_session_details \
             WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("s3_session_details purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` /
/// `updated_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
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
}
