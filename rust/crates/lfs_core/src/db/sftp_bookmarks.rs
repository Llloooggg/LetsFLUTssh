//! SftpBookmarks DAO. Mirrors `lib/core/db/dao/sftp_bookmark_dao.dart`.

use rusqlite::params;

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SftpBookmarkRow {
    pub id: String,
    pub session_id: String,
    pub remote_path: String,
    pub label: String,
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SftpBookmarkRow> {
    Ok(SftpBookmarkRow {
        id: row.get("id")?,
        session_id: row.get("session_id")?,
        remote_path: row.get("remote_path")?,
        label: row.get("label")?,
        created_at_ms: row.get("created_at")?,
    })
}

pub fn list_for_session(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<SftpBookmarkRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, session_id, remote_path, label, created_at \
             FROM sftp_bookmarks WHERE session_id = ?1 AND deleted_at IS NULL \
             ORDER BY remote_path ASC",
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("sftp_bookmarks query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("sftp_bookmarks row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &SftpBookmarkRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO sftp_bookmarks (id, session_id, remote_path, label, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5) \
         ON CONFLICT(id) DO UPDATE SET \
           session_id = excluded.session_id, \
           remote_path = excluded.remote_path, \
           label = excluded.label, \
           deleted_at = NULL",
            params![
                row.id,
                row.session_id,
                row.remote_path,
                row.label,
                row.created_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks upsert: {e}")))?;
    Ok(())
}

/// List every live bookmark across every session, ordered by
/// `session_id` then `remote_path`. Used by the archive composer to
/// fold every bookmark into one JSON payload.
pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<SftpBookmarkRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, session_id, remote_path, label, created_at \
             FROM sftp_bookmarks WHERE deleted_at IS NULL \
             ORDER BY session_id ASC, remote_path ASC",
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks list_all prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("sftp_bookmarks list_all query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("sftp_bookmarks list_all row: {e}")))?);
    }
    Ok(out)
}

/// Every bookmark paired with its `deleted_at` stamp, tombstones
/// included. The sync composer needs the tombstoned rows so a peer
/// device can replay a deletion; `list_all` filters them out (live
/// snapshot only), so a soft-deleted bookmark would otherwise never
/// reach the wire and the peer would push the still-live row
/// straight back. Archive / QR exports keep using `list_all` (live
/// rows only). Bookmarks carry no `updated_at` column, so the LWW
/// key is `created_at_ms`; the tombstone's own `deleted_at` stamp
/// is the deletion event time [`apply_tombstone`] compares against.
pub fn list_all_with_tombstones(
    conn: &impl crate::db::DbAccess,
) -> Result<Vec<(SftpBookmarkRow, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, session_id, remote_path, label, created_at, deleted_at \
             FROM sftp_bookmarks ORDER BY session_id ASC, remote_path ASC",
        )
        .map_err(|e| {
            Error::Db(format!(
                "sftp_bookmarks list_all_with_tombstones prepare: {e}"
            ))
        })?;
    let rows = stmt
        .query_map([], |row| {
            let r = row_from(row)?;
            let deleted_at: Option<i64> = row.get("deleted_at")?;
            Ok((r, deleted_at))
        })
        .map_err(|e| {
            Error::Db(format!(
                "sftp_bookmarks list_all_with_tombstones query: {e}"
            ))
        })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(
            r.map_err(|e| Error::Db(format!("sftp_bookmarks list_all_with_tombstones row: {e}")))?,
        );
    }
    Ok(out)
}

/// Apply a peer bookmark tombstone with an explicit stamp under the
/// sync LWW rule. The row's `deleted_at` flips only when the peer's
/// `deleted_at_ms` is strictly newer than the local `created_at` —
/// bookmarks carry no `updated_at`, so `created_at` is the LWW
/// timestamp; a tie or a stale stamp loses. Returns the affected
/// row count (0 = LWW rejected the tombstone).
pub fn apply_tombstone(
    conn: &impl crate::db::DbAccess,
    id: &str,
    deleted_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE sftp_bookmarks SET deleted_at = ?1 \
             WHERE id = ?2 AND deleted_at IS NULL AND created_at < ?1",
            params![deleted_at_ms, id],
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks apply_tombstone: {e}")))
}

