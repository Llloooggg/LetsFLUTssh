//! FRB adapter for `lfs_core::folder_path`.
//!
//! Sync — every helper is a single linear scan over a folder map
//! that, in production, holds <1k entries (UI tree). The Dart
//! caller (`SessionStore`, `mappers.dart`) invokes them on every
//! load + every folder mutation, so an async jump would buy
//! nothing and cost a microtask hop per call.
//!
//! The shim accepts the same `DbFolder` shape the rest of the
//! `db` module exports, so callers can pass `_folderMap.values
//! .toList()` directly without re-allocating a side table.

use std::collections::BTreeMap;

use lfs_core::db::folders::FolderRow;
use lfs_core::folder_path;

use crate::api::db::DbFolder;

fn into_map(folders: Vec<DbFolder>) -> BTreeMap<String, FolderRow> {
    folders
        .into_iter()
        .map(|f| {
            let row: FolderRow = f.into();
            (row.id.clone(), row)
        })
        .collect()
}

/// Resolve a folder id to its slash-joined path.
#[flutter_rust_bridge::frb(sync)]
pub fn folder_build_path(folder_id: String, folders: Vec<DbFolder>) -> String {
    folder_path::build_folder_path(&folder_id, &into_map(folders))
}

/// Reverse lookup — find the folder id whose path equals
/// [`path`], or `None` for empty / unknown.
#[flutter_rust_bridge::frb(sync)]
pub fn folder_find_id_by_path(path: String, folders: Vec<DbFolder>) -> Option<String> {
    folder_path::find_folder_id_by_path(&path, &into_map(folders))
}

/// Enumerate every reachable path in the folder tree. Result is
/// sorted + deduped for stable wire shape.
#[flutter_rust_bridge::frb(sync)]
pub fn folder_all_paths(folders: Vec<DbFolder>) -> Vec<String> {
    folder_path::all_folder_paths(&into_map(folders))
}

/// Apply a folder rename across a flat path set: exact matches
/// move; entries under `{old_path}/` have the prefix rewritten.
#[flutter_rust_bridge::frb(sync)]
pub fn folder_rename_paths_cascade(
    paths: Vec<String>,
    old_path: String,
    new_path: String,
) -> Vec<String> {
    folder_path::rename_paths_cascade(&paths, &old_path, &new_path)
}

/// Derive the set of folder paths that have no sessions pointing
/// at them. A folder is empty when its id is absent from
/// `used_folder_ids`. Skips empty paths (root has no folder node).
#[flutter_rust_bridge::frb(sync)]
pub fn folder_derive_empty(folders: Vec<DbFolder>, used_folder_ids: Vec<String>) -> Vec<String> {
    let used: std::collections::HashSet<String> = used_folder_ids.into_iter().collect();
    folder_path::derive_empty_folders(&into_map(folders), &used)
}

/// Derive the set of folder paths whose row carries the
/// `collapsed` flag. Skips empty paths (root has no collapsed
/// state).
#[flutter_rust_bridge::frb(sync)]
pub fn folder_derive_collapsed(folders: Vec<DbFolder>) -> Vec<String> {
    folder_path::derive_collapsed_folders(&into_map(folders))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(id: &str, name: &str, parent: Option<&str>, collapsed: bool) -> DbFolder {
        DbFolder {
            id: id.into(),
            name: name.into(),
            parent_id: parent.map(str::to_string),
            sort_order: 0,
            collapsed,
            created_at_ms: 0,
        }
    }

    #[test]
    fn build_path_joins_parent_chain_with_slash() {
        let folders = vec![
            folder("root", "production", None, false),
            folder("child", "edge", Some("root"), false),
        ];
        assert_eq!(
            folder_build_path("child".into(), folders),
            "production/edge"
        );
    }

    #[test]
    fn build_path_for_unknown_id_marks_orphaned() {
        // The core helper prefixes the partial path with `(orphaned)/`
        // so the inconsistency stays visible at the UI layer rather
        // than collapsing to root. Pin the contract so a future
        // refactor can't quietly switch to the empty-string fallback.
        let folders = vec![folder("a", "x", None, false)];
        assert_eq!(folder_build_path("ghost".into(), folders), "(orphaned)/");
    }

    #[test]
    fn build_path_returns_empty_string_for_empty_id() {
        let folders = vec![folder("a", "x", None, false)];
        assert_eq!(folder_build_path(String::new(), folders), "");
    }

    #[test]
    fn find_id_by_path_round_trips_with_build() {
        let folders = vec![
            folder("root", "production", None, false),
            folder("child", "edge", Some("root"), false),
        ];
        assert_eq!(
            folder_find_id_by_path("production/edge".into(), folders),
            Some("child".to_string())
        );
    }

    #[test]
    fn find_id_by_path_returns_none_for_unknown_path() {
        let folders = vec![folder("root", "production", None, false)];
        assert!(folder_find_id_by_path("ghost".into(), folders).is_none());
    }

    #[test]
    fn all_paths_lists_every_node_sorted() {
        let folders = vec![
            folder("root", "production", None, false),
            folder("child", "edge", Some("root"), false),
        ];
        let mut paths = folder_all_paths(folders);
        paths.sort();
        assert_eq!(paths, vec!["production", "production/edge"]);
    }

    #[test]
    fn rename_cascade_rewrites_exact_match_and_descendants() {
        let paths = vec![
            "production".to_string(),
            "production/edge".to_string(),
            "staging".to_string(),
        ];
        let renamed = folder_rename_paths_cascade(paths, "production".into(), "prod".into());
        assert!(renamed.contains(&"prod".to_string()));
        assert!(renamed.contains(&"prod/edge".to_string()));
        assert!(renamed.contains(&"staging".to_string()));
    }

    #[test]
    fn derive_empty_skips_used_folders() {
        let folders = vec![
            folder("a", "alpha", None, false),
            folder("b", "bravo", None, false),
        ];
        let used = vec!["a".to_string()];
        let empty = folder_derive_empty(folders, used);
        assert!(empty.contains(&"bravo".to_string()));
        assert!(!empty.contains(&"alpha".to_string()));
    }

    #[test]
    fn derive_collapsed_picks_only_flagged_folders() {
        let folders = vec![
            folder("a", "open-folder", None, false),
            folder("b", "shut-folder", None, true),
        ];
        let collapsed = folder_derive_collapsed(folders);
        assert!(collapsed.contains(&"shut-folder".to_string()));
        assert!(!collapsed.contains(&"open-folder".to_string()));
    }
}
