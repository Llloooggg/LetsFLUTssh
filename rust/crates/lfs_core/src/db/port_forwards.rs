//! PortForwardRules DAO. Mirrors
//! `lib/core/db/dao/port_forward_rule_dao.dart`.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct PortForwardRuleRow {
    pub id: String,
    pub session_id: String,
    pub kind: String,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub description: String,
    pub enabled: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<PortForwardRuleRow> {
    Ok(PortForwardRuleRow {
        id: row.get("id")?,
        session_id: row.get("session_id")?,
        kind: row.get("kind")?,
        bind_host: row.get("bind_host")?,
        bind_port: row.get("bind_port")?,
        remote_host: row.get("remote_host")?,
        remote_port: row.get("remote_port")?,
        description: row.get("description")?,
        enabled: row.get::<_, i64>("enabled")? != 0,
        sort_order: row.get("sort_order")?,
        created_at_ms: row.get("created_at")?,
    })
}

const SELECT_COLS: &str =
    "id, session_id, kind, bind_host, bind_port, remote_host, remote_port, description, \
     enabled, sort_order, created_at";

pub fn list_for_session(
    conn: &Connection,
    session_id: &str,
) -> Result<Vec<PortForwardRuleRow>, Error> {
    let mut stmt = conn
        .prepare(&format!(
            "SELECT {SELECT_COLS} FROM port_forward_rules \
             WHERE session_id = ?1 ORDER BY sort_order ASC, created_at ASC"
        ))
        .map_err(|e| Error::Io(format!("port_forwards prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Io(format!("port_forwards query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("port_forwards row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &Connection, row: &PortForwardRuleRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO port_forward_rules (id, session_id, kind, bind_host, bind_port, \
           remote_host, remote_port, description, enabled, sort_order, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11) \
         ON CONFLICT(id) DO UPDATE SET \
           session_id = excluded.session_id, \
           kind = excluded.kind, \
           bind_host = excluded.bind_host, \
           bind_port = excluded.bind_port, \
           remote_host = excluded.remote_host, \
           remote_port = excluded.remote_port, \
           description = excluded.description, \
           enabled = excluded.enabled, \
           sort_order = excluded.sort_order",
        params![
            row.id,
            row.session_id,
            row.kind,
            row.bind_host,
            row.bind_port,
            row.remote_host,
            row.remote_port,
            row.description,
            if row.enabled { 1 } else { 0 },
            row.sort_order,
            row.created_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("port_forwards upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM port_forward_rules WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("port_forwards delete: {e}")))
}
