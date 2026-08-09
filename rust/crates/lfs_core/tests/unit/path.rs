/// Unit tests extracted from path.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn basename_returns_input_for_bare_filename() {
    assert_eq!(basename("file.txt"), "file.txt");
}

#[test]
fn basename_returns_last_segment_for_unix_path() {
    assert_eq!(basename("/home/user/file.txt"), "file.txt");
}

#[test]
fn basename_normalizes_windows_separators() {
    assert_eq!(basename(r"C:\Users\u\file.txt"), "file.txt");
}

#[test]
fn basename_handles_trailing_separator() {
    assert_eq!(basename("/home/user/"), "");
}

#[test]
fn is_suspicious_path_flags_dotdot_segment() {
    assert!(is_suspicious_path("/home/user/../../etc/shadow"));
    assert!(is_suspicious_path("../config"));
}

#[test]
fn is_suspicious_path_passes_clean_paths() {
    assert!(!is_suspicious_path("/home/user/.ssh/id_ed25519"));
    assert!(!is_suspicious_path("file.txt"));
}

#[test]
fn is_suspicious_path_flags_dotdot_with_windows_separators() {
    assert!(is_suspicious_path(r"C:\Users\u\..\..\Windows"));
}

#[test]
fn is_suspicious_path_passes_dotdotextension() {
    // ".." is the trigger; "..foo" is not a traversal segment.
    assert!(!is_suspicious_path("/home/user/..foo"));
}

#[test]
fn safe_entry_name_accepts_plain_names() {
    assert!(is_safe_transfer_entry_name("readme.txt"));
    assert!(is_safe_transfer_entry_name("img-2024_05.png"));
}

#[test]
fn safe_entry_name_accepts_interior_spaces() {
    // Spaces inside a real filename are legitimate content.
    assert!(is_safe_transfer_entry_name("my file.txt"));
    assert!(is_safe_transfer_entry_name("a b c"));
}

#[test]
fn safe_entry_name_accepts_dotfile() {
    assert!(is_safe_transfer_entry_name(".bashrc"));
}

#[test]
fn safe_entry_name_accepts_dotdot_prefix() {
    // "..foo" is not the `..` traversal segment.
    assert!(is_safe_transfer_entry_name("..foo"));
}

#[test]
fn safe_entry_name_rejects_empty() {
    assert!(!is_safe_transfer_entry_name(""));
}

#[test]
fn safe_entry_name_rejects_self_and_parent_refs() {
    assert!(!is_safe_transfer_entry_name("."));
    assert!(!is_safe_transfer_entry_name(".."));
}

#[test]
fn safe_entry_name_rejects_separators() {
    assert!(!is_safe_transfer_entry_name("a/b"));
    assert!(!is_safe_transfer_entry_name("a\\b"));
    assert!(!is_safe_transfer_entry_name("../../etc/cron.d/x"));
    assert!(!is_safe_transfer_entry_name("/etc/passwd"));
}

#[test]
fn safe_entry_name_rejects_embedded_nul() {
    assert!(!is_safe_transfer_entry_name("foo\0bar"));
    assert!(!is_safe_transfer_entry_name("trailing\0"));
}

#[test]
fn safe_entry_name_rejects_whitespace_only() {
    assert!(!is_safe_transfer_entry_name("   "));
    assert!(!is_safe_transfer_entry_name("\t\n"));
}

#[test]
fn safe_entry_name_invariant_holds_over_adversarial_inputs() {
    // Property-style sweep: any name containing a separator, a
    // NUL, or equal to ""/"."/".."/whitespace-only is rejected;
    // the predicate never panics. Built from hostile fragments
    // mixed with benign ones the way a malicious SFTP server
    // would shape directory entries.
    let fragments = [
        "",
        ".",
        "..",
        "/",
        "\\",
        "\0",
        " ",
        "\t",
        "a",
        "file.txt",
        "..foo",
        "中文",
        "💥",
        "\u{202E}rcs.exe",
        "a\0b",
        "../x",
        "x/../y",
        "C:\\Windows",
    ];
    for a in &fragments {
        for b in &fragments {
            let name = format!("{a}{b}");
            let unsafe_shape = name.is_empty()
                || name == "."
                || name == ".."
                || name.contains('/')
                || name.contains('\\')
                || name.contains('\0')
                || name.trim().is_empty();
            assert_eq!(
                is_safe_transfer_entry_name(&name),
                !unsafe_shape,
                "name {name:?} classified wrong"
            );
        }
    }
    // A huge name with no banned char is still safe; with one is
    // not — length alone is not a rejection axis.
    let huge = "x".repeat(100_000);
    assert!(is_safe_transfer_entry_name(&huge));
    let huge_sep = format!("{huge}/y");
    assert!(!is_safe_transfer_entry_name(&huge_sep));
}