/// Soft-delete every live row in one shot. Shares the
/// `now_unix_ms()` stamp across the bulk so a sync replay sees a
/// single tombstone moment. Used by the archive-import replace mode
/// to clear the table before re-populating.
pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE sftp_bookmarks SET deleted_at = ?1 WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks delete_all: {e}")))
}

/// Soft-delete a single bookmark by id. Flips `deleted_at` to
/// `now_unix_ms()`; the row survives so a sync-merge (`§8b`) can
/// replay the removal across devices.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE sftp_bookmarks SET deleted_at = ?1 \
             WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("sftp_bookmarks delete: {e}")))
}

/// Physically remove `sftp_bookmarks` rows whose `deleted_at` is
/// older than `before_ms`. Reserved for sync-merge teardown
/// (`§8b`).
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM sftp_bookmarks WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("sftp_bookmarks purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tombstone_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Connection, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn insert_session_raw(db: &Db, id: &str) {
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "INSERT INTO sessions (id, created_at, updated_at) VALUES (?1, ?2, ?2)",
                    params![id, 0_i64],
                )
                .map(|_| ())
                .map_err(|e| crate::error::Error::Db(format!("insert session: {e}")))
        })
        .unwrap();
    }

    fn seed(db: &Db, id: &str, session_id: &str, remote_path: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &SftpBookmarkRow {
                    id: id.into(),
                    session_id: session_id.into(),
                    remote_path: remote_path.into(),
                    label: String::new(),
                    created_at_ms: 0,
                },
            )
        })
        .unwrap();
    }

    fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
        db.with_conn(|c| {
            let row: Option<i64> = c
                .raw()
                .query_row(
                    "SELECT deleted_at FROM sftp_bookmarks WHERE id = ?1",
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
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "bm1", "s1", "/var/log");
        let n = db.with_conn(|c| delete(c, "bm1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "bm1").is_some());
    }

    #[test]
    fn list_for_session_skips_tombstoned_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "alive", "s1", "/a");
        seed(&db, "dead", "s1", "/b");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "bm1", "s1", "/a");
        db.with_conn(|c| delete(c, "bm1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "bm1").is_none());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "bm1", "s1", "/a");
        db.with_conn(|c| delete(c, "bm1")).unwrap();
        seed(&db, "bm1", "s1", "/a");
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert!(raw_deleted_at(&db, "bm1").is_none());
    }

    #[test]
    fn list_all_with_tombstones_keeps_tombstoned_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "alive", "s1", "/a");
        seed(&db, "dead", "s1", "/b");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all_with_tombstones).unwrap();
        assert_eq!(rows.len(), 2);
        let dead = rows.iter().find(|(r, _)| r.id == "dead").unwrap();
        assert!(dead.1.is_some(), "dead row carries a deleted_at stamp");
        let alive = rows.iter().find(|(r, _)| r.id == "alive").unwrap();
        assert!(alive.1.is_none(), "alive row has no tombstone");
    }

    #[test]
    fn apply_tombstone_lww_blocks_stale_stamp() {
        let db = db();
        insert_session_raw(&db, "s1");
        // Bookmarks key LWW on `created_at` (no `updated_at` column).
        db.with_conn(|c| {
            upsert(
                c,
                &SftpBookmarkRow {
                    id: "bm1".into(),
                    session_id: "s1".into(),
                    remote_path: "/a".into(),
                    label: String::new(),
                    created_at_ms: 100,
                },
            )
        })
        .unwrap();
        // Stale peer tombstone (50 < local created_at 100) is rejected.
        let n = db.with_conn(|c| apply_tombstone(c, "bm1", 50)).unwrap();
        assert_eq!(n, 0);
        assert!(raw_deleted_at(&db, "bm1").is_none());
        // Fresh peer tombstone (200 > local 100) lands.
        let n = db.with_conn(|c| apply_tombstone(c, "bm1", 200)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "bm1").is_some());
    }
}
