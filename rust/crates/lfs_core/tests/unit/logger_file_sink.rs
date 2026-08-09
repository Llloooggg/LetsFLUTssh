/// Unit tests extracted from logger/file_sink.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use std::sync::Mutex as StdMutex;

/// Every test mutates the process-wide `STATE`. Serialise so
/// `cargo test --test-threads` does not interleave a `read_all`
/// from case A with a `clear_all` from case B. Lock acquired
/// with `unwrap_or_else` so a poisoned mutex does not skip
/// subsequent tests.
static TEST_LOCK: StdMutex<()> = StdMutex::new(());

fn reset_state() {
    // Drop the held sink + path so each test starts clean.
    // `into_inner()` on a poisoned guard still returns the
    // inner state — every field this module owns tolerates the
    // poison-after-panic shape (no torn invariant).
    let mut guard = STATE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(mut w) = guard.sink.take() {
        let _ = w.flush();
    }
    guard.log_path = None;
}

#[test]
fn open_append_read_round_trip() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = open_sink(dir.path().to_str().unwrap()).unwrap();
    assert!(path.ends_with("letsflutssh.log"));
    append_line("hello world").unwrap();
    append_line("second line").unwrap();
    let body = read_all().unwrap();
    assert!(body.contains("hello world"));
    assert!(body.contains("second line"));
}

#[test]
fn append_critical_works_without_open_sink_only_after_path_registered() {
    // `append_critical` without a prior `open_sink` is a no-op
    // (the path is not yet registered). After `open_sink` runs
    // it writes through a fresh handle that does not depend on
    // the held `BufWriter`.
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    // No path registered yet — silent no-op.
    append_critical("ignored", &[]).unwrap();
    let dir = tempfile::TempDir::new().unwrap();
    open_sink(dir.path().to_str().unwrap()).unwrap();
    close_sink().unwrap();
    // Routine sink closed — critical write still lands.
    append_critical(
        "fatal x",
        &["  Error: boom".into(), "  Stack trace:".into()],
    )
    .unwrap();
    let body = read_all().unwrap();
    assert!(body.contains("fatal x"));
    assert!(body.contains("Error: boom"));
    assert!(body.contains("Stack trace:"));
}

#[test]
fn open_sink_is_idempotent_on_same_dir() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let first = open_sink(dir.path().to_str().unwrap()).unwrap();
    let second = open_sink(dir.path().to_str().unwrap()).unwrap();
    assert_eq!(first, second);
    append_line("once").unwrap();
    let body = read_all().unwrap();
    assert!(body.contains("once"));
}

#[test]
fn rotate_moves_oversize_file_to_dot_one() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    append_line(&"x".repeat(1024)).unwrap();
    rotate_if_needed(100, 3).unwrap();
    let rotated = sibling_with_index(&path, 1);
    assert!(rotated.exists(), "expected {} to exist", rotated.display());
    // Original path reopened empty.
    let after = std::fs::read_to_string(&path).unwrap();
    assert!(after.is_empty(), "expected fresh file, got {after:?}");
}

#[test]
fn rotate_shifts_existing_rotated_files() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    // Pre-seed `.1` and `.2`.
    std::fs::write(sibling_with_index(&path, 1), b"old1").unwrap();
    std::fs::write(sibling_with_index(&path, 2), b"old2").unwrap();
    append_line(&"x".repeat(200)).unwrap();
    rotate_if_needed(50, 3).unwrap();
    // After rotation: `.2` holds what `.1` was, `.3` holds what
    // `.2` was, `.1` is the just-rotated current file.
    assert_eq!(
        std::fs::read(sibling_with_index(&path, 2)).unwrap(),
        b"old1"
    );
    assert_eq!(
        std::fs::read(sibling_with_index(&path, 3)).unwrap(),
        b"old2"
    );
    assert!(sibling_with_index(&path, 1).exists());
}

#[test]
fn rotate_is_noop_when_under_threshold() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    append_line("tiny").unwrap();
    rotate_if_needed(1024 * 1024, 3).unwrap();
    assert!(!sibling_with_index(&path, 1).exists());
}

#[test]
fn clear_all_removes_current_and_every_rotated_sibling() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    append_line("present").unwrap();
    std::fs::write(sibling_with_index(&path, 1), b"r1").unwrap();
    std::fs::write(sibling_with_index(&path, 2), b"r2").unwrap();
    std::fs::write(sibling_with_index(&path, 3), b"r3").unwrap();
    clear_all(3).unwrap();
    assert!(!path.exists());
    for i in 1..=3 {
        assert!(!sibling_with_index(&path, i).exists());
    }
}

#[test]
fn close_sink_is_idempotent() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    open_sink(dir.path().to_str().unwrap()).unwrap();
    close_sink().unwrap();
    close_sink().unwrap();
    // After close, append_line is a silent no-op (sink is None).
    append_line("ignored").unwrap();
    let body = read_all().unwrap();
    assert!(body.is_empty());
}

#[test]
fn read_all_returns_empty_when_no_path_registered() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    assert!(read_all().unwrap().is_empty());
}

#[test]
fn open_sink_recreates_logs_dir_when_missing() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    // First open creates the logs/ subdir.
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    close_sink().unwrap();
    // External wipe of the logs/ dir.
    let logs_dir = path.parent().unwrap();
    std::fs::remove_dir_all(logs_dir).unwrap();
    assert!(!logs_dir.exists());
    // Second open recreates it.
    open_sink(dir.path().to_str().unwrap()).unwrap();
    assert!(logs_dir.exists());
}

#[test]
fn append_critical_recreates_parent_after_external_wipe() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    let logs_dir = path.parent().unwrap().to_path_buf();
    close_sink().unwrap();
    std::fs::remove_dir_all(&logs_dir).unwrap();
    append_critical("post-wipe", &[]).unwrap();
    assert!(logs_dir.exists());
    assert!(path.exists());
}

#[cfg(unix)]
#[test]
fn open_sink_chmods_log_file_to_owner_only() {
    use std::os::unix::fs::PermissionsExt;
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    let path = PathBuf::from(open_sink(dir.path().to_str().unwrap()).unwrap());
    let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
}

#[test]
fn concurrent_appends_from_two_threads_both_land() {
    let _g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_state();
    let dir = tempfile::TempDir::new().unwrap();
    open_sink(dir.path().to_str().unwrap()).unwrap();
    let h1 = std::thread::spawn(|| {
        for i in 0..50 {
            append_line(&format!("a-{i}")).unwrap();
        }
    });
    let h2 = std::thread::spawn(|| {
        for i in 0..50 {
            append_line(&format!("b-{i}")).unwrap();
        }
    });
    h1.join().unwrap();
    h2.join().unwrap();
    let body = read_all().unwrap();
    assert!(body.contains("a-0"));
    assert!(body.contains("a-49"));
    assert!(body.contains("b-0"));
    assert!(body.contains("b-49"));
}
