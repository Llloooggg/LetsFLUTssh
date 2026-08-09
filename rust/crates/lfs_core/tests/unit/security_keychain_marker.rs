/// Unit tests extracted from security/keychain_marker.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tempfile::TempDir;

#[test]
fn exists_is_false_when_marker_absent() {
    let dir = TempDir::new().unwrap();
    assert!(!exists(dir.path()));
}

#[test]
fn set_creates_marker_with_flag_payload() {
    let dir = TempDir::new().unwrap();
    set(dir.path()).unwrap();
    assert!(exists(dir.path()));
    let contents = std::fs::read(dir.path().join(MARKER_FILE_NAME)).unwrap();
    assert_eq!(contents, b"1");
}

#[test]
fn set_is_idempotent() {
    let dir = TempDir::new().unwrap();
    set(dir.path()).unwrap();
    set(dir.path()).unwrap();
    assert!(exists(dir.path()));
}

#[test]
fn clear_removes_existing_marker() {
    let dir = TempDir::new().unwrap();
    set(dir.path()).unwrap();
    clear(dir.path()).unwrap();
    assert!(!exists(dir.path()));
}

#[test]
fn clear_is_idempotent_on_missing() {
    let dir = TempDir::new().unwrap();
    // Never set — clear must not error on a missing file.
    clear(dir.path()).unwrap();
    assert!(!exists(dir.path()));
}

#[test]
fn set_creates_parent_dir_if_missing() {
    // Production callers point at the platform app-support dir,
    // which the OS creates on first launch — but tests pass a
    // fresh temp dir path that may not yet exist. The writer must
    // create it rather than throwing on `ENOENT`.
    let parent = TempDir::new().unwrap();
    let support = parent.path().join("not-yet-created");
    set(&support).unwrap();
    assert!(exists(&support));
}

#[cfg(unix)]
#[test]
fn set_lands_marker_at_owner_only_perms() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TempDir::new().unwrap();
    set(dir.path()).unwrap();
    let mode = std::fs::metadata(dir.path().join(MARKER_FILE_NAME))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    assert_eq!(mode, 0o600);
}
