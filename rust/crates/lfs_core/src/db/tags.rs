//! Tags + the two M2M link tables (session_tags, folder_tags).
//! Mirrors `lib/core/db/dao/tag_dao.dart`.

use rusqlite::{params, Connection};

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

pub fn list_all(conn: &Connection) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .prepare("SELECT id, name, color, created_at FROM tags ORDER BY name ASC")
        .map_err(|e| Error::Io(format!("tags prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("tags row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &Connection, row: &TagRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO tags (id, name, color, created_at) \
         VALUES (?1, ?2, ?3, ?4) \
         ON CONFLICT(id) DO UPDATE SET \
           name = excluded.name, \
           color = excluded.color",
        params![row.id, row.name, row.color, row.created_at_ms],
    )
    .map_err(|e| Error::Io(format!("tags upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM tags WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("tags delete: {e}")))
}

pub fn delete_all(conn: &Connection) -> Result<usize, Error> {
    conn.execute("DELETE FROM tags", [])
        .map_err(|e| Error::Io(format!("tags delete_all: {e}")))
}

/// Tags attached to a session, joined back to the `tags` table.
/// Mirrors drift's `TagDao::getForSession`.
pub fn list_for_session(conn: &Connection, session_id: &str) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT t.id, t.name, t.color, t.created_at \
             FROM tags t \
             INNER JOIN session_tags st ON st.tag_id = t.id \
             WHERE st.session_id = ?1 \
             ORDER BY t.name ASC",
        )
        .map_err(|e| Error::Io(format!("tags list_for_session prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Io(format!("tags list_for_session query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("tags list_for_session row: {e}")))?);
    }
    Ok(out)
}

/// Tags attached to a folder, joined back to the `tags` table.
pub fn list_for_folder(conn: &Connection, folder_id: &str) -> Result<Vec<TagRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT t.id, t.name, t.color, t.created_at \
             FROM tags t \
             INNER JOIN folder_tags ft ON ft.tag_id = t.id \
             WHERE ft.folder_id = ?1 \
             ORDER BY t.name ASC",
        )
        .map_err(|e| Error::Io(format!("tags list_for_folder prepare: {e}")))?;
    let rows = stmt
        .query_map(params![folder_id], row_from)
        .map_err(|e| Error::Io(format!("tags list_for_folder query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("tags list_for_folder row: {e}")))?);
    }
    Ok(out)
}

// ---- M2M link tables ---------------------------------------------------

pub fn link_session_tag(conn: &Connection, session_id: &str, tag_id: &str) -> Result<(), Error> {
    conn.execute(
        "INSERT OR IGNORE INTO session_tags (session_id, tag_id) VALUES (?1, ?2)",
        params![session_id, tag_id],
    )
    .map_err(|e| Error::Io(format!("session_tags insert: {e}")))?;
    Ok(())
}

pub fn unlink_session_tag(
    conn: &Connection,
    session_id: &str,
    tag_id: &str,
) -> Result<usize, Error> {
    conn.execute(
        "DELETE FROM session_tags WHERE session_id = ?1 AND tag_id = ?2",
        params![session_id, tag_id],
    )
    .map_err(|e| Error::Io(format!("session_tags delete: {e}")))
}

pub fn list_session_tag_ids(conn: &Connection, session_id: &str) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .prepare("SELECT tag_id FROM session_tags WHERE session_id = ?1")
        .map_err(|e| Error::Io(format!("session_tags prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Io(format!("session_tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("session_tags row: {e}")))?);
    }
    Ok(out)
}

pub fn link_folder_tag(conn: &Connection, folder_id: &str, tag_id: &str) -> Result<(), Error> {
    conn.execute(
        "INSERT OR IGNORE INTO folder_tags (folder_id, tag_id) VALUES (?1, ?2)",
        params![folder_id, tag_id],
    )
    .map_err(|e| Error::Io(format!("folder_tags insert: {e}")))?;
    Ok(())
}

pub fn unlink_folder_tag(conn: &Connection, folder_id: &str, tag_id: &str) -> Result<usize, Error> {
    conn.execute(
        "DELETE FROM folder_tags WHERE folder_id = ?1 AND tag_id = ?2",
        params![folder_id, tag_id],
    )
    .map_err(|e| Error::Io(format!("folder_tags delete: {e}")))
}

pub fn list_folder_tag_ids(conn: &Connection, folder_id: &str) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .prepare("SELECT tag_id FROM folder_tags WHERE folder_id = ?1")
        .map_err(|e| Error::Io(format!("folder_tags prepare: {e}")))?;
    let rows = stmt
        .query_map(params![folder_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Io(format!("folder_tags query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("folder_tags row: {e}")))?);
    }
    Ok(out)
}
