//! FRB adapter for `lfs_core::sftp_models` display helpers.
//!
//! Sync — both the mode-letter renderer and the sort permutation
//! are O(N) over the directory listing (typically <1k entries) and
//! run sub-microsecond per call. Dart callers (file pane build
//! phase, transfer dialog) want the result inline.

use lfs_core::sftp_models;

/// Render Unix mode bits as `drwxr-xr-x`. `mode == 0` produces
/// `---` (LocalFS entries that didn't fetch perms).
#[flutter_rust_bridge::frb(sync)]
pub fn sftp_mode_string(mode: u32, is_dir: bool) -> String {
    sftp_models::mode_string(mode, is_dir)
}

/// Caller-projected sort key — mirrors `lfs_core::sftp_models::SortKey`
/// across the FFI boundary.
#[derive(Debug, Clone)]
pub struct DbFileSortKey {
    pub is_dir: bool,
    pub name_lower: String,
}

impl From<DbFileSortKey> for sftp_models::SortKey {
    fn from(d: DbFileSortKey) -> Self {
        Self {
            is_dir: d.is_dir,
            name_lower: d.name_lower,
        }
    }
}

/// Stable directory-first then case-insensitive alphabetical sort.
/// Returns the sort permutation as indices into the input list —
/// the caller re-keys its FileEntry list against these indices,
/// avoiding a struct round-trip across FFI.
#[flutter_rust_bridge::frb(sync)]
pub fn sftp_sort_file_entries(keys: Vec<DbFileSortKey>) -> Vec<u32> {
    let projected: Vec<sftp_models::SortKey> = keys.into_iter().map(Into::into).collect();
    sftp_models::sort_file_entries(&projected)
}
