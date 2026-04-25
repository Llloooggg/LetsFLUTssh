//! SftpBookmarks DAO. Mirrors `lib/core/db/dao/sftp_bookmark_dao.dart`.

use rusqlite::{params, Connection};

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
    conn: &Connection,
    session_id: &str,
) -> Result<Vec<SftpBookmarkRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, session_id, remote_path, label, created_at \
             FROM sftp_bookmarks WHERE session_id = ?1 \
             ORDER BY remote_path ASC",
        )
        .map_err(|e| Error::Io(format!("sftp_bookmarks prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Io(format!("sftp_bookmarks query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("sftp_bookmarks row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &Connection, row: &SftpBookmarkRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO sftp_bookmarks (id, session_id, remote_path, label, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5) \
         ON CONFLICT(id) DO UPDATE SET \
           session_id = excluded.session_id, \
           remote_path = excluded.remote_path, \
           label = excluded.label",
        params![
            row.id,
            row.session_id,
            row.remote_path,
            row.label,
            row.created_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("sftp_bookmarks upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM sftp_bookmarks WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("sftp_bookmarks delete: {e}")))
}