#[test]
fn parent_of_posix_file_drops_to_dir() {
    assert_eq!(
        parent("/home/user/file.txt", PathStyle::Posix).as_deref(),
        Some("/home/user")
    );
}

#[test]
fn parent_of_first_level_posix_collapses_to_root() {
    assert_eq!(parent("/home", PathStyle::Posix).as_deref(), Some("/"));
}

#[test]
fn parent_of_posix_root_is_none() {
    assert!(parent("/", PathStyle::Posix).is_none());
    assert!(parent("/", PathStyle::Auto).is_none());
}

#[test]
fn parent_strips_trailing_slash_first() {
    assert_eq!(
        parent("/home/user/", PathStyle::Posix).as_deref(),
        Some("/home")
    );
}

#[test]
fn parent_of_empty_is_none() {
    assert!(parent("", PathStyle::Auto).is_none());
}

#[test]
fn parent_of_bare_relative_segment_is_none() {
    assert!(parent("file.txt", PathStyle::Posix).is_none());
}

#[test]
fn parent_of_windows_path_drops_to_dir() {
    assert_eq!(
        parent(r"C:\Users\foo\file.txt", PathStyle::Auto).as_deref(),
        Some(r"C:\Users\foo")
    );
}

#[test]
fn parent_of_windows_first_level_snaps_drive_root() {
    // Parent of `C:\Users` is the drive root `C:\`, not bare `C:`.
    assert_eq!(
        parent(r"C:\Users", PathStyle::Auto).as_deref(),
        Some(r"C:\")
    );
}

#[test]
fn parent_of_windows_drive_root_is_none() {
    assert!(parent(r"C:\", PathStyle::Auto).is_none());
    assert!(parent("C:", PathStyle::Windows).is_none());
    assert!(parent("D:/", PathStyle::Auto).is_none());
}

#[test]
fn parent_auto_detects_windows_from_forward_slash_drive() {
    // Drive-prefixed even with forward slashes → Windows rules,
    // so the drive root snaps back with a backslash.
    assert_eq!(parent("C:/Users", PathStyle::Auto).as_deref(), Some(r"C:\"));
}

#[test]
fn parent_auto_treats_plain_path_as_posix() {
    assert_eq!(
        parent("/var/log/app", PathStyle::Auto).as_deref(),
        Some("/var/log")
    );
}

#[test]
fn shorten_returns_empty_for_empty() {
    assert_eq!(shorten_to_two_segments(""), "");
}

#[test]
fn shorten_passes_through_paths_with_two_or_fewer_segments() {
    assert_eq!(shorten_to_two_segments("foo"), "foo");
    assert_eq!(shorten_to_two_segments("foo/bar"), "foo/bar");
    assert_eq!(shorten_to_two_segments("/foo"), "/foo");
}

#[test]
fn shorten_keeps_last_two_segments_for_deep_paths() {
    assert_eq!(
        shorten_to_two_segments("/home/user/projects/myrepo/file.txt"),
        ".../myrepo/file.txt"
    );
}

#[test]
fn shorten_normalizes_windows_separators() {
    assert_eq!(
        shorten_to_two_segments(r"C:\Users\u\Downloads\file.txt"),
        ".../Downloads/file.txt"
    );
}

#[test]
fn sibling_candidate_inserts_n_before_extension() {
    assert_eq!(
        sibling_candidate("/home/u/report.txt", 1, true),
        "/home/u/report (1).txt"
    );
    assert_eq!(
        sibling_candidate("/home/u/report.txt", 42, true),
        "/home/u/report (42).txt"
    );
}

#[test]
fn sibling_candidate_only_preserves_final_extension() {
    // "archive.tar.gz" → "archive.tar (1).gz" — matches GNOME
    // Files / Finder behaviour.
    assert_eq!(
        sibling_candidate("/home/u/archive.tar.gz", 1, true),
        "/home/u/archive.tar (1).gz"
    );
}

#[test]
fn sibling_candidate_handles_extensionless_files() {
    assert_eq!(
        sibling_candidate("/home/u/README", 1, true),
        "/home/u/README (1)"
    );
}

#[test]
fn sibling_candidate_handles_dotfiles_as_extensionless() {
    // ".bashrc" — leading dot is not an extension.
    assert_eq!(
        sibling_candidate("/home/u/.bashrc", 1, true),
        "/home/u/.bashrc (1)"
    );
}

#[test]
fn sibling_candidate_handles_bare_filename() {
    assert_eq!(sibling_candidate("file.txt", 1, true), "file (1).txt");
}

#[test]
fn sibling_candidate_uses_native_separator_when_not_posix() {
    // Windows path; posix=false should use `\` as the
    // dirname separator.
    assert_eq!(
        sibling_candidate(r"C:\Users\u\file.txt", 1, false),
        r"C:\Users\u\file (1).txt"
    );
}

#[test]
fn parse_attrib_finds_hidden_files() {
    let out = "A    H  C:\\Users\\u\\hidden.txt\n\
               A       C:\\Users\\u\\visible.txt\n\
               A   S   C:\\Users\\u\\system.txt\n";
    let result = parse_windows_attrib_output(out);
    assert!(result.contains("hidden.txt"));
    assert!(result.contains("system.txt"));
    assert!(!result.contains("visible.txt"));
}

#[test]
fn parse_attrib_normalizes_to_lowercase() {
    let out = "A    H  C:\\Users\\u\\HIDDEN.TXT\n";
    let result = parse_windows_attrib_output(out);
    assert!(result.contains("hidden.txt"));
    assert!(!result.contains("HIDDEN.TXT"));
}

#[test]
fn parse_attrib_skips_blank_and_malformed_lines() {
    let out = "\n\nblank line\nA   H  C:\\Users\\u\\real.txt\n";
    let result = parse_windows_attrib_output(out);
    assert_eq!(result.len(), 1);
    assert!(result.contains("real.txt"));
}

#[test]
fn parse_attrib_handles_empty_input() {
    assert!(parse_windows_attrib_output("").is_empty());
}

/// Tests mutate process-wide environment variables. Run them
/// serialised under a `Mutex` so parallel cargo-test runs
/// don't trample each other's `HOME`. Lock acquired with
/// `unwrap_or_else` to keep poisoning from skipping tests.
use std::sync::Mutex;
static ENV_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn bare_tilde_resolves_to_home() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::set_var("HOME", "/tmp/fakehome");
    assert_eq!(expand_tilde("~"), "/tmp/fakehome");
}

#[test]
fn tilde_slash_prefix_expands() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::set_var("HOME", "/tmp/fakehome");
    assert_eq!(expand_tilde("~/.ssh/config"), "/tmp/fakehome/.ssh/config");
}

#[test]
fn tilde_slash_only_keeps_separator() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::set_var("HOME", "/tmp/fakehome");
    assert_eq!(expand_tilde("~/"), "/tmp/fakehome/");
}

#[test]
fn user_tilde_form_left_unchanged() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::set_var("HOME", "/tmp/fakehome");
    assert_eq!(expand_tilde("~bob/foo"), "~bob/foo");
}

#[test]
fn no_home_returns_input_verbatim() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::remove_var("HOME");
    std::env::remove_var("USERPROFILE");
    assert_eq!(expand_tilde("~/.ssh/config"), "~/.ssh/config");
}

