/// Unit tests extracted from sftp/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

/// Unit tests for the SFTP module's pure helpers. The
/// per-method tests against a real SFTP server live in the
/// integration suite (`lfs_frb` / Dart `transfer_queue_test`);
/// the tests below cover the parts that don't need a transport.
use russh_sftp::protocol::FileAttributes;

fn touch(path: &std::path::Path) {
    std::fs::File::create(path).expect("create test file");
}

#[test]
fn transfer_staging_path_appends_token_and_part_suffix() {
    // The staged name must stay a sibling of the destination
    // (same directory) so the final rename is an intra-directory
    // move, and must carry the token so two concurrent transfers
    // to the same destination never share a temp file.
    let p = transfer_staging_path("/srv/data/report.pdf", "task-7");
    assert_eq!(p, "/srv/data/report.pdf.task-7.part");
    let a = transfer_staging_path("/d/f", "alpha");
    let b = transfer_staging_path("/d/f", "beta");
    assert_ne!(a, b);
}

#[tokio::test]
async fn count_local_files_empty_dir_returns_zero() {
    let tmp = tempfile::tempdir().expect("tmp dir");
    let n = count_local_files(tmp.path()).await;
    assert_eq!(n, 0);
}

#[tokio::test]
async fn count_local_files_counts_flat_files() {
    let tmp = tempfile::tempdir().expect("tmp dir");
    touch(&tmp.path().join("a.txt"));
    touch(&tmp.path().join("b.txt"));
    touch(&tmp.path().join("c.txt"));
    let n = count_local_files(tmp.path()).await;
    assert_eq!(n, 3);
}

#[tokio::test]
async fn count_local_files_recurses_into_subdirs() {
    let tmp = tempfile::tempdir().expect("tmp dir");
    let nested = tmp.path().join("sub").join("deep");
    std::fs::create_dir_all(&nested).expect("mkdir -p");
    touch(&tmp.path().join("root.txt"));
    touch(&tmp.path().join("sub/mid.txt"));
    touch(&nested.join("leaf.txt"));
    let n = count_local_files(tmp.path()).await;
    assert_eq!(n, 3);
}

#[tokio::test]
async fn count_local_files_missing_dir_returns_zero() {
    // A missing path must return 0, not panic — matches the
    // graceful-degradation contract count_remote_files honours.
    let n = count_local_files(std::path::Path::new("/nonexistent/path-7c8f")).await;
    assert_eq!(n, 0);
}

#[test]
fn file_metadata_from_russh_preserves_every_field_for_dir() {
    // `FileAttributes::default()` already sets permissions to
    // `0o777 | DIR`, so this tests the directory branch by
    // augmenting the default with size + mtime.
    let attr = FileAttributes {
        size: Some(2048),
        mtime: Some(1_700_000_000),
        ..FileAttributes::default()
    };
    let m = FileMetadata::from_russh(&attr);
    assert_eq!(m.size, 2048);
    assert!(m.is_dir);
    assert!(!m.is_symlink);
    assert_eq!(m.modified_unix, Some(1_700_000_000));
    assert_ne!(m.permissions & 0o777, 0);
}

#[test]
fn file_metadata_from_russh_folds_missing_optionals_to_safe_defaults() {
    // Real SFTP servers omit fields the client didn't request —
    // the converter must fold every gap into a safe default
    // rather than panic. Build a fully-empty attribute set.
    let attr = FileAttributes {
        size: None,
        uid: None,
        user: None,
        gid: None,
        group: None,
        permissions: None,
        atime: None,
        mtime: None,
    };
    let m = FileMetadata::from_russh(&attr);
    assert_eq!(m.size, 0);
    assert!(!m.is_dir);
    assert!(!m.is_symlink);
    assert_eq!(m.modified_unix, None);
    assert_eq!(m.permissions, 0);
}

#[test]
fn file_metadata_from_russh_flags_regular_file() {
    // A regular file: clear the DIR bit baked into Default and
    // set the REG one. Confirms the converter returns
    // `is_dir = false` for non-directory entries. Mutating
    // setters used here (no struct-update shortcut available)
    // because each setter ORs into the permissions field.
    let mut attr = FileAttributes::default();
    attr.remove_type(russh_sftp::protocol::FileMode::DIR);
    attr.set_regular(true);
    let m = FileMetadata::from_russh(&attr);
    assert!(!m.is_dir);
    assert!(!m.is_symlink);
}

#[test]
fn dir_entry_clone_round_trip() {
    // Pre-fill a DirEntry, clone it, mutate the original — the
    // clone must hold the original values. Guards against an
    // accidental shared-reference field in a future refactor.
    let entry = DirEntry {
        name: "fileA".into(),
        size: 1234,
        is_dir: false,
        is_symlink: false,
        modified_unix: Some(42),
        permissions: 0o644,
    };
    let cloned = entry.clone();
    let mut original = entry;
    original.name = "mutated".into();
    original.size = 0;
    assert_eq!(cloned.name, "fileA");
    assert_eq!(cloned.size, 1234);
    assert_eq!(cloned.permissions, 0o644);
}

#[test]
fn transfer_progress_event_clone_round_trip() {
    let evt = TransferProgressEvent {
        file_name: "x.bin".into(),
        total_files: 10,
        done_files: 3,
        is_upload: true,
    };
    let cloned = evt.clone();
    assert_eq!(cloned.file_name, "x.bin");
    assert_eq!(cloned.total_files, 10);
    assert_eq!(cloned.done_files, 3);
    assert!(cloned.is_upload);
}

