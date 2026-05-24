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

/// Caller-projected file entry shape for [`sort_file_entries_by`].
/// Index-based — the caller projects every sortable axis for each
/// row in its FileEntry list and feeds the projection here; the
/// result is the sort permutation as indices into the original
/// list.
///
/// Avoids round-tripping the entire FileEntry struct (which carries
/// `path` etc.) across FFI just to derive a sort order — the Dart
/// caller re-keys its list against the returned indices. Every
/// sortable column is projected up front (a single struct shape) so
/// the caller never re-implements any per-column comparison: the
/// active column + direction select which fields the comparator
/// reads, but the comparison rules (case-folding, dir-first) stay
/// Rust-owned.
#[derive(Debug, Clone)]
pub struct SortKey {
    pub is_dir: bool,
    pub name_lower: String,
    pub size: u64,
    pub mode: u32,
    /// Modification time as Unix epoch milliseconds.
    pub mod_time_unix_ms: i64,
    pub owner_lower: String,
}

/// Which column the user clicked to sort by. Mirrors the file
/// table's header cells. `Name` and `Owner` sort case-insensitively
/// (the caller lowercases into [`SortKey`]); the rest compare their
/// numeric / temporal field directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortField {
    Name,
    Size,
    Mode,
    Modified,
    Owner,
}

/// Stable directory-first, then by the active [`SortField`] +
/// direction. Returns the sort permutation as indices into the
/// input slice — `result[0]` is the index of the entry that comes
/// first.
///
/// Directories always sort ahead of files regardless of column or
/// direction — flipping to descending reverses the within-kind
/// order but never interleaves files among directories. This is the
/// grammar the file table renders on every column-header click
/// across `LocalFS`, `RustSftpFs`, and both mobile + desktop panes,
/// so it lives one place rather than re-derived in each caller.
#[must_use]
pub fn sort_file_entries_by(keys: &[SortKey], field: SortField, ascending: bool) -> Vec<u32> {
    let mut indices: Vec<u32> = (0..keys.len() as u32).collect();
    indices.sort_by(|&a, &b| {
        let ka = &keys[a as usize];
        let kb = &keys[b as usize];
        // Directories first, always — independent of column /
        // direction. Only the within-kind order responds to the
        // active field + ascending flag.
        match (ka.is_dir, kb.is_dir) {
            (true, false) => return std::cmp::Ordering::Less,
            (false, true) => return std::cmp::Ordering::Greater,
            _ => {}
        }
        let cmp = match field {
            SortField::Name => ka.name_lower.cmp(&kb.name_lower),
            SortField::Size => ka.size.cmp(&kb.size),
            SortField::Mode => ka.mode.cmp(&kb.mode),
            SortField::Modified => ka.mod_time_unix_ms.cmp(&kb.mod_time_unix_ms),
            SortField::Owner => ka.owner_lower.cmp(&kb.owner_lower),
        };
        if ascending {
            cmp
        } else {
            cmp.reverse()
        }
    });
    indices
}

/// Closed set of file classifications the file browser maps to an
/// icon + colour. The classification (which extensions count as
/// images / code / …, and the directory / symlink precedence) is
/// the decision tree — owned here so it stays byte-stable across
/// platforms and panes. The Flutter side owns only the
/// `FileKind → IconData + colour` rendering map, which is a
/// legitimate framework concern.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Directory,
    Symlink,
    Image,
    Archive,
    Code,
    Audio,
    Video,
    Document,
    Binary,
    /// Dotfile / no recognised extension — the catch-all "plain
    /// file" bucket.
    Plain,
}

/// Classify a directory entry by name + type flags.
///
/// Precedence: a directory is always [`FileKind::Directory`] and a
/// symlink (that is not also reported as a directory) is always
/// [`FileKind::Symlink`] — both win over any extension match,
/// because the entry's structural role matters more than what its
/// name suffix implies. Only regular files fall through to the
/// extension table. Names with no extension (or a leading-dot
/// dotfile like `.bashrc`, which has no real extension) land in
/// [`FileKind::Plain`].
#[must_use]
pub fn file_kind(name: &str, is_dir: bool, is_symlink: bool) -> FileKind {
    if is_dir {
        return FileKind::Directory;
    }
    if is_symlink {
        return FileKind::Symlink;
    }
    match extension_lower(name).as_deref() {
        Some(ext) => classify_extension(ext),
        None => FileKind::Plain,
    }
}

