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
mod tests {
    use super::*;
    use crate::db::{bootstrap_schema, Connection};

    fn fresh_conn() -> Connection {
        let conn = Connection::open_in_memory().expect("open in-memory db");
        bootstrap_schema(&conn).expect("bootstrap schema");
        conn
    }

    #[test]
    fn upsert_returns_stable_id_on_insert_and_update() {
        // First call inserts; second call hits the ON CONFLICT
        // arm and must return the same `id` so SFTP key-pin retries
        // converge on a single row.
        let conn = fresh_conn();
        let id_insert =
            upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "AAAA", 100).unwrap();
        let id_update =
            upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "BBBB", 200).unwrap();
        assert_eq!(
            id_insert, id_update,
            "RETURNING id must be stable across upsert"
        );

        let row = get_by_host_port(&conn, "host.example", 22)
            .unwrap()
            .unwrap();
        assert_eq!(row.id, id_insert);
        assert_eq!(
            row.key_base64, "BBBB",
            "second upsert overwrites key material"
        );
        assert_eq!(row.added_at_ms, 200, "second upsert overwrites timestamp");
    }

    #[test]
    fn upsert_distinct_host_port_pairs_get_distinct_ids() {
        let conn = fresh_conn();
        let id_a = upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "A", 0).unwrap();
        let id_b = upsert_by_host_port(&conn, "other.example", 22, "ssh-ed25519", "B", 0).unwrap();
        let id_c = upsert_by_host_port(&conn, "host.example", 2222, "ssh-rsa", "C", 0).unwrap();
        assert_ne!(id_a, id_b);
        assert_ne!(id_a, id_c);
        assert_ne!(id_b, id_c);
    }
}
