//! Snippets DAO. Mirrors `lib/core/db/dao/snippet_dao.dart`.

use rusqlite::{params, Connection};

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

pub fn list_all(conn: &Connection) -> Result<Vec<SnippetRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, title, command, description, created_at, updated_at \
             FROM snippets ORDER BY title ASC",
        )
        .map_err(|e| Error::Io(format!("snippets prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("snippets query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("snippets row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &Connection, row: &SnippetRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO snippets (id, title, command, description, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
         ON CONFLICT(id) DO UPDATE SET \
           title = excluded.title, \
           command = excluded.command, \
           description = excluded.description, \
           updated_at = excluded.updated_at",
        params![
            row.id,
            row.title,
            row.command,
            row.description,
            row.created_at_ms,
            row.updated_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("snippets upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM snippets WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("snippets delete: {e}")))
}

pub fn delete_all(conn: &Connection) -> Result<usize, Error> {
    conn.execute("DELETE FROM snippets", [])
        .map_err(|e| Error::Io(format!("snippets delete_all: {e}")))
}

// ---- session_snippets M2M ----------------------------------------------

pub fn link_session_snippet(
    conn: &Connection,
    session_id: &str,
    snippet_id: &str,
) -> Result<(), Error> {
    conn.execute(
        "INSERT OR IGNORE INTO session_snippets (session_id, snippet_id) VALUES (?1, ?2)",
        params![session_id, snippet_id],
    )
    .map_err(|e| Error::Io(format!("session_snippets insert: {e}")))?;
    Ok(())
}

pub fn unlink_session_snippet(
    conn: &Connection,
    session_id: &str,
    snippet_id: &str,
) -> Result<usize, Error> {
    conn.execute(
        "DELETE FROM session_snippets WHERE session_id = ?1 AND snippet_id = ?2",
        params![session_id, snippet_id],
    )
    .map_err(|e| Error::Io(format!("session_snippets delete: {e}")))
}

/// All snippets pinned to a session, joined back to the snippets
/// table so callers don't have to do an N+1 lookup. Mirrors drift's
/// `SnippetDao::getForSession`.
pub fn list_for_session(conn: &Connection, session_id: &str) -> Result<Vec<SnippetRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT s.id, s.title, s.command, s.description, s.created_at, s.updated_at \
             FROM snippets s \
             INNER JOIN session_snippets ss ON ss.snippet_id = s.id \
             WHERE ss.session_id = ?1 \
             ORDER BY s.title ASC",
        )
        .map_err(|e| Error::Io(format!("snippets list_for_session prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Io(format!("snippets list_for_session query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("snippets list_for_session row: {e}")))?);
    }
    Ok(out)
}

pub fn list_session_snippet_ids(conn: &Connection, session_id: &str) -> Result<Vec<String>, Error> {
    let mut stmt = conn
        .prepare("SELECT snippet_id FROM session_snippets WHERE session_id = ?1")
        .map_err(|e| Error::Io(format!("session_snippets prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], |row| row.get::<_, String>(0))
        .map_err(|e| Error::Io(format!("session_snippets query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("session_snippets row: {e}")))?);
    }
    Ok(out)
}
