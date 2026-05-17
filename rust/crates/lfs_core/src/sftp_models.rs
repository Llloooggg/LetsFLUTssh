//! File-entry display helpers shared between local + remote file
//! browsers. Pure formatters / comparators that the UI renders
//! against — kept Rust-canonical so the chmod-letter grammar
//! and the directory-first sort stay byte-stable across both
//! `LocalFS` and `RustSftpFs`.
//!
//! Why Rust-side: every file pane (local + SFTP, mobile + desktop)
//! renders these. Promoting them once means the future
//! `lfs_core::sftp` directory listing endpoint can return the
//! pre-sorted, pre-formatted view in one shot rather than the Dart
//! caller doing the same work after every `list()`.

/// Render Unix mode bits as a `drwxr-xr-x` string.
///
/// `mode` is the OS-reported permission bits (lower 12 of a u32 in
/// practice — owner / group / other × r / w / x). `is_dir` selects
/// the leading character (`d` for directory, `-` for file). Mode
/// `0` renders as `---` so a `LocalFS` entry that didn't fetch
/// permissions does not show a fake-precise rwx bar.
#[must_use]
pub fn mode_string(mode: u32, is_dir: bool) -> String {
    if mode == 0 {
        return "---".to_string();
    }
    let mut out = String::with_capacity(10);
    out.push(if is_dir { 'd' } else { '-' });
    // Walk bits 8 → 0; pick `r`, `w`, `x` based on bit position
    // mod 3 (0=x, 1=w, 2=r).
    for i in (0..=8).rev() {
        let bit = (mode >> i) & 1;
        let ch = if bit == 1 {
            match i % 3 {
                0 => 'x',
                1 => 'w',
                _ => 'r',
            }
        } else {
            '-'
        };
        out.push(ch);
    }
    out
}

/// Caller-projected file entry shape for [`sort_file_entries`].
/// Index-based — the caller projects `(is_dir, lowercase_name)`
/// for each row in its FileEntry list and feeds the projection
/// here; the result is the sort permutation as indices into the
/// original list.
///
/// Avoids round-tripping the entire FileEntry struct (which carries
/// path / size / mode / modTime / owner) across FFI just to derive
/// a sort order — the Dart caller re-keys its list against the
/// returned indices.
#[derive(Debug, Clone)]
pub struct SortKey {
    pub is_dir: bool,
    pub name_lower: String,
}

/// Stable directory-first, then case-insensitive alphabetical
/// name sort. Returns the sort permutation as indices into the
/// input slice — `result[0]` is the index of the entry that
/// comes first.
///
/// Used by every directory-listing surface (`LocalFS.list`,
/// `RustSftpFs.list`, mobile + desktop file panes) so the
/// "folders first then alphabetical" grammar lives one place.
#[must_use]
pub fn sort_file_entries(keys: &[SortKey]) -> Vec<u32> {
    let mut indices: Vec<u32> = (0..keys.len() as u32).collect();
    indices.sort_by(|&a, &b| {
        let ka = &keys[a as usize];
        let kb = &keys[b as usize];
        match (ka.is_dir, kb.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => ka.name_lower.cmp(&kb.name_lower),
        }
    });
    indices
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_string_zero_renders_dashes_only() {
        assert_eq!(mode_string(0, false), "---");
        assert_eq!(mode_string(0, true), "---");
    }

    #[test]
    fn mode_string_renders_rwx_r_x_r_x_for_0755() {
        // Owner rwx (7), group r-x (5), other r-x (5).
        assert_eq!(mode_string(0o755, false), "-rwxr-xr-x");
        assert_eq!(mode_string(0o755, true), "drwxr-xr-x");
    }

    #[test]
    fn mode_string_renders_rw_r_r_for_0644() {
        assert_eq!(mode_string(0o644, false), "-rw-r--r--");
    }

    #[test]
    fn mode_string_renders_rw_owner_only_for_0600() {
        assert_eq!(mode_string(0o600, false), "-rw-------");
    }

    #[test]
    fn mode_string_renders_full_perms_for_0777() {
        assert_eq!(mode_string(0o777, true), "drwxrwxrwx");
    }

    fn key(name: &str, is_dir: bool) -> SortKey {
        SortKey {
            name_lower: name.to_lowercase(),
            is_dir,
        }
    }

    #[test]
    fn sort_returns_directories_before_files() {
        let keys = vec![
            key("zfile", false),
            key("adir", true),
            key("yfile", false),
            key("bdir", true),
        ];
        let indices = sort_file_entries(&keys);
        // adir, bdir, yfile, zfile — dirs first then alphabetical.
        assert_eq!(indices, vec![1, 3, 2, 0]);
    }

    #[test]
    fn sort_is_case_insensitive() {
        let keys = vec![key("Zoo", false), key("apple", false), key("Banana", false)];
        let indices = sort_file_entries(&keys);
        assert_eq!(indices, vec![1, 2, 0]);
    }

    #[test]
    fn sort_handles_empty_input() {
        let keys: Vec<SortKey> = Vec::new();
        assert!(sort_file_entries(&keys).is_empty());
    }

    #[test]
    fn sort_preserves_stable_order_for_equal_keys() {
        let keys = vec![key("dup", false), key("dup", false), key("dup", false)];
        // All equal — stable sort returns original order.
        assert_eq!(sort_file_entries(&keys), vec![0, 1, 2]);
    }
}
