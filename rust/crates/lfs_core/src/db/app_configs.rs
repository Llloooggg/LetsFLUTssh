//! AppConfigs DAO. Single-row blob table — id is forced to 1.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct AppConfigRow {
    pub data: String,
    pub updated_at_ms: i64,
    pub auto_lock_minutes: i64,
}

pub fn get(conn: &Connection) -> Result<Option<AppConfigRow>, Error> {
    let mut stmt = conn
        .prepare("SELECT data, updated_at, auto_lock_minutes FROM app_configs WHERE id = 1")
        .map_err(|e| Error::Io(format!("app_configs prepare: {e}")))?;
    let mut rows = stmt
        .query_map([], |row| {
            Ok(AppConfigRow {
                data: row.get("data")?,
                updated_at_ms: row.get("updated_at")?,
                auto_lock_minutes: row.get("auto_lock_minutes")?,
            })
        })
        .map_err(|e| Error::Io(format!("app_configs query: {e}")))?;
    match rows.next() {
        Some(Ok(r)) => Ok(Some(r)),
        Some(Err(e)) => Err(Error::Io(format!("app_configs row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &Connection, row: &AppConfigRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO app_configs (id, data, updated_at, auto_lock_minutes) \
         VALUES (1, ?1, ?2, ?3) \
         ON CONFLICT(id) DO UPDATE SET \
           data = excluded.data, \
           updated_at = excluded.updated_at, \
           auto_lock_minutes = excluded.auto_lock_minutes",
        params![row.data, row.updated_at_ms, row.auto_lock_minutes],
    )
    .map_err(|e| Error::Io(format!("app_configs upsert: {e}")))?;
    Ok(())
}
