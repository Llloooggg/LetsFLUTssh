/// Unit tests extracted from security/tier_transition_marker.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tempfile::TempDir;

#[test]
fn read_returns_none_when_marker_absent() {
    let dir = TempDir::new().unwrap();
    assert_eq!(read(dir.path()), None);
}

#[test]
fn write_then_read_round_trips_payload() {
    let dir = TempDir::new().unwrap();
    let body = r#"{"target":"keychain"}"#;
    write(dir.path(), body).unwrap();
    assert_eq!(read(dir.path()).as_deref(), Some(body));
}

#[test]
fn write_overwrites_existing_marker() {
    let dir = TempDir::new().unwrap();
    write(dir.path(), "first").unwrap();
    write(dir.path(), "second").unwrap();
    assert_eq!(read(dir.path()).as_deref(), Some("second"));
}

#[test]
fn read_rejects_file_without_magic() {
    let dir = TempDir::new().unwrap();
    // A leftover from an unrelated tool / hostile drop. Read
    // must treat it as absent so the switcher does not act on
    // an attacker-shaped payload.
    std::fs::write(dir.path().join(MARKER_FILE_NAME), b"{\"target\":\"x\"}").unwrap();
    assert!(read(dir.path()).is_none());
}

#[test]
fn read_rejects_unknown_version() {
    let dir = TempDir::new().unwrap();
    let mut bytes = Vec::from(*MAGIC);
    bytes.push(VERSION + 1);
    bytes.extend_from_slice(b"body");
    std::fs::write(dir.path().join(MARKER_FILE_NAME), &bytes).unwrap();
    assert!(read(dir.path()).is_none());
}

#[test]
fn read_rejects_truncated_header() {
    let dir = TempDir::new().unwrap();
    std::fs::write(dir.path().join(MARKER_FILE_NAME), b"LF").unwrap();
    assert!(read(dir.path()).is_none());
}

#[test]
fn clear_removes_existing_marker() {
    let dir = TempDir::new().unwrap();
    write(dir.path(), "x").unwrap();
    clear(dir.path()).unwrap();
    assert!(read(dir.path()).is_none());
}

#[test]
fn clear_is_idempotent_on_missing() {
    let dir = TempDir::new().unwrap();
    clear(dir.path()).unwrap();
}

#[test]
fn write_creates_parent_dir_when_missing() {
    // Production callers point at the platform app-support dir
    // (always exists), but tests pass a fresh temp dir that may
    // not yet exist. The writer must create it rather than
    // throwing on `ENOENT`.
    let parent = TempDir::new().unwrap();
    let support = parent.path().join("not-yet-created");
    write(&support, "x").unwrap();
    assert_eq!(read(&support).as_deref(), Some("x"));
}

#[cfg(unix)]
#[test]
fn write_lands_marker_at_owner_only_perms() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TempDir::new().unwrap();
    write(dir.path(), "x").unwrap();
    let mode = std::fs::metadata(dir.path().join(MARKER_FILE_NAME))
        .unwrap()
        .permissions()
        .mode()
        & 0o777;
    assert_eq!(mode, 0o600);
}