#[test]
fn userprofile_fallback_when_home_unset() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::env::remove_var("HOME");
    std::env::set_var("USERPROFILE", "C:\\Users\\bob");
    assert_eq!(expand_tilde("~/foo"), "C:\\Users\\bob/foo");
    std::env::remove_var("USERPROFILE");
}

#[test]
fn absolute_path_unchanged() {
    let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    assert_eq!(expand_tilde("/absolute/path"), "/absolute/path");
}

#[cfg(unix)]
#[test]
fn harden_file_perms_sets_owner_only_mode() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("secret.bin");
    std::fs::write(&path, b"x").unwrap();
    // Pre-condition: default umask leaves at least group-readable
    // bits on a fresh file. Sanity-check before the call.
    let before = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_ne!(before, 0o600, "test setup got 0600 unexpectedly");

    harden_file_perms(&path).unwrap();

    let after = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_eq!(after, 0o600);
}

#[cfg(unix)]
#[test]
fn harden_file_perms_errors_on_missing_path() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("does-not-exist");
    let err = harden_file_perms(&path).unwrap_err();
    assert!(err.contains("chmod"));
}

#[test]
fn write_bytes_atomic_round_trips_payload() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("payload.bin");
    write_bytes_atomic(&path, b"hello, atomic world").unwrap();
    let contents = std::fs::read(&path).unwrap();
    assert_eq!(contents, b"hello, atomic world");
}

