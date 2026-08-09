/// Unit tests extracted from sftp_models.rs
/// Declared via `#[path] mod tests;` in the source file.
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
