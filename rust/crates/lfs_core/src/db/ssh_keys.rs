//! SshKeys DAO. Mirrors `lib/core/db/dao/ssh_key_dao.dart` against
//! the same drift-shaped sqlite schema. The Dart KeyStore points at
//! this module via FRB so the same on-disk rows are read/written from
//! either side during the migration.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SshKeyRow {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    /// Unix-millis at create time. The drift schema stores a
    /// DateTime value as INTEGER milliseconds-since-epoch via
    /// `DateTimeColumn`'s default mapping.
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SshKeyRow> {
    Ok(SshKeyRow {
        id: row.get("id")?,
        label: row.get("label")?,
        private_key: row.get("private_key")?,
        public_key: row.get("public_key")?,
        key_type: row.get("key_type")?,
        // drift maps Bool to int 0/1
        is_generated: row.get::<_, i64>("is_generated")? != 0,
        created_at_ms: row.get("created_at")?,
    })
}

pub fn list_all(conn: &Connection) -> Result<Vec<SshKeyRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Io(format!("ssh_keys list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("ssh_keys list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("ssh_keys row: {e}")))?);
    }
    Ok(out)
}

pub fn get(conn: &Connection, id: &str) -> Result<Option<SshKeyRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at \
             FROM ssh_keys WHERE id = ?1",
        )
        .map_err(|e| Error::Io(format!("ssh_keys get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], row_from)
        .map_err(|e| Error::Io(format!("ssh_keys get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Io(format!("ssh_keys get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &Connection, row: &SshKeyRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           private_key = excluded.private_key, \
           public_key = excluded.public_key, \
           key_type = excluded.key_type, \
           is_generated = excluded.is_generated, \
           created_at = excluded.created_at",
        params![
            row.id,
            row.label,
            row.private_key,
            row.public_key,
            row.key_type,
            if row.is_generated { 1 } else { 0 },
            row.created_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("ssh_keys upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    let n = conn
        .execute("DELETE FROM ssh_keys WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("ssh_keys delete: {e}")))?;
    Ok(n)
}