#[test]
fn write_bytes_atomic_overwrites_existing() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("payload.bin");
    std::fs::write(&path, b"first version").unwrap();
    write_bytes_atomic(&path, b"second version").unwrap();
    let contents = std::fs::read(&path).unwrap();
    assert_eq!(contents, b"second version");
}

#[test]
fn write_bytes_atomic_leaves_no_tmp_on_success() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("payload.bin");
    write_bytes_atomic(&path, b"x").unwrap();
    assert!(path.exists());
    // No leftover `.tmp*` files anywhere in the parent dir.
    let leftover: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().contains(".tmp"))
        .collect();
    assert!(leftover.is_empty(), "stale tmp file: {leftover:?}");
}

#[test]
fn write_bytes_atomic_concurrent_writes_do_not_corrupt_destination() {
    // Mirror of the Dart `writeFileAtomic preserves content on
    // concurrent writes` test. Three parallel writes to the
    // same destination must produce a non-corrupt file with one
    // of the three payloads — the random tmp suffix prevents
    // intermediate-file collisions.
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("race.bin");
    let path_a = path.clone();
    let path_b = path.clone();
    let path_c = path.clone();
    let h_a = std::thread::spawn(move || write_bytes_atomic(&path_a, b"a"));
    let h_b = std::thread::spawn(move || write_bytes_atomic(&path_b, b"b"));
    let h_c = std::thread::spawn(move || write_bytes_atomic(&path_c, b"c"));
    h_a.join().unwrap().unwrap();
    h_b.join().unwrap().unwrap();
    h_c.join().unwrap().unwrap();
    let final_bytes = std::fs::read(&path).unwrap();
    assert_eq!(final_bytes.len(), 1);
    assert!(matches!(final_bytes[0], b'a' | b'b' | b'c'));
}

#[cfg(unix)]
#[test]
fn write_bytes_atomic_lands_destination_at_owner_only_perms() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("payload.bin");
    write_bytes_atomic(&path, b"x").unwrap();
    let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
}

#[test]
fn write_bytes_atomic_errors_when_parent_dir_missing() {
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("does-not-exist").join("payload.bin");
    // Caller is responsible for `create_dir_all`; this helper
    // surfaces ENOENT rather than implicitly creating it, so a
    // misconfigured caller is loud not silent. The exact error
    // tag depends on which step fails first (`create` or
    // `write`); we just pin that *some* I/O step refuses.
    let err = write_bytes_atomic(&path, b"x").unwrap_err();
    assert!(
        err.contains("create") || err.contains("write"),
        "unexpected error tag: {err}",
    );
}

#[test]
fn write_bytes_atomic_fsyncs_payload_before_rename() {
    // Regression for the "rename lands a torn file after a power
    // loss" gap. We cannot synthesise a real crash in a unit
    // test, but we *can* assert that the bytes on disk match the
    // payload byte-for-byte after the helper returns — proving
    // the data hit the destination through the rename path. The
    // `sync_data` step is what guarantees the post-crash
    // observable matches the post-return observable; without
    // it the destination could read empty after a crash even
    // though the test would still see the right bytes here.
    let dir = tempfile::TempDir::new().unwrap();
    let path = dir.path().join("fsync.bin");
    let payload: Vec<u8> = (0..=255u8).cycle().take(64 * 1024).collect();
    write_bytes_atomic(&path, &payload).unwrap();
    let on_disk = std::fs::read(&path).unwrap();
    assert_eq!(on_disk, payload);
}
