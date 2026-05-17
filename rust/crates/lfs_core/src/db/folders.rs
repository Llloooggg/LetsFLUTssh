//! Folders DAO. Mirrors `lib/core/db/dao/folder_dao.dart`.

use crate::db::Connection;
use rusqlite::params;

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

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<FolderRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, name, parent_id, sort_order, collapsed, created_at \
             FROM folders ORDER BY sort_order ASC, name ASC",
        )
        .map_err(|e| Error::Db(format!("folders prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("folders query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("folders row: {e}")))?);
    }
    Ok(out)
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &FolderRow) -> Result<(), Error> {
    conn.raw()
        .execute(
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
        .map_err(|e| Error::Db(format!("folders upsert: {e}")))?;
    Ok(())
}

pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    conn.raw()
        .execute("DELETE FROM folders WHERE id = ?1", params![id])
        .map_err(|e| Error::Db(format!("folders delete: {e}")))
}

pub fn delete_all(conn: &impl crate::db::DbAccess) -> Result<usize, Error> {
    conn.raw()
        .execute("DELETE FROM folders", [])
        .map_err(|e| Error::Db(format!("folders delete_all: {e}")))
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
    conn: &impl crate::db::DbAccess,
    path: &str,
    now_ms: i64,
) -> Result<Option<String>, Error> {
    if path.is_empty() {
        return Ok(None);
    }
    use rand::Rng;
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
        rand::rng().fill_bytes(&mut bytes);
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

/// Transactional wrapper around [`ensure_folder_path`] for FRB
/// callers. Walks `path` segment-by-segment inside a single
/// `rusqlite::Transaction` so a crash or panic mid-walk leaves no
/// partially-resolved subtree — either every missing segment is
/// committed together with the leaf id, or none of them are.
///
/// Returns the leaf folder id, or `None` when `path` is empty
/// (root-level). The wall-clock time stamp is supplied by the
/// caller so test fixtures can pin `created_at`.
pub fn resolve_or_create_path(
    conn: &mut Connection,
    path: &str,
    now_ms: i64,
) -> Result<Option<String>, Error> {
    if path.is_empty() {
        return Ok(None);
    }
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("folders resolve_or_create_path tx: {e}")))?;
    let leaf = ensure_folder_path(&tx, path, now_ms)?;
    tx.commit()
        .map_err(|e| Error::Db(format!("folders resolve_or_create_path commit: {e}")))?;
    Ok(leaf)
}

/// Flip the `collapsed` flag on a single folder. Returns the new
/// value (true = now collapsed) so the caller can update its cache
/// without a follow-up read. Empty `Ok(0)` if the row is missing.
pub fn toggle_collapsed(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE folders SET collapsed = CASE collapsed WHEN 0 THEN 1 ELSE 0 END \
         WHERE id = ?1",
            params![id],
        )
        .map_err(|e| Error::Db(format!("folders toggle_collapsed: {e}")))
}

/// Update name and/or parent_id. Either field may stay the same; the
/// caller passes the desired values verbatim. Rejects cycles —
/// moving a folder under one of its own descendants would orphan
/// the rest of the subtree and (combined with [`delete_recursive`]'s
/// `UNION ALL` traversal) could otherwise spin a wipe forever.
pub fn update_name_parent(
    conn: &impl crate::db::DbAccess,
    id: &str,
    name: &str,
    parent_id: Option<&str>,
) -> Result<usize, Error> {
    if let Some(target) = parent_id {
        if target == id {
            return Err(Error::Db(format!(
                "folders update_name_parent: cycle — parent_id == id ({id})",
            )));
        }
        if is_descendant_of(conn, target, id)? {
            return Err(Error::Db(format!(
                "folders update_name_parent: cycle — refused to move {id} under its own descendant {target}",
            )));
        }
    }
    conn.raw()
        .execute(
            "UPDATE folders SET name = ?1, parent_id = ?2 WHERE id = ?3",
            params![name, parent_id, id],
        )
        .map_err(|e| Error::Db(format!("folders update_name_parent: {e}")))
}

