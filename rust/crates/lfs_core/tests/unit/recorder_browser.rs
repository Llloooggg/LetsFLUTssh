/// Unit tests extracted from recorder/browser.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::fs;
use std::io::Write;

fn temp_root(suffix: &str) -> std::path::PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let pid = std::process::id();
    let dir = std::env::temp_dir().join(format!("lfs_browser_test_{pid}_{n}_{suffix}"));
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn list_returns_empty_when_root_missing() {
    let nonexistent = std::env::temp_dir().join("lfs_browser_test_does_not_exist_xyz");
    let _ = fs::remove_dir_all(&nonexistent);
    let out = list_recordings(&nonexistent).expect("missing root is not an error");
    assert!(out.is_empty());
}

#[test]
fn list_returns_empty_for_empty_root() {
    let root = temp_root("empty");
    let out = list_recordings(&root).unwrap();
    assert!(out.is_empty());
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn list_filters_to_cast_and_lfsr_extensions() {
    let root = temp_root("filter");
    let session = root.join("sess-1");
    fs::create_dir_all(&session).unwrap();
    fs::File::create(session.join("a.cast"))
        .unwrap()
        .write_all(b"hello")
        .unwrap();
    fs::File::create(session.join("b.lfsr"))
        .unwrap()
        .write_all(b"world")
        .unwrap();
    // .txt is the unrelated-extension case the spec rejects.
    fs::File::create(session.join("c.txt"))
        .unwrap()
        .write_all(b"skip")
        .unwrap();
    // A nested directory inside the session dir must be skipped
    // (recordings are flat under their session).
    fs::create_dir_all(session.join("nested")).unwrap();

    let mut out = list_recordings(&root).unwrap();
    out.sort_by(|a, b| a.file_name.cmp(&b.file_name));
    assert_eq!(out.len(), 2);
    assert_eq!(out[0].file_name, "a.cast");
    assert_eq!(out[0].extension, "cast");
    assert!(!out[0].encrypted);
    assert_eq!(out[0].session_id, "sess-1");
    assert_eq!(out[0].size_bytes, 5);
    assert_eq!(out[1].file_name, "b.lfsr");
    assert_eq!(out[1].extension, "lfsr");
    assert!(out[1].encrypted);
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn list_skips_files_directly_under_root() {
    // `<root>/orphan.cast` (no session subdir) is invalid layout
    // — every recording must live under its session id. The
    // walk skips bare files at the root level.
    let root = temp_root("rootfile");
    fs::File::create(root.join("orphan.cast"))
        .unwrap()
        .write_all(b"x")
        .unwrap();
    let out = list_recordings(&root).unwrap();
    assert!(out.is_empty());
    let _ = fs::remove_dir_all(&root);
}

#[cfg(unix)]
#[test]
fn list_skips_symlinked_session_dir() {
    // A symlink at <root>/<dir> pointing outside the
    // recordings tree must NOT be traversed. The walk uses
    // symlink_metadata to detect the link and skip it without
    // dereferencing.
    use std::os::unix::fs::symlink;
    let root = temp_root("symlink-dir");
    let real = temp_root("symlink-target");
    fs::File::create(real.join("decoy.cast"))
        .unwrap()
        .write_all(b"x")
        .unwrap();
    symlink(&real, root.join("sess-link")).unwrap();
    let out = list_recordings(&root).unwrap();
    assert!(out.is_empty());
    let _ = fs::remove_dir_all(&root);
    let _ = fs::remove_dir_all(&real);
}

#[cfg(unix)]
#[test]
fn list_skips_symlinked_file_inside_session_dir() {
    use std::os::unix::fs::symlink;
    let root = temp_root("symlink-file");
    let session = root.join("sess-1");
    fs::create_dir_all(&session).unwrap();
    let real_file = root.join("outside.cast");
    fs::File::create(&real_file)
        .unwrap()
        .write_all(b"x")
        .unwrap();
    symlink(&real_file, session.join("decoy.cast")).unwrap();
    let out = list_recordings(&root).unwrap();
    assert!(out.is_empty());
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn list_includes_uppercase_extensions_via_lowercase_match() {
    // macOS / Windows can produce mixed-case extensions on
    // user-renamed files; the filter compares lowercased ext
    // so `.LFSR` is still recognised as encrypted.
    let root = temp_root("upper");
    let session = root.join("sess-1");
    fs::create_dir_all(&session).unwrap();
    fs::File::create(session.join("a.LFSR"))
        .unwrap()
        .write_all(b"x")
        .unwrap();
    let out = list_recordings(&root).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].extension, "lfsr");
    assert!(out[0].encrypted);
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_removes_existing_file() {
    let root = temp_root("del");
    let session = root.join("sess-1");
    fs::create_dir_all(&session).unwrap();
    let target = session.join("a.cast");
    fs::File::create(&target).unwrap().write_all(b"x").unwrap();
    delete_recording(&root, "sess-1", "a.cast").expect("delete ok");
    assert!(!target.exists());
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_missing_target_is_idempotent() {
    let root = temp_root("del-missing");
    // Session dir does not exist either — the delete still
    // collapses to Ok rather than surfacing NotFound.
    delete_recording(&root, "sess-x", "ghost.cast").expect("idempotent on missing");
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_rejects_dotdot_in_session_id() {
    let root = temp_root("del-traversal-sid");
    let err = delete_recording(&root, "..", "a.cast").unwrap_err();
    assert!(matches!(err, BrowserError::InvalidComponent));
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_rejects_dotdot_in_file_name() {
    let root = temp_root("del-traversal-fn");
    let err = delete_recording(&root, "sess-1", "..").unwrap_err();
    assert!(matches!(err, BrowserError::InvalidComponent));
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_rejects_path_separator_in_session_id() {
    let root = temp_root("del-sep-sid");
    let err = delete_recording(&root, "sess/../etc", "a.cast").unwrap_err();
    assert!(matches!(err, BrowserError::InvalidComponent));
    let err = delete_recording(&root, r"sess\..\etc", "a.cast").unwrap_err();
    assert!(matches!(err, BrowserError::InvalidComponent));
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_rejects_path_separator_in_file_name() {
    let root = temp_root("del-sep-fn");
    let err = delete_recording(&root, "sess-1", "../foo.cast").unwrap_err();
    assert!(matches!(err, BrowserError::InvalidComponent));
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn delete_rejects_empty_components() {
    let root = temp_root("del-empty");
    assert!(matches!(
        delete_recording(&root, "", "a.cast").unwrap_err(),
        BrowserError::InvalidComponent
    ));
    assert!(matches!(
        delete_recording(&root, "sess", "").unwrap_err(),
        BrowserError::InvalidComponent
    ));
    let _ = fs::remove_dir_all(&root);
}
