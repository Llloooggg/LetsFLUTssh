//! Sessions DAO. Mirrors `lib/core/db/dao/session_dao.dart`.
//! Largest table — 20+ columns including the FK to folders /
//! ssh_keys / self (ProxyJump bastion).
//!
//! **Secret-store angle**: the `password`, `key_data`, `passphrase`
//! columns will eventually move out of this table into the
//! SecretStore (the row carries opaque ids; plaintext lives only
//! in Rust). For now the DAO mirrors drift's plaintext columns
//! verbatim so the data backfill can do a straight copy; the
//! follow-up adds an `auth_secret_id` column and drops the
//! plaintext ones.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SessionRow {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    /// JSON object — see drift `extras` column.
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SessionRow> {
    Ok(SessionRow {
        id: row.get("id")?,
        label: row.get("label")?,
        folder_id: row.get("folder_id")?,
        host: row.get("host")?,
        port: row.get("port")?,
        user: row.get("user")?,
        auth_type: row.get("auth_type")?,
        password: row.get("password")?,
        key_path: row.get("key_path")?,
        key_data: row.get("key_data")?,
        key_id: row.get("key_id")?,
        passphrase: row.get("passphrase")?,
        sort_order: row.get("sort_order")?,
        notes: row.get("notes")?,
        last_connected_at_ms: row.get("last_connected_at")?,
        extras: row.get("extras")?,
        via_session_id: row.get("via_session_id")?,
        via_host: row.get("via_host")?,
        via_port: row.get("via_port")?,
        via_user: row.get("via_user")?,
        created_at_ms: row.get("created_at")?,
        updated_at_ms: row.get("updated_at")?,
    })
}

const SELECT_COLS: &str =
    "id, label, folder_id, host, port, user, auth_type, password, key_path, key_data, key_id, \
     passphrase, sort_order, notes, last_connected_at, extras, via_session_id, via_host, \
     via_port, via_user, created_at, updated_at";

pub fn list_all(conn: &Connection) -> Result<Vec<SessionRow>, Error> {
    let mut stmt = conn
        .prepare(&format!(
            "SELECT {SELECT_COLS} FROM sessions ORDER BY sort_order ASC, label ASC"
        ))
        .map_err(|e| Error::Io(format!("sessions prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("sessions query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("sessions row: {e}")))?);
    }
    Ok(out)
}

pub fn get(conn: &Connection, id: &str) -> Result<Option<SessionRow>, Error> {
    let mut stmt = conn
        .prepare(&format!("SELECT {SELECT_COLS} FROM sessions WHERE id = ?1"))
        .map_err(|e| Error::Io(format!("sessions get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], row_from)
        .map_err(|e| Error::Io(format!("sessions get query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Io(format!("sessions get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &Connection, row: &SessionRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO sessions (id, label, folder_id, host, port, user, auth_type, password, \
           key_path, key_data, key_id, passphrase, sort_order, notes, last_connected_at, \
           extras, via_session_id, via_host, via_port, via_user, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, \
           ?18, ?19, ?20, ?21, ?22) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           folder_id = excluded.folder_id, \
           host = excluded.host, \
           port = excluded.port, \
           user = excluded.user, \
           auth_type = excluded.auth_type, \
           password = excluded.password, \
           key_path = excluded.key_path, \
           key_data = excluded.key_data, \
           key_id = excluded.key_id, \
           passphrase = excluded.passphrase, \
           sort_order = excluded.sort_order, \
           notes = excluded.notes, \
           last_connected_at = excluded.last_connected_at, \
           extras = excluded.extras, \
           via_session_id = excluded.via_session_id, \
           via_host = excluded.via_host, \
           via_port = excluded.via_port, \
           via_user = excluded.via_user, \
           updated_at = excluded.updated_at",
        params![
            row.id,
            row.label,
            row.folder_id,
            row.host,
            row.port,
            row.user,
            row.auth_type,
            row.password,
            row.key_path,
            row.key_data,
            row.key_id,
            row.passphrase,
            row.sort_order,
            row.notes,
            row.last_connected_at_ms,
            row.extras,
            row.via_session_id,
            row.via_host,
            row.via_port,
            row.via_user,
            row.created_at_ms,
            row.updated_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("sessions upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM sessions WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("sessions delete: {e}")))
}

/// Bulk delete by id list. Empty input is a cheap no-op (no SQL).
pub fn delete_multiple(conn: &Connection, ids: &[String]) -> Result<usize, Error> {
    if ids.is_empty() {
        return Ok(0);
    }
    let placeholders = vec!["?"; ids.len()].join(",");
    let sql = format!("DELETE FROM sessions WHERE id IN ({placeholders})");
    let params_vec: Vec<&dyn rusqlite::ToSql> =
        ids.iter().map(|s| s as &dyn rusqlite::ToSql).collect();
    conn.execute(&sql, params_vec.as_slice())
        .map_err(|e| Error::Io(format!("sessions delete_multiple: {e}")))
}

pub fn delete_all(conn: &Connection) -> Result<usize, Error> {
    conn.execute("DELETE FROM sessions", [])
        .map_err(|e| Error::Io(format!("sessions delete_all: {e}")))
}

/// Set `folder_id` for a single session, refreshing `updated_at`.
pub fn move_to_folder(
    conn: &Connection,
    session_id: &str,
    folder_id: Option<&str>,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    conn.execute(
        "UPDATE sessions SET folder_id = ?1, updated_at = ?2 WHERE id = ?3",
        params![folder_id, updated_at_ms, session_id],
    )
    .map_err(|e| Error::Io(format!("sessions move_to_folder: {e}")))
}

/// Bulk variant of [`move_to_folder`].
pub fn move_multiple(
    conn: &Connection,
    ids: &[String],
    folder_id: Option<&str>,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    if ids.is_empty() {
        return Ok(0);
    }
    let placeholders = vec!["?"; ids.len()].join(",");
    let sql =
        format!("UPDATE sessions SET folder_id = ?1, updated_at = ?2 WHERE id IN ({placeholders})");
    let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(2 + ids.len());
    params_vec.push(&folder_id as &dyn rusqlite::ToSql);
    params_vec.push(&updated_at_ms as &dyn rusqlite::ToSql);
    for id in ids {
        params_vec.push(id as &dyn rusqlite::ToSql);
    }
    conn.execute(&sql, params_vec.as_slice())
        .map_err(|e| Error::Io(format!("sessions move_multiple: {e}")))
}