/// Walk up `candidate.parent_id` chain looking for `ancestor`. Used
/// by [`update_name_parent`] to reject reparent operations that
/// would create a cycle. Bounded by the number of folder rows so
/// pre-existing on-disk cycles can't make this loop forever.
fn is_descendant_of(
    conn: &impl crate::db::DbAccess,
    candidate: &str,
    ancestor: &str,
) -> Result<bool, Error> {
    let mut current: Option<String> = Some(candidate.to_string());
    let mut hops: u32 = 0;
    let max_hops: u32 = 65_536;
    while let Some(id) = current.take() {
        if hops >= max_hops {
            return Err(Error::Io(
                "folders is_descendant_of: traversal hop cap exceeded — \
                 likely a pre-existing cycle in the parent_id chain"
                    .into(),
            ));
        }
        hops += 1;
        if id == ancestor {
            return Ok(true);
        }
        let parent: Option<String> = conn
            .raw()
            .query_row(
                "SELECT parent_id FROM folders WHERE id = ?1",
                params![id],
                |row| row.get(0),
            )
            .ok()
            .flatten();
        current = parent;
    }
    Ok(false)
}

/// Rename / move a folder from `old_path` to `new_path` in one
/// transaction. Resolves the existing folder by path, computes the
/// new name (last segment) + new parent path (everything before),
/// ensures the new parent path exists (creating segments as
/// needed), then updates the folder row.
///
/// Returns 1 on success, 0 when `old_path` resolves to no folder
/// (caller treats that as "nothing to rename"). Errors come from
/// the underlying DAOs.
///
/// Replaces the Dart `SessionStore.renameFolder` /
/// `moveFolder` two-step (`findFolderIdByPath` + manual
/// `dbFoldersUpdateNameParent` with a stale `parent_id` carried
/// from the row cache). The Dart caller passed the OLD parent_id
/// when moving across the tree — this helper computes the NEW
/// parent from the target path so move-across-the-tree actually
/// re-parents the row.
pub fn rename_path_cascade(
    conn: &mut Connection,
    old_path: &str,
    new_path: &str,
    now_ms: i64,
) -> Result<usize, Error> {
    if old_path.is_empty() || new_path.is_empty() || old_path == new_path {
        return Ok(0);
    }
    // Reject cycles: moving a folder under one of its own descendants
    // would orphan the rest of the subtree.
    if new_path.starts_with(&format!("{old_path}/")) {
        return Err(Error::Db(format!(
            "folders rename_path_cascade: refused to move {old_path} under its own descendant {new_path}",
        )));
    }
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("folders rename_path_cascade tx: {e}")))?;

    let folders = list_all(&tx)?;
    let folder_map: std::collections::BTreeMap<String, FolderRow> =
        folders.iter().map(|f| (f.id.clone(), f.clone())).collect();

    let folder_id = match crate::folder_path::find_folder_id_by_path(old_path, &folder_map) {
        Some(id) => id,
        None => return Ok(0),
    };

    let segments: Vec<&str> = new_path.split('/').filter(|s| !s.is_empty()).collect();
    if segments.is_empty() {
        return Err(Error::Db(format!(
            "folders rename_path_cascade: empty new_path after split: {new_path}",
        )));
    }
    let new_name = segments
        .last()
        .expect("non-empty by check above")
        .to_string();
    let new_parent_path = if segments.len() == 1 {
        String::new()
    } else {
        segments[..segments.len() - 1].join("/")
    };

    let new_parent_id = ensure_folder_path(&tx, &new_parent_path, now_ms)?;

    let n = update_name_parent(&tx, &folder_id, &new_name, new_parent_id.as_deref())?;
    tx.commit()
        .map_err(|e| Error::Db(format!("folders rename_path_cascade commit: {e}")))?;
    Ok(n)
}

/// Delete `id` and every descendant in the parent_id tree. Uses a
/// recursive CTE with `UNION` (deduplicating) so a pre-existing
/// cyclic `parent_id` chain (A → B → A) cannot push the recursive
/// term to walk forever. The schema CHECK + [`update_name_parent`]
/// cycle guard make a cycle write-impossible going forward, but
/// hand-edited DBs and pre-fix data could carry one — `UNION ALL`
/// would happily expand them until SQLite's internal recursion
/// ceiling, blocking the writer mutex on every wipe.
pub fn delete_recursive(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "WITH RECURSIVE descendants(id) AS ( \
           SELECT id FROM folders WHERE id = ?1 \
           UNION \
           SELECT f.id FROM folders f \
             INNER JOIN descendants d ON f.parent_id = d.id \
         ) \
         DELETE FROM folders WHERE id IN (SELECT id FROM descendants)",
            params![id],
        )
        .map_err(|e| Error::Db(format!("folders delete_recursive: {e}")))
}

