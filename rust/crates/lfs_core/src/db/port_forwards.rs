//! PortForwardRules DAO. Mirrors
//! `lib/core/db/dao/port_forward_rule_dao.dart`.
//!
//! **Tombstone discipline.** `delete` flips `deleted_at` to
//! `now_unix_ms()` instead of issuing `DELETE FROM`; the row
//! survives the call so the sync layer (`§8b`) can replay the
//! removal across devices. `upsert` clears the tombstone + bumps
//! `updated_at` so the LWW gate on the receiving device sees a
//! revival rather than a stale wakeup. `purge_tombstones` is the
//! teardown that physically removes rows whose `deleted_at` is
//! older than the threshold.

use rusqlite::params;

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
    pub updated_at_ms: i64,
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
        updated_at_ms: row.get("updated_at")?,
    })
}

const SELECT_COLS: &str =
    "id, session_id, kind, bind_host, bind_port, remote_host, remote_port, description, \
     enabled, sort_order, created_at, updated_at";

pub fn list_for_session(
    conn: &impl crate::db::DbAccess,
    session_id: &str,
) -> Result<Vec<PortForwardRuleRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SELECT_COLS} FROM port_forward_rules \
             WHERE session_id = ?1 AND deleted_at IS NULL \
             ORDER BY sort_order ASC, created_at ASC"
        ))
        .map_err(|e| Error::Db(format!("port_forwards prepare: {e}")))?;
    let rows = stmt
        .query_map(params![session_id], row_from)
        .map_err(|e| Error::Db(format!("port_forwards query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("port_forwards row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &PortForwardRuleRow) -> Result<(), Error> {
    upsert_with_stamp(conn, row, now_unix_ms())
}

/// Same as [`upsert`] but with an explicit `updated_at_ms` stamp.
/// Used by the sync apply path so the receiver records the peer's
/// timestamp instead of a fresh local one.
pub fn upsert_with_stamp(
    conn: &impl crate::db::DbAccess,
    row: &PortForwardRuleRow,
    updated_at_ms: i64,
) -> Result<(), Error> {
    conn.raw()
        .execute(
            "INSERT INTO port_forward_rules (id, session_id, kind, bind_host, bind_port, \
           remote_host, remote_port, description, enabled, sort_order, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) \
         ON CONFLICT(id) DO UPDATE SET \
           session_id = excluded.session_id, \
           kind = excluded.kind, \
           bind_host = excluded.bind_host, \
           bind_port = excluded.bind_port, \
           remote_host = excluded.remote_host, \
           remote_port = excluded.remote_port, \
           description = excluded.description, \
           enabled = excluded.enabled, \
           sort_order = excluded.sort_order, \
           updated_at = excluded.updated_at, \
           deleted_at = NULL",
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
                updated_at_ms,
            ],
        )
        .map_err(|e| Error::Db(format!("port_forwards upsert: {e}")))?;
    Ok(())
}

/// Soft-delete a single rule by id. Flips `deleted_at` to
/// `now_unix_ms()` and bumps `updated_at` so the sync layer's LWW
/// gate sees a strictly newer stamp; the row survives so a sync
/// replay can carry the tombstone to peer devices.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE port_forward_rules SET deleted_at = ?1, updated_at = ?1 \
             WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("port_forwards delete: {e}")))
}

/// Soft-delete every live rule. Tombstones share one stamp so the
/// bulk-clear is a single point on the sync timeline. Used by the
/// archive-import replace mode before re-populating.
pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    conn.raw()
        .execute(
            "UPDATE port_forward_rules SET deleted_at = ?1, updated_at = ?1 \
             WHERE deleted_at IS NULL",
            params![now_ms],
        )
        .map_err(|e| Error::Db(format!("port_forwards delete_all: {e}")))
}

/// List every rule across every session, ordered by `session_id`
/// then `sort_order` then `created_at`. Used by the archive composer
/// to fold every rule into one JSON payload. Includes tombstoned
/// rows so a Sync compose can emit them; archive-mode composers
/// filter them upstream.
pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<PortForwardRuleRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SELECT_COLS} FROM port_forward_rules \
             WHERE deleted_at IS NULL \
             ORDER BY session_id ASC, sort_order ASC, created_at ASC"
        ))
        .map_err(|e| Error::Db(format!("port_forwards list_all prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("port_forwards list_all query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("port_forwards list_all row: {e}")))?);
    }
    Ok(out)
}

/// List every rule including tombstoned ones, paired with the
/// `deleted_at` stamp. Sync composers emit tombstoned rows so a
/// peer device can replay the removal; archive composers filter
/// out tombstones to keep the wire payload to live rows.
pub fn list_all_with_tombstones(
    conn: &impl crate::db::DbAccess,
) -> Result<Vec<(PortForwardRuleRow, Option<i64>)>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(&format!(
            "SELECT {SELECT_COLS}, deleted_at FROM port_forward_rules \
             ORDER BY session_id ASC, sort_order ASC, created_at ASC"
        ))
        .map_err(|e| {
            Error::Db(format!(
                "port_forwards list_all_with_tombstones prepare: {e}"
            ))
        })?;
    let rows = stmt
        .query_map([], |r| {
            let row = row_from(r)?;
            let deleted_at: Option<i64> = r.get("deleted_at")?;
            Ok((row, deleted_at))
        })
        .map_err(|e| Error::Db(format!("port_forwards list_all_with_tombstones query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(
            r.map_err(|e| Error::Db(format!("port_forwards list_all_with_tombstones row: {e}")))?,
        );
    }
    Ok(out)
}

