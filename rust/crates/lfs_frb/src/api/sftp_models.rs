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
/// across the FFI boundary. Carries every sortable axis so the
/// caller never re-implements a per-column comparison Dart-side; the
/// active [`DbSortField`] picks which fields the comparator reads.
#[derive(Debug, Clone)]
pub struct DbFileSortKey {
    pub is_dir: bool,
    pub name_lower: String,
    pub size: u64,
    pub mode: u32,
    pub mod_time_unix_ms: i64,
    pub owner_lower: String,
}

impl From<DbFileSortKey> for sftp_models::SortKey {
    fn from(d: DbFileSortKey) -> Self {
        Self {
            is_dir: d.is_dir,
            name_lower: d.name_lower,
            size: d.size,
            mode: d.mode,
            mod_time_unix_ms: d.mod_time_unix_ms,
            owner_lower: d.owner_lower,
        }
    }
}

/// Which column the file table is sorted by — mirrors
/// `lfs_core::sftp_models::SortField`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbSortField {
    Name,
    Size,
    Mode,
    Modified,
    Owner,
}

impl From<DbSortField> for sftp_models::SortField {
    fn from(d: DbSortField) -> Self {
        match d {
            DbSortField::Name => sftp_models::SortField::Name,
            DbSortField::Size => sftp_models::SortField::Size,
            DbSortField::Mode => sftp_models::SortField::Mode,
            DbSortField::Modified => sftp_models::SortField::Modified,
            DbSortField::Owner => sftp_models::SortField::Owner,
        }
    }
}

/// File classification — mirrors `lfs_core::sftp_models::FileKind`.
/// The Dart side maps each variant to an `IconData` + theme colour
/// (a rendering concern); the classification itself stays Rust-owned.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbFileKind {
    Directory,
    Symlink,
    Image,
    Archive,
    Code,
    Audio,
    Video,
    Document,
    Binary,
    Plain,
}

impl From<sftp_models::FileKind> for DbFileKind {
    fn from(k: sftp_models::FileKind) -> Self {
        match k {
            sftp_models::FileKind::Directory => DbFileKind::Directory,
            sftp_models::FileKind::Symlink => DbFileKind::Symlink,
            sftp_models::FileKind::Image => DbFileKind::Image,
            sftp_models::FileKind::Archive => DbFileKind::Archive,
            sftp_models::FileKind::Code => DbFileKind::Code,
            sftp_models::FileKind::Audio => DbFileKind::Audio,
            sftp_models::FileKind::Video => DbFileKind::Video,
            sftp_models::FileKind::Document => DbFileKind::Document,
            sftp_models::FileKind::Binary => DbFileKind::Binary,
            sftp_models::FileKind::Plain => DbFileKind::Plain,
        }
    }
}

/// Stable directory-first then by the active column + direction.
/// Returns the sort permutation as indices into the input list —
/// the caller re-keys its FileEntry list against these indices,
/// avoiding a struct round-trip across FFI. Directories always lead
/// regardless of column / direction; only the within-kind order
/// responds to `field` + `ascending`.
#[flutter_rust_bridge::frb(sync)]
pub fn sftp_sort_file_entries_by(
    keys: Vec<DbFileSortKey>,
    field: DbSortField,
    ascending: bool,
) -> Vec<u32> {
    let projected: Vec<sftp_models::SortKey> = keys.into_iter().map(Into::into).collect();
    sftp_models::sort_file_entries_by(&projected, field.into(), ascending)
}

/// Classify a directory entry into the icon/colour bucket the file
/// browser renders. Directory + symlink flags take precedence over
/// the name's extension. See [`lfs_core::sftp_models::file_kind`].
#[flutter_rust_bridge::frb(sync)]
pub fn sftp_file_kind(name: String, is_dir: bool, is_symlink: bool) -> DbFileKind {
    sftp_models::file_kind(&name, is_dir, is_symlink).into()
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

    fn key(name: &str, is_dir: bool) -> DbFileSortKey {
        DbFileSortKey {
            is_dir,
            name_lower: name.to_lowercase(),
            size: 0,
            mode: 0,
            mod_time_unix_ms: 0,
            owner_lower: String::new(),
        }
    }

    #[test]
    fn sort_file_entries_puts_dirs_first() {
        // Mixed file + directory list: every directory index
        // must come back ahead of every file index, regardless of
        // name-lower order.
        let keys = vec![
            key("alpha.txt", false),
            key("zebra", true),
            key("beta.txt", false),
            key("alpha-dir", true),
        ];
        let sorted = sftp_sort_file_entries_by(keys, DbSortField::Name, true);
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
            key("charlie", false),
            key("alpha", false),
            key("bravo", false),
        ];
        let sorted = sftp_sort_file_entries_by(keys, DbSortField::Name, true);
        assert_eq!(sorted, vec![1, 2, 0]); // alpha, bravo, charlie
    }

    #[test]
    fn sort_file_entries_by_size_descending_keeps_dirs_first() {
        let keys = vec![
            DbFileSortKey {
                is_dir: false,
                name_lower: "small.txt".into(),
                size: 10,
                mode: 0,
                mod_time_unix_ms: 0,
                owner_lower: String::new(),
            },
            DbFileSortKey {
                is_dir: true,
                name_lower: "adir".into(),
                size: 0,
                mode: 0,
                mod_time_unix_ms: 0,
                owner_lower: String::new(),
            },
            DbFileSortKey {
                is_dir: false,
                name_lower: "big.bin".into(),
                size: 900,
                mode: 0,
                mod_time_unix_ms: 0,
                owner_lower: String::new(),
            },
        ];
        // Descending size: dir leads, then big (900) then small (10).
        let sorted = sftp_sort_file_entries_by(keys, DbSortField::Size, false);
        assert_eq!(sorted, vec![1, 2, 0]);
    }

    #[test]
    fn file_kind_maps_directory_symlink_and_extensions() {
        assert_eq!(
            sftp_file_kind("x.zip".into(), true, false),
            DbFileKind::Directory
        );
        assert_eq!(
            sftp_file_kind("link".into(), false, true),
            DbFileKind::Symlink
        );
        assert_eq!(
            sftp_file_kind("a.png".into(), false, false),
            DbFileKind::Image
        );
        assert_eq!(
            sftp_file_kind("a.rs".into(), false, false),
            DbFileKind::Code
        );
        assert_eq!(
            sftp_file_kind("README".into(), false, false),
            DbFileKind::Plain
        );
    }
}
