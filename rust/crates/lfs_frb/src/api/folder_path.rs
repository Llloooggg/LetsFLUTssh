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
