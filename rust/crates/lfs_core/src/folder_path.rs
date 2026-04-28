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
    let mut current: Option<String> = Some(folder_id.to_string());
    while let Some(id) = current {
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
mod tests {
    use super::*;

    fn row(id: &str, name: &str, parent: Option<&str>) -> FolderRow {
        FolderRow {
            id: id.to_string(),
            name: name.to_string(),
            parent_id: parent.map(|s| s.to_string()),
            sort_order: 0,
            collapsed: false,
            created_at_ms: 0,
        }
    }

    fn map_of(rows: Vec<FolderRow>) -> BTreeMap<String, FolderRow> {
        rows.into_iter().map(|r| (r.id.clone(), r)).collect()
    }

    #[test]
    fn build_path_returns_empty_for_empty_id() {
        let folders = map_of(vec![]);
        assert_eq!(build_folder_path("", &folders), "");
    }

    #[test]
    fn build_path_walks_parent_chain() {
        let folders = map_of(vec![
            row("a", "Production", None),
            row("b", "EU", Some("a")),
            row("c", "web", Some("b")),
        ]);
        assert_eq!(build_folder_path("c", &folders), "Production/EU/web");
        assert_eq!(build_folder_path("b", &folders), "Production/EU");
        assert_eq!(build_folder_path("a", &folders), "Production");
    }

    #[test]
    fn build_path_marks_orphan_with_prefix() {
        // `c` references a parent `b` that was deleted while `a`
        // was kept — surface the inconsistency instead of losing
        // the leaf name silently.
        let folders = map_of(vec![
            row("a", "Production", None),
            row("c", "web", Some("b")),
        ]);
        assert_eq!(build_folder_path("c", &folders), "(orphaned)/web");
    }

    #[test]
    fn build_path_returns_orphan_marker_for_missing_root() {
        let folders = map_of(vec![]);
        assert_eq!(build_folder_path("missing", &folders), "(orphaned)/");
    }

    #[test]
    fn find_id_by_path_returns_none_for_empty() {
        let folders = map_of(vec![row("a", "Production", None)]);
        assert!(find_folder_id_by_path("", &folders).is_none());
    }

    #[test]
    fn find_id_by_path_matches_full_path() {
        let folders = map_of(vec![
            row("a", "Production", None),
            row("b", "EU", Some("a")),
            row("c", "web", Some("b")),
        ]);
        assert_eq!(
            find_folder_id_by_path("Production/EU/web", &folders),
            Some("c".to_string())
        );
        assert_eq!(
            find_folder_id_by_path("Production", &folders),
            Some("a".to_string())
        );
    }

    #[test]
    fn find_id_by_path_returns_none_for_unknown() {
        let folders = map_of(vec![row("a", "Production", None)]);
        assert!(find_folder_id_by_path("Production/EU", &folders).is_none());
    }

    #[test]
    fn all_paths_enumerates_every_node() {
        let folders = map_of(vec![
            row("a", "Production", None),
            row("b", "EU", Some("a")),
            row("c", "web", Some("b")),
            row("d", "Staging", None),
        ]);
        let paths = all_folder_paths(&folders);
        assert_eq!(
            paths,
            vec![
                "Production".to_string(),
                "Production/EU".to_string(),
                "Production/EU/web".to_string(),
                "Staging".to_string(),
            ]
        );
    }

    #[test]
    fn rename_cascade_renames_exact_match() {
        let paths = vec!["Production".to_string(), "Staging".to_string()];
        let out = rename_paths_cascade(&paths, "Production", "Prod");
        assert_eq!(out, vec!["Prod".to_string(), "Staging".to_string()]);
    }

    #[test]
    fn rename_cascade_renames_children_under_prefix() {
        let paths = vec![
            "Production".to_string(),
            "Production/EU".to_string(),
            "Production/EU/web".to_string(),
            "Staging".to_string(),
        ];
        let out = rename_paths_cascade(&paths, "Production", "Prod");
        assert_eq!(
            out,
            vec![
                "Prod".to_string(),
                "Prod/EU".to_string(),
                "Prod/EU/web".to_string(),
                "Staging".to_string(),
            ]
        );
    }

    #[test]
    fn rename_cascade_skips_paths_with_matching_prefix_but_different_name() {
        // "ProductionExtra" must NOT be renamed when the user
        // renames "Production" — only exact matches and entries
        // under `Production/` (note the slash) move.
        let paths = vec!["Production".to_string(), "ProductionExtra".to_string()];
        let out = rename_paths_cascade(&paths, "Production", "Prod");
        assert_eq!(out, vec!["Prod".to_string(), "ProductionExtra".to_string()]);
    }

    #[test]
    fn rename_cascade_no_op_for_identical_paths() {
        let paths = vec!["A".to_string(), "B".to_string()];
        let out = rename_paths_cascade(&paths, "X", "X");
        assert_eq!(out, vec!["A".to_string(), "B".to_string()]);
    }

    #[test]
    fn rename_cascade_no_op_for_empty_old_or_new() {
        let paths = vec!["A".to_string(), "B".to_string()];
        assert_eq!(rename_paths_cascade(&paths, "", "Prod"), vec!["A", "B"]);
        assert_eq!(rename_paths_cascade(&paths, "A", ""), vec!["A", "B"]);
    }
}
