//! Pure folder-tree → path-string helpers shared between the
//! Dart `SessionStore` cache view and the Rust persistence DAOs.
//!
//! The folder cache is a flat `id → FolderRow` map; user-visible
//! paths are the `Production/EU/web` strings the UI renders. Both
//! sides need to convert in both directions:
//!
//!   - `build_folder_path` walks parent_id chain → path string
//!   - `find_folder_id_by_path` exact-match reverse lookup
//!   - `all_folder_paths` enumerates the tree
//!   - `rename_paths_cascade` applies a rename across a path set,
//!     covering both the exact match and every child under the
//!     renamed prefix (used when the user drags a folder).
//!
//! Why Rust-canonical even though every caller is Dart today: the
//! Rust DAOs (`db::folders`) and the future `SessionRegistry` actor
//! both need to derive paths the same way the UI does — keeping the
//! helper Rust-side avoids two divergent implementations of the
//! orphan-path policy and the cascade-rename grammar.
//!
//! Orphan policy mirrors the Dart `_buildFolderPath` it replaces: a
//! `parent_id` pointing at a deleted row produces
//! `"(orphaned)/{partial}"` rather than truncating silently, so the
//! UI surfaces the inconsistency instead of dropping rows.

use std::collections::BTreeMap;

use crate::db::folders::FolderRow;

/// Walk the parent chain of [`folder_id`] and return the
/// slash-joined name path (`"Production/EU"`).
///
/// Returns the empty string when [`folder_id`] is empty (root
/// session). When a referenced parent is missing from [`folders`],
/// the partial path is prefixed with `(orphaned)/` so the
/// inconsistency stays visible at the UI layer.
#[must_use]
pub fn build_folder_path(folder_id: &str, folders: &BTreeMap<String, FolderRow>) -> String {
    if folder_id.is_empty() {
        return String::new();
    }
    let mut parts: Vec<String> = Vec::new();
    let mut visited: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut current: Option<String> = Some(folder_id.to_string());
    while let Some(id) = current {
        // A cyclic `parent_id` chain (both rows present, e.g. a
        // hand-edited or pre-fix DB) would otherwise loop forever and
        // grow `parts` without bound. Bail on revisit — mirrors the
        // guards on the write-side folder walkers in `db::folders`
        // (`is_descendant_of` hop cap, `delete_recursive` UNION
        // dedup); this read-side walker runs on every session-list
        // render, so an unguarded cycle hangs the UI.
        if !visited.insert(id.clone()) {
            parts.reverse();
            return format!("(cycle)/{}", parts.join("/"));
        }
        match folders.get(&id) {
            Some(row) => {
                parts.push(row.name.clone());
                current = row.parent_id.clone();
            }
            None => {
                parts.reverse();
                return format!("(orphaned)/{}", parts.join("/"));
            }
        }
    }
    parts.reverse();
    parts.join("/")
}

/// Reverse lookup: scan [`folders`] for the row whose path equals
/// [`path`]. Returns `None` for the empty path (root) or when no
/// match exists.
///
/// Linear over the map — folder trees are bounded (<<1k entries) so
/// the cost stays sub-microsecond. Callers that need this hot can
/// switch to a `(parent_id, name) → id` secondary index later.
#[must_use]
pub fn find_folder_id_by_path(path: &str, folders: &BTreeMap<String, FolderRow>) -> Option<String> {
    if path.is_empty() {
        return None;
    }
    folders
        .iter()
        .find(|(id, _)| build_folder_path(id, folders) == path)
        .map(|(id, _)| id.clone())
}

/// Enumerate every reachable folder path in [`folders`]. Used by
/// the export flow (folder list serialisation) and by the empty-
/// folder reconciliation pass on store load.
#[must_use]
pub fn all_folder_paths(folders: &BTreeMap<String, FolderRow>) -> Vec<String> {
    let mut out: Vec<String> = folders
        .keys()
        .map(|id| build_folder_path(id, folders))
        .collect();
    out.sort();
    out.dedup();
    out
}

/// Derive the set of folder paths that have no sessions pointing
/// at them — the "empty folders" the UI renders even though no
/// session lives under them. A folder is empty when its id is
/// absent from [`used_folder_ids`].
///
/// Output is sorted + deduped for stable wire shape and
/// deterministic test output. Skips empty paths (root) since
/// "root" is implicit and never rendered as a folder node.
#[must_use]
pub fn derive_empty_folders(
    folders: &BTreeMap<String, FolderRow>,
    used_folder_ids: &std::collections::HashSet<String>,
) -> Vec<String> {
    let mut out: Vec<String> = folders
        .values()
        .filter(|row| !used_folder_ids.contains(&row.id))
        .map(|row| build_folder_path(&row.id, folders))
        .filter(|path| !path.is_empty())
        .collect();
    out.sort();
    out.dedup();
    out
}

/// Derive the set of folder paths whose row carries the
/// `collapsed` flag. The UI uses this to draw the collapsed-
/// triangle marker without having to peek at the FolderRow shape
/// — the rendered representation is the same flat path set
/// `derive_empty_folders` produces.
///
/// Output is sorted + deduped, skips empty paths (root has no
/// collapsed state).
#[must_use]
pub fn derive_collapsed_folders(folders: &BTreeMap<String, FolderRow>) -> Vec<String> {
    let mut out: Vec<String> = folders
        .values()
        .filter(|row| row.collapsed)
        .map(|row| build_folder_path(&row.id, folders))
        .filter(|path| !path.is_empty())
        .collect();
    out.sort();
    out.dedup();
    out
}

/// Apply a folder rename across a flat path set: every entry that
/// equals [`old_path`] becomes [`new_path`]; every entry that
/// starts with `{old_path}/` has the prefix rewritten. Other
/// entries pass through. Result is sorted for deterministic test
/// output and stable Rust→Dart wire shape.
///
/// Callers (empty-folder set, collapsed-folder set) feed their
/// `Set<String>` here and replace the storage in one shot.
#[must_use]
pub fn rename_paths_cascade(paths: &[String], old_path: &str, new_path: &str) -> Vec<String> {
    if old_path.is_empty() || new_path.is_empty() || old_path == new_path {
        let mut copy: Vec<String> = paths.to_vec();
        copy.sort();
        copy.dedup();
        return copy;
    }
    let prefix = format!("{old_path}/");
    let mut out: Vec<String> = paths
        .iter()
        .map(|p| {
            if p == old_path {
                new_path.to_string()
            } else if let Some(suffix) = p.strip_prefix(&prefix) {
                format!("{new_path}/{suffix}")
            } else {
                p.clone()
            }
        })
        .collect();
    out.sort();
    out.dedup();
    out
}
#[cfg(test)]
#[path = "../tests/unit/folder_path.rs"]
mod tests;
