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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_string_zero_renders_dashes_for_local_fs_unknown_perms() {
        // LocalFS entries that didn't fetch perms collapse to
        // `---------` so the file row shows a placeholder rather
        // than a misleading "rwx" string.
        let s = sftp_mode_string(0, false);
        assert!(s.contains('-'));
    }

    #[test]
    fn mode_string_dir_flag_prefixes_d() {
        let s = sftp_mode_string(0o755, true);
        assert!(s.starts_with('d'), "got: {s}");
    }

    #[test]
    fn mode_string_renders_classic_owner_group_other_groups() {
        // 0o644 → `rw-r--r--`. Asserting the trailing 9 perms
        // chars (skip the type prefix) so the test stays robust
        // to a future leading-character change.
        let s = sftp_mode_string(0o644, false);
        assert!(s.ends_with("rw-r--r--"), "got: {s}");
    }

    #[test]
    fn sort_file_entries_puts_dirs_first() {
        // Mixed file + directory list: every directory index
        // must come back ahead of every file index, regardless of
        // name-lower order.
        let keys = vec![
            DbFileSortKey {
                is_dir: false,
                name_lower: "alpha.txt".into(),
            },
            DbFileSortKey {
                is_dir: true,
                name_lower: "zebra".into(),
            },
            DbFileSortKey {
                is_dir: false,
                name_lower: "beta.txt".into(),
            },
            DbFileSortKey {
                is_dir: true,
                name_lower: "alpha-dir".into(),
            },
        ];
        let sorted = sftp_sort_file_entries(keys);
        assert_eq!(sorted.len(), 4);
        // First two indices are dirs (3 = "alpha-dir", 1 = "zebra").
        // The original file indices (0, 2) follow.
        let dirs_first = sorted[0] == 3 && sorted[1] == 1;
        assert!(dirs_first, "expected dirs first, got: {:?}", sorted);
        assert_eq!(sorted[2], 0); // alpha.txt
        assert_eq!(sorted[3], 2); // beta.txt
    }

    #[test]
    fn sort_file_entries_alphabetises_within_kind() {
        let keys = vec![
            DbFileSortKey {
                is_dir: false,
                name_lower: "charlie".into(),
            },
            DbFileSortKey {
                is_dir: false,
                name_lower: "alpha".into(),
            },
            DbFileSortKey {
                is_dir: false,
                name_lower: "bravo".into(),
            },
        ];
        let sorted = sftp_sort_file_entries(keys);
        assert_eq!(sorted, vec![1, 2, 0]); // alpha, bravo, charlie
    }
}