#[cfg(test)]
mod rename_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn ensure(db: &Db, path: &str) -> String {
        db.with_conn(|c| ensure_folder_path(c, path, 0))
            .unwrap()
            .unwrap()
    }

    fn rename(db: &Db, old_p: &str, new_p: &str) -> Result<usize, crate::error::Error> {
        db.with_conn_mut(|c| rename_path_cascade(c, old_p, new_p, 100))
    }

    #[test]
    fn rename_renames_leaf_segment_only() {
        let db = db();
        let old_id = ensure(&db, "infra");
        let n = rename(&db, "infra", "platform").unwrap();
        assert_eq!(n, 1);
        let folders = db.with_conn(list_all).unwrap();
        let row = folders.iter().find(|f| f.id == old_id).unwrap();
        assert_eq!(row.name, "platform");
        assert!(row.parent_id.is_none());
    }

    #[test]
    fn rename_moves_across_tree_reparenting_correctly() {
        // The Dart-side bug: SessionStore.moveFolder routed through
        // renameFolder which passed the OLD parent_id back to the
        // DAO. The composite Rust helper here resolves the new
        // parent path directly so the row actually re-parents.
        let db = db();
        let original = ensure(&db, "infra/prod");
        ensure(&db, "infra/staging"); // ensure target parent exists
        rename(&db, "infra/prod", "infra/staging/prod").unwrap();

        let folders = db.with_conn(list_all).unwrap();
        let prod = folders.iter().find(|f| f.id == original).unwrap();
        assert_eq!(prod.name, "prod");
        let staging = folders.iter().find(|f| f.name == "staging").unwrap();
        assert_eq!(prod.parent_id.as_deref(), Some(staging.id.as_str()));
    }

    #[test]
    fn rename_creates_missing_parent_segments() {
        let db = db();
        let original = ensure(&db, "infra/prod");
        // New parent path doesn't exist yet — composite must mint
        // it inside the same transaction.
        rename(&db, "infra/prod", "platforms/cloud/prod").unwrap();

        let folders = db.with_conn(list_all).unwrap();
        let cloud = folders.iter().find(|f| f.name == "cloud").unwrap();
        let prod = folders.iter().find(|f| f.id == original).unwrap();
        assert_eq!(prod.parent_id.as_deref(), Some(cloud.id.as_str()));
    }

    #[test]
    fn rename_unknown_old_path_returns_zero() {
        let db = db();
        let n = rename(&db, "ghost", "real").unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn rename_under_own_descendant_errors() {
        // Moving infra/prod → infra/prod/leaf would orphan the
        // subtree. Rust helper rejects the cycle.
        let db = db();
        ensure(&db, "infra/prod");
        let err = rename(&db, "infra/prod", "infra/prod/leaf").unwrap_err();
        assert!(err.to_string().contains("descendant"));
    }

    #[test]
    fn rename_same_path_is_noop() {
        let db = db();
        ensure(&db, "infra/prod");
        let n = rename(&db, "infra/prod", "infra/prod").unwrap();
        assert_eq!(n, 0);
    }

    #[test]
    fn rename_empty_paths_are_noop() {
        let db = db();
        assert_eq!(rename(&db, "", "x").unwrap(), 0);
        assert_eq!(rename(&db, "x", "").unwrap(), 0);
    }

    /// Regression: the recursive CTE in [`delete_recursive`] used
    /// `UNION ALL` (no dedup) and `update_name_parent` skipped the
    /// cycle check, so a hand-edited
    /// or pre-fix DB carrying a cyclic `parent_id` chain (A → B → A)
    /// would loop the descendant traversal until SQLite's ceiling
    /// fired, blocking the writer mutex on every wipe attempt. The
    /// fix is two-fold: `update_name_parent` rejects cycles up
    /// front so live data can never reach the cyclic state; and
    /// `delete_recursive` switched to `UNION` (deduplicating) so
    /// pre-existing on-disk cycles still terminate.
    #[test]
    fn update_name_parent_rejects_self_cycle() {
        let db = db();
        let id = ensure(&db, "loopy");
        let err = db
            .with_conn(|c| update_name_parent(c, &id, "loopy", Some(&id)))
            .unwrap_err();
        assert!(err.to_string().contains("cycle"));
    }

    #[test]
    fn update_name_parent_rejects_descendant_cycle() {
        let db = db();
        ensure(&db, "infra/prod");
        let folders = db.with_conn(list_all).unwrap();
        let infra = folders.iter().find(|f| f.name == "infra").unwrap();
        let prod = folders.iter().find(|f| f.name == "prod").unwrap();
        // Try to make `infra` a child of `prod` (which is its child).
        let err = db
            .with_conn(|c| update_name_parent(c, &infra.id, "infra", Some(&prod.id)))
            .unwrap_err();
        assert!(err.to_string().contains("cycle"));
    }

    #[test]
    fn delete_recursive_terminates_on_pre_existing_cycle() {
        // Bypass `update_name_parent` to plant a cycle the way a
        // hand-edited DB or pre-fix data could carry one. Then
        // delete_recursive must terminate (the `UNION` dedup wins
        // over an infinite walk).
        let db = db();
        ensure(&db, "a");
        ensure(&db, "b");
        let folders = db.with_conn(list_all).unwrap();
        let a_id = folders.iter().find(|f| f.name == "a").unwrap().id.clone();
        let b_id = folders.iter().find(|f| f.name == "b").unwrap().id.clone();
        // Force the cycle directly via SQL: a.parent_id = b, b.parent_id = a.
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "UPDATE folders SET parent_id = ?1 WHERE id = ?2",
                    params![&b_id, &a_id],
                )
                .map_err(|e| crate::error::Error::Db(format!("plant cycle a: {e}")))
        })
        .unwrap();
        db.with_conn(|c| {
            c.raw()
                .execute(
                    "UPDATE folders SET parent_id = ?1 WHERE id = ?2",
                    params![&a_id, &b_id],
                )
                .map_err(|e| crate::error::Error::Db(format!("plant cycle b: {e}")))
        })
        .unwrap();

        // The deletion must complete in finite time (the test would
        // hang or hit SQLite's recursion ceiling under the old
        // `UNION ALL` body).
        let n = db.with_conn(|c| delete_recursive(c, &a_id)).unwrap();
        assert_eq!(n, 2, "both rows of the cycle should be deleted");
    }
}

