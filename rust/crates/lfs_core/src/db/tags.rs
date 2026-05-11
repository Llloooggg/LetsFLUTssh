//! Tags + the two M2M link tables (session_tags, folder_tags).
//! Mirrors `lib/core/db/dao/tag_dao.dart`.

use rusqlite::params;

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct TagRow {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<TagRow> {
    Ok(TagRow {
        id: row.get("id")?,
        name: row.get("name")?,
        color: row.get("color")?,
        created_at_ms: row.get("created_at")?,
    })
}

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, name, color, created_at FROM tags \
             WHERE deleted_at IS NULL ORDER BY name ASC",
        )
        .map_err(|e| Error::Db(format!("tags prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("tags row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &TagRow) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO tags (id, name, color, created_at) \
         VALUES (?1, ?2, ?3, ?4) \
         ON CONFLICT(id) DO UPDATE SET \
           name = excluded.name, \
           color = excluded.color, \
           deleted_at = NULL",
            params![row.id, row.name, row.color, row.created_at_ms],
        )
        .map_err(|e| Error::Db(format!("tags upsert: {e}")))?;
    Ok(())
}

/// Soft-delete a single tag by id. Flips `deleted_at` to
/// `now_unix_ms()` so a sync-merge can replay the removal.
///
/// **Known limit.** The schema's `UNIQUE(name)` constraint is
/// not partial — a tombstoned tag keeps its name reserved, so a
/// fresh tag created with the same name surfaces a UNIQUE
/// violation. The sync teardown
/// ([`purge_tombstones`]) clears the slot; the operator-facing
/// "delete then recreate same-name tag" loop is the case to
/// watch when the sync layer (`§8b`) lands.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE tags SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("tags delete: {e}")))
}

/// Soft-delete every live tag. Tombstones share one timestamp.
pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE tags SET deleted_at = ?1 WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("tags delete_all: {e}")))
}

/// Physically remove `tags` rows whose `deleted_at` is older
/// than `before_ms`. Reserved for sync-merge teardown (`§8b`).
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM tags WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("tags purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Tags attached to a session, joined back to the `tags` table.
/// Mirrors drift's `TagDao::getForSession`.
pub fn list_for_session(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT t.id, t.name, t.color, t.created_at \
             FROM tags t \
             INNER JOIN session_tags st ON st.tag_id = t.id \
             WHERE st.session_id = ?1 AND t.deleted_at IS NULL \
             ORDER BY t.name ASC",
        )
        .map_err(|e| Error::Db(format!("tags list_for_session prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("tags list_for_session query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("tags list_for_session row: {e}")))?);
    }
    Ok(out)
}

/// Tags attached to a folder, joined back to the `tags` table.
pub fn list_for_folder(
    conn: &impl crate::db::DbAccess,
    folder_id: &str,
) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT t.id, t.name, t.color, t.created_at \
             FROM tags t \
             INNER JOIN folder_tags ft ON ft.tag_id = t.id \
             WHERE ft.folder_id = ?1 AND t.deleted_at IS NULL \
             ORDER BY t.name ASC",
        )
        .map_err(|e| Error::Db(format!("tags list_for_folder prepare: {e}")))?;
    let rows = stmt
        .query_map(params![folder_id], row_from)
        .map_err(|e| Error::Db(format!("tags list_for_folder query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("tags list_for_folder row: {e}")))?);
    }
    Ok(out)
}

// ---- M2M link tables ---------------------------------------------------

pub fn link_session_tag(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
    tag_id: &str,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT OR IGNORE INTO session_tags (session_id, tag_id) VALUES (?1, ?2)",
            params![session_id, tag_id],
        )
        .map_err(|e| Error::Db(format!("session_tags insert: {e}")))?;
    Ok(())
}

pub fn unlink_session_tag(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
    tag_id: &str,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "DELETE FROM session_tags WHERE session_id = ?1 AND tag_id = ?2",
            params![session_id, tag_id],
        )
        .map_err(|e| Error::Db(format!("session_tags delete: {e}")))
}

pub fn list_session_tag_ids(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT tag_id FROM session_tags WHERE session_id = ?1")
        .map_err(|e| Error::Db(format!("session_tags prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Db(format!("session_tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("session_tags row: {e}")))?);
    }
    Ok(out)
}