/// Apply a tombstone with an explicit stamp. Used by the sync apply
/// path when a peer ships a `deleted_at` value; the local row's
/// `updated_at` is bumped to match so the LWW gate cannot pick a
/// stale revival.
pub fn apply_tombstone(
    conn: &impl crate::db::DbAccess,
    id: &str,
    deleted_at_ms: i64,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE port_forward_rules SET deleted_at = ?1, updated_at = ?1 \
             WHERE id = ?2 AND (updated_at IS NULL OR updated_at < ?1)",
            params![deleted_at_ms, id],
        )
        .map_err(|e| Error::Db(format!("port_forwards apply_tombstone: {e}")))
}

/// Physically remove rules whose `deleted_at` is older than
/// `before_ms`. Reserved for sync-merge teardown.
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM port_forward_rules \
             WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("port_forwards purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` /
/// `updated_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tombstone_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Connection, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn insert_session_raw(db: &Db, id: &str) {
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "INSERT INTO sessions (id, created_at, updated_at) VALUES (?1, ?2, ?2)",
                    params![id, 0_i64],
                )
                .map(|_| ())
                .map_err(|e| crate::error::Error::Db(format!("insert session: {e}")))
        })
        .unwrap();
    }

    fn seed(db: &Db, id: &str, session_id: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &PortForwardRuleRow {
                    id: id.into(),
                    session_id: session_id.into(),
                    kind: "local".into(),
                    bind_host: "127.0.0.1".into(),
                    bind_port: 8080,
                    remote_host: "example.com".into(),
                    remote_port: 80,
                    description: String::new(),
                    enabled: true,
                    sort_order: 0,
                    created_at_ms: 0,
                    updated_at_ms: 0,
                },
            )
        })
        .unwrap();
    }

    fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
        db.with_conn(|c| {
            let row: Option<i64> = c
                .raw()
                .query_row(
                    "SELECT deleted_at FROM port_forward_rules WHERE id = ?1",
                    params![id],
                    |r| r.get(0),
                )
                .ok()
                .flatten();
            Ok(row)
        })
        .unwrap()
    }

    #[test]
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "pf1", "s1");
        let n = db.with_conn(|c| delete(c, "pf1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "pf1").is_some());
    }

    #[test]
    fn list_for_session_skips_tombstoned_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "alive", "s1");
        seed(&db, "dead", "s1");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn list_all_skips_tombstoned_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "alive", "s1");
        seed(&db, "dead", "s1");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn list_all_with_tombstones_keeps_tombstoned_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "alive", "s1");
        seed(&db, "dead", "s1");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all_with_tombstones).unwrap();
        assert_eq!(rows.len(), 2);
        let dead = rows.iter().find(|(r, _)| r.id == "dead").unwrap();
        assert!(dead.1.is_some());
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "pf1", "s1");
        db.with_conn(|c| delete(c, "pf1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "pf1").is_none());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        insert_session_raw(&db, "s1");
        seed(&db, "pf1", "s1");
        db.with_conn(|c| delete(c, "pf1")).unwrap();
        seed(&db, "pf1", "s1");
        let rows = db.with_conn(|c| list_for_session(c, "s1")).unwrap();
        assert_eq!(rows.len(), 1);
        assert!(raw_deleted_at(&db, "pf1").is_none());
    }

    #[test]
    fn apply_tombstone_lww_blocks_stale_stamp() {
        let db = db();
        insert_session_raw(&db, "s1");
        db.with_conn(|c| {
            upsert_with_stamp(
                c,
                &PortForwardRuleRow {
                    id: "pf1".into(),
                    session_id: "s1".into(),
                    kind: "local".into(),
                    bind_host: "127.0.0.1".into(),
                    bind_port: 8080,
                    remote_host: "example.com".into(),
                    remote_port: 80,
                    description: String::new(),
                    enabled: true,
                    sort_order: 0,
                    created_at_ms: 0,
                    updated_at_ms: 0,
                },
                100,
            )
        })
        .unwrap();
        // Stale peer tombstone (50 < local 100) is rejected.
        let n = db.with_conn(|c| apply_tombstone(c, "pf1", 50)).unwrap();
        assert_eq!(n, 0);
        assert!(raw_deleted_at(&db, "pf1").is_none());
        // Fresh peer tombstone (200 > local 100) lands.
        let n = db.with_conn(|c| apply_tombstone(c, "pf1", 200)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "pf1").is_some());
    }
}