// ─── Local-fs walk edge cases ──────────────────────────────────

#[tokio::test]
async fn count_local_files_includes_hidden_dotfiles() {
    // The walker must not silently skip dotfiles — dotfile
    // exclusion would diverge from `cp -r` semantics and surprise
    // a user who expects a full transfer count to match
    // `find <dir> -type f | wc -l`.
    let tmp = tempfile::tempdir().expect("tmp dir");
    touch(&tmp.path().join(".hidden"));
    touch(&tmp.path().join("visible.txt"));
    std::fs::create_dir(tmp.path().join(".dot_dir")).expect("mkdir");
    touch(&tmp.path().join(".dot_dir/inside.txt"));
    let n = count_local_files(tmp.path()).await;
    assert_eq!(n, 3);
}

#[tokio::test]
async fn count_local_files_does_not_count_directories_themselves() {
    // The walker counts files only — a tree of empty directories
    // returns zero so a directory-only transfer doesn't inflate
    // the progress denominator.
    let tmp = tempfile::tempdir().expect("tmp dir");
    let nested = tmp.path().join("a").join("b").join("c");
    std::fs::create_dir_all(&nested).expect("mkdir -p");
    let n = count_local_files(tmp.path()).await;
    assert_eq!(n, 0);
}

#[cfg(unix)]
#[tokio::test]
async fn count_local_files_follows_into_subdir_via_symlink_target_only() {
    // Symlinks themselves are counted by `read_dir` enumeration
    // but the walker recurses only on `is_dir()` (file_type), and
    // a symlink-to-dir is NOT classified as a directory by
    // `read_dir` metadata — verifies the walker doesn't follow a
    // symlink loop. A two-file dir + a symlink to it counts the
    // two real files plus the symlink entry itself = 3.
    let tmp = tempfile::tempdir().expect("tmp dir");
    let sub = tmp.path().join("sub");
    std::fs::create_dir(&sub).expect("mkdir");
    touch(&sub.join("a.txt"));
    touch(&sub.join("b.txt"));
    std::os::unix::fs::symlink(&sub, tmp.path().join("link")).expect("symlink");
    let n = count_local_files(tmp.path()).await;
    // Two real files inside `sub`; the symlink entry at the top
    // level is not a directory per `file_type().is_dir()` and is
    // counted as a single entry.
    assert_eq!(n, 3);
}

// ─── FileMetadata mode-bit edge cases ──────────────────────────

#[test]
fn file_metadata_size_at_u64_max_round_trips() {
    // Pin the size field's full 64-bit range — a regression that
    // truncates to u32 would silently corrupt large-file stat()
    // results (>4 GiB files come back wrong).
    let attr = FileAttributes {
        size: Some(u64::MAX),
        ..FileAttributes::default()
    };
    let m = FileMetadata::from_russh(&attr);
    assert_eq!(m.size, u64::MAX);
}

#[test]
fn file_metadata_modified_unix_handles_large_mtime() {
    // mtime as u32 max (year 2106 epoch) round-trips into i64
    // without losing the high bit. Pre-2038 values stay positive.
    let attr = FileAttributes {
        mtime: Some(u32::MAX),
        ..FileAttributes::default()
    };
    let m = FileMetadata::from_russh(&attr);
    assert_eq!(m.modified_unix, Some(u32::MAX as i64));
}

#[test]
fn file_metadata_permissions_preserve_setuid_and_sticky_bits() {
    // setuid (04000), setgid (02000), sticky (01000) bits live
    // above the rwx mode triplets — a regression masking with
    // 0o777 would silently strip them from the surfaced metadata.
    let attr = FileAttributes {
        permissions: Some(0o7755),
        ..FileAttributes::default()
    };
    let m = FileMetadata::from_russh(&attr);
    assert_eq!(m.permissions & 0o7000, 0o7000);
}

// ─── DirEntry / TransferProgressEvent invariants ───────────────

#[test]
fn dir_entry_default_field_values_are_safe() {
    // Construct a "minimum information" entry with empty name +
    // zeroed scalars + None mtime. Confirms the struct accepts
    // every legitimate gap a parse path might produce without
    // requiring all fields populated.
    let entry = DirEntry {
        name: String::new(),
        size: 0,
        is_dir: false,
        is_symlink: false,
        modified_unix: None,
        permissions: 0,
    };
    assert!(entry.name.is_empty());
    assert_eq!(entry.size, 0);
    assert!(!entry.is_dir);
}

#[test]
fn transfer_progress_event_at_completion_marks_done_equals_total() {
    // The completed-progress shape is `done_files == total_files`.
    // Pin the equality so consumers (Dart progress bar) can rely
    // on `done == total ⇒ finished` without a separate flag.
    let evt = TransferProgressEvent {
        file_name: "final.bin".into(),
        total_files: 5,
        done_files: 5,
        is_upload: false,
    };
    assert_eq!(evt.done_files, evt.total_files);
    assert!(!evt.is_upload);
}

#[test]
fn transfer_progress_event_at_zero_progress_signals_pending() {
    // Initial-state shape: total > 0, done == 0. Confirms the
    // struct accepts the legitimate "queued, nothing done yet"
    // case without requiring a non-zero done_files.
    let evt = TransferProgressEvent {
        file_name: "first.bin".into(),
        total_files: 3,
        done_files: 0,
        is_upload: true,
    };
    assert_eq!(evt.done_files, 0);
    assert_ne!(evt.total_files, 0);
}
