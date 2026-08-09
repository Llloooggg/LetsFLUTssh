//! Unit tests extracted from ssh_agent/transport
//!
//! Declared via `#[path] mod tests;` in the source file.

use super::*;

#[test]
fn unix_socket_path_uses_pid_suffix() {
    let path = unix_socket_path();
    let s = path.to_string_lossy();
    assert!(s.contains("letsflutssh-agent."));
    assert!(s.ends_with("agent.sock"));
}

/// Both bind_unix tests run inside the same `cargo test`
/// process, sharing the per-pid path. Serialise so they don't
/// race for the same socket file. A `Mutex<()>` is enough —
/// the test runner schedules tests across threads but never
/// against the same lock concurrently.
static UNIX_BIND_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[tokio::test]
async fn bind_unix_creates_owner_only_parent() {
    use std::os::unix::fs::PermissionsExt;
    let _g = UNIX_BIND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (listener, path) = bind_unix().unwrap();
    let parent = path.parent().unwrap();
    let perms = std::fs::metadata(parent).unwrap().permissions();
    // The low 12 bits encode the unix mode.
    assert_eq!(perms.mode() & 0o777, 0o700);
    drop(listener);
    cleanup_unix(&path);
}

#[tokio::test]
async fn bind_unix_replaces_stale_socket() {
    let _g = UNIX_BIND_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let (l1, path) = bind_unix().unwrap();
    // Drop the listener so the second bind can claim the path.
    drop(l1);
    // Recreate the listener — the implementation removes the
    // stale file first, so the second bind must succeed.
    let (l2, _) = bind_unix().unwrap();
    drop(l2);
    cleanup_unix(&path);
}
