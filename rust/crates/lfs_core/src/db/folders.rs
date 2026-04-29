//! Folders DAO. Mirrors `lib/core/db/dao/folder_dao.dart`.

use rusqlite::{params, Connection};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct FolderRow {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub sort_order: i64,
    pub collapsed: bool,
    pub created_at_ms: i64,
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<FolderRow> {
    Ok(FolderRow {
        id: row.get("id")?,
        name: row.get("name")?,
        parent_id: row.get("parent_id")?,
        sort_order: row.get("sort_order")?,
        collapsed: row.get::<_, i64>("collapsed")? != 0,
        created_at_ms: row.get("created_at")?,
    })
}

pub fn list_all(conn: &Connection) -> Result<Vec<FolderRow>, Error> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, parent_id, sort_order, collapsed, created_at \
             FROM folders ORDER BY sort_order ASC, name ASC",
        )
        .map_err(|e| Error::Io(format!("folders prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Io(format!("folders query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Io(format!("folders row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &Connection, row: &FolderRow) -> Result<(), Error> {
    conn.execute(
        "INSERT INTO folders (id, name, parent_id, sort_order, collapsed, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
         ON CONFLICT(id) DO UPDATE SET \
           name = excluded.name, \
           parent_id = excluded.parent_id, \
           sort_order = excluded.sort_order, \
           collapsed = excluded.collapsed, \
           created_at = excluded.created_at",
        params![
            row.id,
            row.name,
            row.parent_id,
            row.sort_order,
            if row.collapsed { 1 } else { 0 },
            row.created_at_ms,
        ],
    )
    .map_err(|e| Error::Io(format!("folders upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute("DELETE FROM folders WHERE id = ?1", params![id])
        .map_err(|e| Error::Io(format!("folders delete: {e}")))
}

pub fn delete_all(conn: &Connection) -> Result<usize, Error> {
    conn.execute("DELETE FROM folders", [])
        .map_err(|e| Error::Io(format!("folders delete_all: {e}")))
}

/// Walk a `/`-separated `path` (e.g. `infra/prod/web`) and ensure
/// every segment exists as a folder row, returning the id of the
/// leaf segment. Empty `path` returns `Ok(None)` (root-level).
///
/// Each missing segment gets a fresh 16-byte random id (same shape
/// `apply_folder_tree` mints); existing segments resolve by
/// `(parent_id, name)` lookup against the in-memory list this
/// function loads at the top of the call. Caller wraps the call
/// in a transaction when atomicity matters — the per-segment upsert
/// below is not transactional on its own.
///
/// Mirrors the Dart `resolveFolderPath` helper byte-for-byte so a
/// composite session-duplicate / session-add command can resolve the
/// folder path Rust-side without round-tripping through the FRB DAO
/// surface.
pub fn ensure_folder_path(
    conn: &Connection,
    path: &str,
    now_ms: i64,
) -> Result<Option<String>, Error> {
    if path.is_empty() {
        return Ok(None);
    }
    use rand::RngCore;
    let folders = list_all(conn)?;
    let mut by_parent: std::collections::HashMap<(Option<String>, String), String> =
        std::collections::HashMap::new();
    for f in &folders {
        by_parent.insert((f.parent_id.clone(), f.name.clone()), f.id.clone());
    }
    let mut parent_id: Option<String> = None;
    for seg in path.split('/').filter(|s| !s.is_empty()) {
        let key = (parent_id.clone(), seg.to_string());
        if let Some(existing) = by_parent.get(&key) {
            parent_id = Some(existing.clone());
            continue;
        }
        let mut bytes = [0u8; 16];
        rand::rngs::OsRng.fill_bytes(&mut bytes);
        let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
        let row = FolderRow {
            id: id.clone(),
            name: seg.to_string(),
            parent_id: parent_id.clone(),
            sort_order: 0,
            collapsed: false,
            created_at_ms: now_ms,
        };
        upsert(conn, &row)?;
        by_parent.insert(key, id.clone());
        parent_id = Some(id);
    }
    Ok(parent_id)
}

/// Flip the `collapsed` flag on a single folder. Returns the new
/// value (true = now collapsed) so the caller can update its cache
/// without a follow-up read. Empty `Ok(0)` if the row is missing.
pub fn toggle_collapsed(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute(
        "UPDATE folders SET collapsed = CASE collapsed WHEN 0 THEN 1 ELSE 0 END \
         WHERE id = ?1",
        params![id],
    )
    .map_err(|e| Error::Io(format!("folders toggle_collapsed: {e}")))
}

/// Update name and/or parent_id. Either field may stay the same; the
/// caller passes the desired values verbatim.
pub fn update_name_parent(
    conn: &Connection,
    id: &str,
    name: &str,
    parent_id: Option<&str>,
) -> Result<usize, Error> {
    conn.execute(
        "UPDATE folders SET name = ?1, parent_id = ?2 WHERE id = ?3",
        params![name, parent_id, id],
    )
    .map_err(|e| Error::Io(format!("folders update_name_parent: {e}")))
}

/// Delete `id` and every descendant in the parent_id tree. Uses a
/// recursive CTE so the round-trip count is one regardless of tree
/// depth — same shape drift's `getDescendantIds` paired with a
/// follow-up `IN (...)` delete.
pub fn delete_recursive(conn: &Connection, id: &str) -> Result<usize, Error> {
    conn.execute(
        "WITH RECURSIVE descendants(id) AS ( \
           SELECT id FROM folders WHERE id = ?1 \
           UNION ALL \
           SELECT f.id FROM folders f \
             INNER JOIN descendants d ON f.parent_id = d.id \
         ) \
         DELETE FROM folders WHERE id IN (SELECT id FROM descendants)",
        params![id],
    )
    .map_err(|e| Error::Io(format!("folders delete_recursive: {e}")))
}
