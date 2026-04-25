//! KnownHosts DAO — TOFU host-key cache. Mirrors
//! `lib/core/db/dao/known_host_dao.dart`. The `id` column is
//! AUTOINCREMENT so callers don't supply it on insert; lookups
//! (and the unique-key conflict resolution) go by `(host, port)`.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct KnownHostRow {
    pub id: i64,
    pub host: String,
    pub port: i64,
    pub key_type: String,
    pub key_base64: String,
    pub added_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<KnownHostRow> {
    Ok(KnownHostRow {
        id: row.get("id")?,
        host: row.get("host")?,
        port: row.get("port")?,
        key_type: row.get("key_type")?,
        key_base64: row.get("key_base64")?,
        added_at_ms: row.get("added_at")?,
    })
}

pub fn list_all(conn: &Connection) -> Result<Vec<KnownHostRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, host, port, key_type, key_base64, added_at \
             FROM known_hosts ORDER BY host ASC, port ASC",
        )
        .map_err(|e| Error::Io(format!("known_hosts prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("known_hosts query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("known_hosts row: {e}")))?);
    }
    Ok(out)
}

pub fn get_by_host_port(
    conn: &Connection,
    host: &str,
    port: i64,
) -> Result<Option<KnownHostRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, host, port, key_type, key_base64, added_at \
             FROM known_hosts WHERE host = ?1 AND port = ?2",
        )
        .map_err(|e| Error::Io(format!("known_hosts get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![host, port], row_from)
        .map_err(|e| Error::Io(format!("known_hosts get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Io(format!("known_hosts get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or update by `(host, port)` unique key. The auto-increment
/// `id` is irrelevant on conflict — we just refresh key material and
/// timestamp. Returns the row's id (existing or newly-allocated).
pub fn upsert_by_host_port(
    conn: &Connection,
    host: &str,
    port: i64,
    key_type: &str,
    key_base64: &str,
    added_at_ms: i64,
) -> Result<i64, Error> {
    conn.execute(
        "INSERT INTO known_hosts (host, port, key_type, key_base64, added_at) \
         VALUES (?1, ?2, ?3, ?4, ?5) \
         ON CONFLICT(host, port) DO UPDATE SET \
           key_type = excluded.key_type, \
           key_base64 = excluded.key_base64, \
           added_at = excluded.added_at",
        params![host, port, key_type, key_base64, added_at_ms],
    )
    .map_err(|e| Error::Io(format!("known_hosts upsert: {e}")))?;
    let id = conn
        .query_row(
            "SELECT id FROM known_hosts WHERE host = ?1 AND port = ?2",
            params![host, port],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| Error::Io(format!("known_hosts upsert select: {e}")))?;
    Ok(id)
}

pub fn delete_by_host_port(conn: &Connection, host: &str, port: i64) -> Result<usize, Error> {
    conn.execute(
        "DELETE FROM known_hosts WHERE host = ?1 AND port = ?2",
        params![host, port],
    )
    .map_err(|e| Error::Io(format!("known_hosts delete: {e}")))
}

pub fn clear_all(conn: &Connection) -> Result<usize, Error> {
    conn.execute("DELETE FROM known_hosts", [])
        .map_err(|e| Error::Io(format!("known_hosts clear_all: {e}")))
}
