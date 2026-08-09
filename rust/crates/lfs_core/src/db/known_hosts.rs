//! KnownHosts DAO — TOFU host-key cache. Mirrors
//! `lib/core/db/dao/known_host_dao.dart`. The `id` column is
//! AUTOINCREMENT so callers don't supply it on insert; lookups
//! (and the unique-key conflict resolution) go by `(host, port)`.

use rusqlite::params;

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

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<KnownHostRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, host, port, key_type, key_base64, added_at \
             FROM known_hosts ORDER BY host ASC, port ASC",
        )
        .map_err(|e| Error::Db(format!("known_hosts prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("known_hosts query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("known_hosts row: {e}")))?);
    }
    Ok(out)
}

pub fn get_by_host_port(
    conn: &impl crate::db::DbAccess,
    host: &str,
    port: i64,
) -> Result<Option<KnownHostRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, host, port, key_type, key_base64, added_at \
             FROM known_hosts WHERE host = ?1 AND port = ?2",
        )
        .map_err(|e| Error::Db(format!("known_hosts get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![host, port], row_from)
        .map_err(|e| Error::Db(format!("known_hosts get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Db(format!("known_hosts get row: {e}"))),
        None => Ok(None),
    }
}

/// Insert or update by `(host, port)` unique key. The auto-increment
/// `id` is irrelevant on conflict — we just refresh key material and
/// timestamp. Returns the row's id (existing or newly-allocated).
///
/// SQLite 3.35+ (rusqlite 0.31 ships 3.45; SQLCipher 4.x rebases on
/// the same series) supports `RETURNING` on `INSERT ... ON CONFLICT
/// ... DO UPDATE`, so the id round-trip lands in a single statement.
pub fn upsert_by_host_port(
    conn: &impl crate::db::DbAccess,
    host: &str,
    port: i64,
    key_type: &str,
    key_base64: &str,
    added_at_ms: i64,
) -> Result<i64, Error> {
    conn.raw()
        .query_row(
            "INSERT INTO known_hosts (host, port, key_type, key_base64, added_at) \
             VALUES (?1, ?2, ?3, ?4, ?5) \
             ON CONFLICT(host, port) DO UPDATE SET \
               key_type = excluded.key_type, \
               key_base64 = excluded.key_base64, \
               added_at = excluded.added_at \
             RETURNING id",
            params![host, port, key_type, key_base64, added_at_ms],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| Error::Db(format!("known_hosts upsert: {e}")))
}

pub fn delete_by_host_port(
    conn: &impl crate::db::DbAccess,
    host: &str,
    port: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "DELETE FROM known_hosts WHERE host = ?1 AND port = ?2",
            params![host, port],
        )
        .map_err(|e| Error::Db(format!("known_hosts delete: {e}")))
}

pub fn clear_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    conn.raw()
        .execute("DELETE FROM known_hosts", [])
        .map_err(|e| Error::Db(format!("known_hosts clear_all: {e}")))
}
#[cfg(test)]
#[path = "../../tests/unit/db_known_hosts.rs"]
mod tests;