pub fn link_folder_tag(
    conn: &impl crate::db::DbAccess,
    folder_id: &str,
    tag_id: &str,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT OR IGNORE INTO folder_tags (folder_id, tag_id) VALUES (?1, ?2)",
            params![folder_id, tag_id],
        )
        .map_err(|e| Error::Db(format!("folder_tags insert: {e}")))?;
    Ok(())
}

pub fn unlink_folder_tag(
    conn: &impl crate::db::DbAccess,
    folder_id: &str,
    tag_id: &str,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "DELETE FROM folder_tags WHERE folder_id = ?1 AND tag_id = ?2",
            params![folder_id, tag_id],
        )
        .map_err(|e| Error::Db(format!("folder_tags delete: {e}")))
}

pub fn list_folder_tag_ids(
    conn: &impl crate::db::DbAccess,
    folder_id: &str,
) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT tag_id FROM folder_tags WHERE folder_id = ?1")
        .map_err(|e| Error::Db(format!("folder_tags prepare: {e}")))?;
    let rows = stmt
        .query_map(params![folder_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Db(format!("folder_tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("folder_tags row: {e}")))?);
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

    fn seed(db: &Db, id: &str, name: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &TagRow {
                    id: id.into(),
                    name: name.into(),
                    color: None,
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
                    "SELECT deleted_at FROM tags WHERE id = ?1",
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
        seed(&db, "t1", "prod");
        let n = db.with_conn(|c| delete(c, "t1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "t1").is_some());
    }

    #[test]
    fn list_all_skips_tombstoned_rows() {
        let db = db();
        seed(&db, "alive", "alive-name");
        seed(&db, "dead", "dead-name");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    fn insert_session_raw(db: &Db, id: &str) {
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "INSERT INTO sessions (id, host, user, created_at, updated_at) \
                     VALUES (?1, ?2, ?3, ?4, ?4)",
                    params![id, "h", "u", 0_i64],
                )
                .map(|_| ())
                .map_err(|e| crate::error::Error::Db(format!("insert session: {e}")))
        })
        .unwrap();
    }

    fn insert_folder_raw(db: &Db, id: &str) {
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "INSERT INTO folders (id, name, created_at) VALUES (?1, ?2, ?3)",
                    params![id, "infra", 0_i64],
                )
                .map(|_| ())
                .map_err(|e| crate::error::Error::Db(format!("insert folder: {e}")))
        })
        .unwrap();
    }

    #[test]
    fn list_for_session_skips_tombstoned_tags() {
        // The join through session_tags must drop tags whose
        // parent row was tombstoned — the M2M edge survives, but
        // the read-side filter on `tags.deleted_at` hides the
        // edge's endpoint.
        let db = db();
        seed(&db, "alive", "alive");
        seed(&db, "dead", "dead");
        insert_session_raw(&db, "s1");
        db.with_conn(|c| link_session_tag(c, "s1", "alive"))
            .unwrap();
        db.with_conn(|c| link_session_tag(c, "s1", "dead")).unwrap();
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn list_for_folder_skips_tombstoned_tags() {
        let db = db();
        seed(&db, "alive", "alive");
        seed(&db, "dead", "dead");
        insert_folder_raw(&db, "f1");
        db.with_conn(|c| link_folder_tag(c, "f1", "alive")).unwrap();
        db.with_conn(|c| link_folder_tag(c, "f1", "dead")).unwrap();
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(|c| list_for_folder(c, "f1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn delete_all_tombstones_every_live_row() {
        let db = db();
        seed(&db, "a", "an");
        seed(&db, "b", "bn");
        let n = db.with_conn(delete_all).unwrap();
        assert_eq!(n, 2);
        assert!(db.with_conn(list_all).unwrap().is_empty());
        assert!(raw_deleted_at(&db, "a").is_some());
        assert!(raw_deleted_at(&db, "b").is_some());
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        seed(&db, "t1", "n1");
        db.with_conn(|c| delete(c, "t1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "t1").is_none());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        seed(&db, "t1", "n1");
        db.with_conn(|c| delete(c, "t1")).unwrap();
        seed(&db, "t1", "n1");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "t1");
        assert!(raw_deleted_at(&db, "t1").is_none());
    }
}