/// Lowercase extension of `name`, or `None` for an extensionless
/// name or a leading-dot dotfile. A leading `.` is not an extension
/// (`.bashrc` → `None`), matching the GNOME Files / Finder split
/// used elsewhere in the path helpers.
fn extension_lower(name: &str) -> Option<String> {
    let idx = name.rfind('.').filter(|&i| i > 0)?;
    let ext = &name[idx + 1..];
    if ext.is_empty() {
        return None;
    }
    Some(ext.to_lowercase())
}

fn classify_extension(ext: &str) -> FileKind {
    const IMAGE: &[&str] = &[
        "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico", "tiff", "heic", "avif",
    ];
    const ARCHIVE: &[&str] = &[
        "zip", "tar", "gz", "bz2", "xz", "rar", "7z", "tgz", "zst", "lz4", "lzma",
    ];
    const CODE: &[&str] = &[
        "dart", "js", "ts", "py", "go", "rs", "c", "cpp", "h", "hpp", "java", "kt", "rb", "sh",
        "bash", "zsh", "fish", "yaml", "yml", "toml", "json", "xml", "html", "css", "scss", "md",
        "txt", "log", "conf", "cfg", "ini", "env", "sql", "swift", "tsx", "jsx", "lua", "pl",
        "php",
    ];
    const AUDIO: &[&str] = &["mp3", "wav", "flac", "aac", "ogg", "m4a", "opus", "wma"];
    const VIDEO: &[&str] = &["mp4", "mkv", "mov", "avi", "webm", "flv", "wmv", "m4v"];
    const DOCUMENT: &[&str] = &[
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "epub",
    ];
    const BINARY: &[&str] = &[
        "exe", "dll", "so", "dylib", "bin", "o", "a", "class", "jar", "wasm", "deb", "rpm", "dmg",
        "iso", "img", "apk",
    ];
    if IMAGE.contains(&ext) {
        FileKind::Image
    } else if ARCHIVE.contains(&ext) {
        FileKind::Archive
    } else if CODE.contains(&ext) {
        FileKind::Code
    } else if AUDIO.contains(&ext) {
        FileKind::Audio
    } else if VIDEO.contains(&ext) {
        FileKind::Video
    } else if DOCUMENT.contains(&ext) {
        FileKind::Document
    } else if BINARY.contains(&ext) {
        FileKind::Binary
    } else {
        FileKind::Plain
    }
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
            size: 0,
            mode: 0,
            mod_time_unix_ms: 0,
            owner_lower: String::new(),
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
        let indices = sort_file_entries_by(&keys, SortField::Name, true);
        // adir, bdir, yfile, zfile — dirs first then alphabetical.
        assert_eq!(indices, vec![1, 3, 2, 0]);
    }

    #[test]
    fn sort_is_case_insensitive() {
        let keys = vec![key("Zoo", false), key("apple", false), key("Banana", false)];
        let indices = sort_file_entries_by(&keys, SortField::Name, true);
        assert_eq!(indices, vec![1, 2, 0]);
    }

    #[test]
    fn sort_handles_empty_input() {
        let keys: Vec<SortKey> = Vec::new();
        assert!(sort_file_entries_by(&keys, SortField::Name, true).is_empty());
    }

    #[test]
    fn sort_preserves_stable_order_for_equal_keys() {
        let keys = vec![key("dup", false), key("dup", false), key("dup", false)];
        // All equal — stable sort returns original order.
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Name, true),
            vec![0, 1, 2]
        );
    }

    #[test]
    fn sort_descending_reverses_within_kind_but_keeps_dirs_first() {
        // Descending name: dirs still lead, but order within each
        // kind flips. dirs adir/bdir → bdir, adir; files yfile/zfile
        // → zfile, yfile.
        let keys = vec![
            key("zfile", false),
            key("adir", true),
            key("yfile", false),
            key("bdir", true),
        ];
        let indices = sort_file_entries_by(&keys, SortField::Name, false);
        assert_eq!(indices, vec![3, 1, 0, 2]);
    }

    fn sized_key(name: &str, size: u64) -> SortKey {
        SortKey {
            name_lower: name.to_lowercase(),
            is_dir: false,
            size,
            mode: 0,
            mod_time_unix_ms: 0,
            owner_lower: String::new(),
        }
    }

    #[test]
    fn sort_by_size_ascending_orders_smallest_first() {
        let keys = vec![
            sized_key("big", 900),
            sized_key("small", 10),
            sized_key("mid", 100),
        ];
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Size, true),
            vec![1, 2, 0]
        );
    }

    #[test]
    fn sort_by_size_descending_orders_largest_first() {
        let keys = vec![
            sized_key("big", 900),
            sized_key("small", 10),
            sized_key("mid", 100),
        ];
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Size, false),
            vec![0, 2, 1]
        );
    }

    #[test]
    fn sort_by_modified_orders_by_timestamp() {
        let mk = |ms: i64| SortKey {
            name_lower: "f".into(),
            is_dir: false,
            size: 0,
            mode: 0,
            mod_time_unix_ms: ms,
            owner_lower: String::new(),
        };
        let keys = vec![mk(300), mk(100), mk(200)];
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Modified, true),
            vec![1, 2, 0]
        );
    }

    #[test]
    fn sort_by_mode_orders_by_permission_bits() {
        let mk = |mode: u32| SortKey {
            name_lower: "f".into(),
            is_dir: false,
            size: 0,
            mode,
            mod_time_unix_ms: 0,
            owner_lower: String::new(),
        };
        let keys = vec![mk(0o755), mk(0o600), mk(0o644)];
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Mode, true),
            vec![1, 2, 0]
        );
    }

    #[test]
    fn sort_by_owner_is_case_insensitive() {
        let mk = |owner: &str| SortKey {
            name_lower: "f".into(),
            is_dir: false,
            size: 0,
            mode: 0,
            mod_time_unix_ms: 0,
            owner_lower: owner.to_lowercase(),
        };
        let keys = vec![mk("Zoe"), mk("alice"), mk("Bob")];
        assert_eq!(
            sort_file_entries_by(&keys, SortField::Owner, true),
            vec![1, 2, 0]
        );
    }

    #[test]
    fn file_kind_directory_wins_over_extension() {
        // A directory named like an archive is still a directory.
        assert_eq!(file_kind("backup.zip", true, false), FileKind::Directory);
        assert_eq!(file_kind("photos", true, false), FileKind::Directory);
    }

    #[test]
    fn file_kind_symlink_wins_over_extension_but_not_directory() {
        // Symlink-to-file: Symlink. Symlink reported as a directory:
        // Directory (the `is_dir` flag wins, matching how a resolved
        // symlinked directory surfaces).
        assert_eq!(file_kind("link.png", false, true), FileKind::Symlink);
        assert_eq!(file_kind("dirlink", true, true), FileKind::Directory);
    }

    #[test]
    fn file_kind_classifies_each_extension_bucket() {
        assert_eq!(file_kind("photo.JPG", false, false), FileKind::Image);
        assert_eq!(file_kind("archive.tar.gz", false, false), FileKind::Archive);
        assert_eq!(file_kind("main.rs", false, false), FileKind::Code);
        assert_eq!(file_kind("song.mp3", false, false), FileKind::Audio);
        assert_eq!(file_kind("clip.mkv", false, false), FileKind::Video);
        assert_eq!(file_kind("report.pdf", false, false), FileKind::Document);
        assert_eq!(file_kind("tool.exe", false, false), FileKind::Binary);
    }

    #[test]
    fn file_kind_unknown_and_dotfiles_are_plain() {
        assert_eq!(file_kind("notes.qwerty", false, false), FileKind::Plain);
        assert_eq!(file_kind("README", false, false), FileKind::Plain);
        // Leading dot is not an extension.
        assert_eq!(file_kind(".bashrc", false, false), FileKind::Plain);
        // Trailing dot leaves an empty extension → Plain.
        assert_eq!(file_kind("weird.", false, false), FileKind::Plain);
    }
}