#[cfg(test)]
mod resolve_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn resolve(db: &Db, path: &str) -> Option<String> {
        db.with_conn_mut(|c| resolve_or_create_path(c, path, 0))
            .unwrap()
    }

    #[test]
    fn resolve_empty_path_returns_none() {
        let db = db();
        assert!(resolve(&db, "").is_none());
        assert!(db.with_conn(list_all).unwrap().is_empty());
    }

    #[test]
    fn resolve_single_segment_creates_one_row() {
        let db = db();
        let id = resolve(&db, "infra").expect("leaf id");
        let folders = db.with_conn(list_all).unwrap();
        assert_eq!(folders.len(), 1);
        let row = &folders[0];
        assert_eq!(row.id, id);
        assert_eq!(row.name, "infra");
        assert!(row.parent_id.is_none());
    }

    #[test]
    fn resolve_multi_segment_creates_parent_chain() {
        let db = db();
        let leaf_id = resolve(&db, "infra/prod/web").expect("leaf id");
        let folders = db.with_conn(list_all).unwrap();
        assert_eq!(folders.len(), 3);
        let leaf = folders.iter().find(|f| f.id == leaf_id).unwrap();
        assert_eq!(leaf.name, "web");
        let prod = folders
            .iter()
            .find(|f| f.id == *leaf.parent_id.as_ref().unwrap())
            .unwrap();
        assert_eq!(prod.name, "prod");
        let infra = folders
            .iter()
            .find(|f| f.id == *prod.parent_id.as_ref().unwrap())
            .unwrap();
        assert_eq!(infra.name, "infra");
        assert!(infra.parent_id.is_none());
    }

    #[test]
    fn resolve_is_idempotent() {
        let db = db();
        let first = resolve(&db, "infra/prod").expect("first leaf");
        let second = resolve(&db, "infra/prod").expect("second leaf");
        assert_eq!(first, second);
        // The second call must not have created a duplicate row pair.
        assert_eq!(db.with_conn(list_all).unwrap().len(), 2);
    }
}
