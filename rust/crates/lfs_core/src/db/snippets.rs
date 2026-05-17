//! Snippets DAO. Mirrors `lib/core/db/dao/snippet_dao.dart`.

use rusqlite::params;

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SnippetRow {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SnippetRow> {
    Ok(SnippetRow {
        id: row.get("id")?,
        title: row.get("title")?,
        command: row.get("command")?,
        description: row.get("description")?,
        created_at_ms: row.get("created_at")?,
        updated_at_ms: row.get("updated_at")?,
    })
}

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<SnippetRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, title, command, description, created_at, updated_at \
             FROM snippets WHERE deleted_at IS NULL ORDER BY title ASC",
        )
        .map_err(|e| Error::Db(format!("snippets prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("snippets query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("snippets row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &SnippetRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO snippets (id, title, command, description, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
         ON CONFLICT(id) DO UPDATE SET \
           title = excluded.title, \
           command = excluded.command, \
           description = excluded.description, \
           updated_at = excluded.updated_at, \
           deleted_at = NULL",
            params![
                row.id,
                row.title,
                row.command,
                row.description,
                row.created_at_ms,
                row.updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("snippets upsert: {e}")))?;
    Ok(())
}

/// Soft-delete a single snippet by id. Flips `deleted_at` to
/// `now_unix_ms()`; the row survives so a sync-merge (`§8b`) can
/// replay the removal across devices.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE snippets SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("snippets delete: {e}")))
}

/// Soft-delete every live snippet. Tombstones share one stamp.
pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE snippets SET deleted_at = ?1 WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("snippets delete_all: {e}")))
}

/// Physically remove `snippets` rows whose `deleted_at` is older
/// than `before_ms`. Reserved for sync-merge teardown (`§8b`).
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM snippets WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("snippets purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

// ---- session_snippets M2M ----------------------------------------------

pub fn link_session_snippet(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
    snippet_id: &str,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT OR IGNORE INTO session_snippets (session_id, snippet_id) VALUES (?1, ?2)",
            params![session_id, snippet_id],
        )
        .map_err(|e| Error::Db(format!("session_snippets insert: {e}")))?;
    Ok(())
}

pub fn unlink_session_snippet(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
    snippet_id: &str,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "DELETE FROM session_snippets WHERE session_id = ?1 AND snippet_id = ?2",
            params![session_id, snippet_id],
        )
        .map_err(|e| Error::Db(format!("session_snippets delete: {e}")))
}

/// All snippets pinned to a session, joined back to the snippets
/// table so callers don't have to do an N+1 lookup. Mirrors drift's
/// `SnippetDao::getForSession`.
pub fn list_for_session(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<SnippetRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT s.id, s.title, s.command, s.description, s.created_at, s.updated_at \
             FROM snippets s \
             INNER JOIN session_snippets ss ON ss.snippet_id = s.id \
             WHERE ss.session_id = ?1 AND s.deleted_at IS NULL \
             ORDER BY s.title ASC",
        )
        .map_err(|e| Error::Db(format!("snippets list_for_session prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("snippets list_for_session query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("snippets list_for_session row: {e}")))?);
    }
    Ok(out)
}

pub fn list_session_snippet_ids(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT snippet_id FROM session_snippets WHERE session_id = ?1")
        .map_err(|e| Error::Db(format!("session_snippets prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Db(format!("session_snippets query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("session_snippets row: {e}")))?);
    }
    Ok(out)
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

    fn seed(db: &Db, id: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &SnippetRow {
                    id: id.into(),
                    title: id.into(),
                    command: "echo".into(),
                    description: String::new(),
                    created_at_ms: 0,
                    updated_at_ms: 0,
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
                    "SELECT deleted_at FROM snippets WHERE id = ?1",
                    params![id],
                    |r| r.get(0),
                )
                .ok()
                .flatten();
            Ok(row)
        })
        .unwrap()
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

    #[test]
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        seed(&db, "sn1");
        let n = db.with_conn(|c| delete(c, "sn1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "sn1").is_some());
    }

    #[test]
    fn list_all_skips_tombstoned_rows() {
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn list_for_session_skips_tombstoned_snippets() {
        // The join through session_snippets drops snippets whose
        // parent row was tombstoned. The M2M edge survives.
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        insert_session_raw(&db, "s1");
        db.with_conn(|c| link_session_snippet(c, "s1", "alive"))
            .unwrap();
        db.with_conn(|c| link_session_snippet(c, "s1", "dead"))
            .unwrap();
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn delete_all_tombstones_every_live_row() {
        let db = db();
        seed(&db, "a");
        seed(&db, "b");
        let n = db.with_conn(delete_all).unwrap();
        assert_eq!(n, 2);
        assert!(db.with_conn(list_all).unwrap().is_empty());
        assert!(raw_deleted_at(&db, "a").is_some());
        assert!(raw_deleted_at(&db, "b").is_some());
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        seed(&db, "sn1");
        db.with_conn(|c| delete(c, "sn1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "sn1").is_none());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        seed(&db, "sn1");
        db.with_conn(|c| delete(c, "sn1")).unwrap();
        seed(&db, "sn1");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert!(raw_deleted_at(&db, "sn1").is_none());
    }
}
