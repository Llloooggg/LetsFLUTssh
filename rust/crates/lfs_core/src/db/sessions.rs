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

/// What got staged into the [`crate::secrets::SecretStore`] by
/// [`stage_secrets_into_store`]. The bools tell the caller which
/// `SshAuth*Ref` variant to construct without needing to read the
/// columns themselves.
#[derive(Debug, Clone, Default)]
pub struct StagedSecrets {
    pub auth_type: String,
    pub has_password: bool,
    pub has_key_data: bool,
    pub has_passphrase: bool,
}

/// Read `password` / `key_data` / `passphrase` for a saved session
/// and push every non-empty field into the process-singleton secret
/// store under the canonical `sess.<slot>.<id>` ids. Plaintext bytes
/// never cross the FRB boundary back to Dart — only the bool flags
/// describing which slots were staged. The caller then dispatches
/// to the matching `SshAuth*Ref` connect variant.
///
/// Returns `Ok(None)` when the session row is missing.
pub fn stage_secrets_into_store(
    conn: &Connection,
    session_id: &str,
) -> Result<Option<StagedSecrets>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT auth_type, password, key_data, passphrase \
             FROM sessions WHERE id = ?1",
        )
        .map_err(|e| Error::Io(format!("sessions stage_secrets prepare: {e}")))?;
    let row: Option<(String, String, String, String)> = stmt
        .query_row(params![session_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .ok();
    let Some((auth_type, password, key_data, passphrase)) = row else {
        return Ok(None);
    };

    let store = &crate::app::instance().secrets;
    let has_password = !password.is_empty();
    if has_password {
        store.put(&format!("sess.password.{session_id}"), password.as_bytes());
    }
    let has_key_data = !key_data.is_empty();
    if has_key_data {
        store.put(&format!("sess.key.{session_id}"), key_data.as_bytes());
    }
    let has_passphrase = !passphrase.is_empty();
    if has_passphrase {
        store.put(
            &format!("sess.passphrase.{session_id}"),
            passphrase.as_bytes(),
        );
    }

    Ok(Some(StagedSecrets {
        auth_type,
        has_password,
        has_key_data,
        has_passphrase,
    }))
}

/// Plain-data view of a session row used by [`update_metadata`].
/// The credential columns (`password` / `key_data` / `passphrase`)
/// are deliberately absent — they are owned by
/// [`set_secret_column`] / [`stage_secrets_into_store`] so that
/// metadata edits never need to round-trip plaintext.
#[derive(Debug, Clone)]
pub struct SessionMetadata {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub key_path: String,
    pub key_id: Option<String>,
    pub sort_order: i64,
    pub notes: String,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub updated_at_ms: i64,
}

/// Update the non-credential metadata of a session in place. The
/// `password` / `key_data` / `passphrase` columns are deliberately
/// untouched — credential edits go through [`set_secret_column`]
/// instead, so the edit dialog can save metadata changes without
/// having to first read the existing secret bytes onto the Dart
/// heap and write them back.
pub fn update_metadata(conn: &Connection, m: &SessionMetadata) -> Result<usize, Error> {
    conn.execute(
        "UPDATE sessions SET \
           label = ?1, folder_id = ?2, host = ?3, port = ?4, user = ?5, \
           auth_type = ?6, key_path = ?7, key_id = ?8, sort_order = ?9, \
           notes = ?10, extras = ?11, via_session_id = ?12, via_host = ?13, \
           via_port = ?14, via_user = ?15, updated_at = ?16 \
         WHERE id = ?17",
        params![
            m.label,
            m.folder_id,
            m.host,
            m.port,
            m.user,
            m.auth_type,
            m.key_path,
            m.key_id,
            m.sort_order,
            m.notes,
            m.extras,
            m.via_session_id,
            m.via_host,
            m.via_port,
            m.via_user,
            m.updated_at_ms,
            m.id,
        ],
    )
    .map_err(|e| Error::Io(format!("sessions update_metadata: {e}")))
}

/// Replace a single credential column on a session row. `slot` is one
/// of `"password"`, `"key_data"`, `"passphrase"`. Empty `value` writes
/// an empty string (clears the credential). `value` reaches us
/// through FRB but never crosses back to Dart — combined with
/// [`stage_secrets_into_store`] this lets the edit dialog save a new
/// password without ever pre-filling the old one onto the Dart heap.
/// Returns rows affected (1 on success, 0 on missing row, error on
/// unrecognised slot).
pub fn set_secret_column(
    conn: &Connection,
    id: &str,
    slot: &str,
    value: &str,
    updated_at_ms: i64,
) -> Result<usize, Error> {
    let column = match slot {
        "password" => "password",
        "key_data" => "key_data",
        "passphrase" => "passphrase",
        other => return Err(Error::Io(format!("unknown secret slot: {other}"))),
    };
    let sql = format!("UPDATE sessions SET {column} = ?1, updated_at = ?2 WHERE id = ?3");
    conn.execute(&sql, params![value, updated_at_ms, id])
        .map_err(|e| Error::Io(format!("sessions set_secret_column: {e}")))
}

/// Copy a session row by id, allocating a new id + label and
/// optionally relocating into `target_folder_id`. Credentials
/// (`password` / `key_data` / `passphrase`) flow column-to-column
/// inside SQLite without crossing back to Dart — eliminates the
/// brief plaintext window the Dart-side `loadWithCredentials` →
/// `duplicate()` → `add()` path used to open. Returns "session
/// missing" when the source row has been deleted.
pub fn duplicate_session(
    conn: &Connection,
    src_id: &str,
    new_id: &str,
    new_label: &str,
    target_folder_id: Option<&str>,
    now_ms: i64,
) -> Result<(), Error> {
    let n = conn
        .execute(
            "INSERT INTO sessions ( \
               id, label, folder_id, host, port, user, auth_type, password, \
               key_path, key_data, key_id, passphrase, sort_order, notes, \
               last_connected_at, extras, via_session_id, via_host, via_port, \
               via_user, created_at, updated_at \
             ) \
             SELECT \
               ?1 AS id, ?2 AS label, ?3 AS folder_id, host, port, user, auth_type, \
               password, key_path, key_data, key_id, passphrase, sort_order, notes, \
               NULL AS last_connected_at, extras, via_session_id, via_host, \
               via_port, via_user, ?4 AS created_at, ?4 AS updated_at \
             FROM sessions WHERE id = ?5",
            params![new_id, new_label, target_folder_id, now_ms, src_id],
        )
        .map_err(|e| Error::Io(format!("sessions duplicate: {e}")))?;
    if n == 0 {
        return Err(Error::Io("sessions duplicate: source row missing".into()));
    }
    Ok(())
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
