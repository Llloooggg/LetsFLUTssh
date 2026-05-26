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
    fn build_path_breaks_a_parent_cycle_instead_of_looping() {
        // Cyclic parent_id chain (hand-edited / pre-fix DB): a -> b,
        // b -> a. The walk must terminate at a "(cycle)/…" marker
        // rather than loop forever / OOM growing the path.
        let folders = map_of(vec![
            row("a", "Alpha", Some("b")),
            row("b", "Bravo", Some("a")),
        ]);
        let path = build_folder_path("a", &folders);
        assert!(
            path.starts_with("(cycle)/"),
            "expected a cycle marker, got {path:?}"
        );
    }

    #[test]
    fn build_path_breaks_a_self_referential_cycle() {
        let folders = map_of(vec![row("a", "Alpha", Some("a"))]);
        let path = build_folder_path("a", &folders);
        assert!(
            path.starts_with("(cycle)/"),
            "expected a cycle marker, got {path:?}"
        );
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

    fn collapsed_row(id: &str, name: &str, parent: Option<&str>) -> FolderRow {
        FolderRow {
            id: id.to_string(),
            name: name.to_string(),
            parent_id: parent.map(|s| s.to_string()),
            sort_order: 0,
            collapsed: true,
            created_at_ms: 0,
        }
    }

    #[test]
    fn empty_folders_skips_folders_with_sessions() {
        let folders = map_of(vec![
            row("a", "Production", None),
            row("b", "EU", Some("a")),
            row("c", "Staging", None),
        ]);
        let used: std::collections::HashSet<String> = ["a".into()].into();
        let empty = derive_empty_folders(&folders, &used);
        // 'a' has a session — exclude. 'b' (Production/EU) and 'c'
        // (Staging) are empty.
        assert_eq!(
            empty,
            vec!["Production/EU".to_string(), "Staging".to_string()]
        );
    }

    #[test]
    fn empty_folders_returns_every_folder_when_no_session_present() {
        let folders = map_of(vec![
            row("a", "Production", None),
            row("b", "Staging", None),
        ]);
        let used: std::collections::HashSet<String> = std::collections::HashSet::new();
        let empty = derive_empty_folders(&folders, &used);
        assert_eq!(empty, vec!["Production".to_string(), "Staging".to_string()]);
    }

    #[test]
    fn empty_folders_skips_orphan_partial_paths_when_root_present() {
        // An orphan folder still gets a path entry — the UI shows
        // the marker — but only when it actually resolves to a
        // non-empty path. A row with no name + no parent would
        // resolve to empty and we drop it.
        let folders = map_of(vec![row("a", "Production", None)]);
        let used: std::collections::HashSet<String> = std::collections::HashSet::new();
        let empty = derive_empty_folders(&folders, &used);
        assert_eq!(empty, vec!["Production".to_string()]);
    }

    #[test]
    fn collapsed_folders_returns_only_collapsed_rows() {
        let folders = map_of(vec![
            row("a", "Production", None),
            collapsed_row("b", "EU", Some("a")),
            collapsed_row("c", "Staging", None),
        ]);
        let collapsed = derive_collapsed_folders(&folders);
        assert_eq!(
            collapsed,
            vec!["Production/EU".to_string(), "Staging".to_string()]
        );
    }

    #[test]
    fn collapsed_folders_returns_empty_when_nothing_collapsed() {
        let folders = map_of(vec![row("a", "Production", None)]);
        assert!(derive_collapsed_folders(&folders).is_empty());
    }
}
