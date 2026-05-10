//! Process-wide sink for `<app_support>/logs/letsflutssh.log`.
//!
//! Why Rust-side: the Dart `AppLogger` already routes formatting +
//! sanitisation, broadcasts entries to the live viewer, and gates
//! pre-FRB `logCritical` writes through an in-memory ring buffer.
//! Letting Dart also own the `dart:io` file handle would split the
//! permissions / rotation / read-back contract across two languages
//! and re-introduce the chmod + recursive-mkdir quirks the
//! `lfs_core::path::harden_*` helpers exist to centralise. One
//! sink, one owner, one chmod helper.
//!
//! State model: a single [`std::sync::Mutex`] holds the held log
//! path + an open `BufWriter<File>` for routine writes. The mutex
//! is acquired briefly inside each public entry point; per-call
//! work is short (one `write` + best-effort flush) so contention
//! between the live writer and a Settings → Read tab is bounded.
//!
//! Sink lifecycle:
//!
//! * [`open_sink`] resolves `<dir>/logs/letsflutssh.log`, creates
//!   the parent directory if needed, opens the file in append mode,
//!   hardens to `0600` on POSIX (no-op on Windows — the app-support
//!   tree inherits the user's profile ACL). Idempotent on the same
//!   directory; switching directory closes the prior sink and
//!   reopens at the new path.
//! * [`append_line`] / [`append_critical`] write rendered (already
//!   sanitised) lines into the file. Routine `append_line` writes
//!   through the held `BufWriter`; `append_critical` opens a fresh
//!   `OpenOptions::append` handle so a crash entry lands even when
//!   the routine sink is closed (user has logging off).
//! * [`rotate_if_needed`] cycles `<log>.N → <log>.N+1` down to
//!   `<log>.1`, then renames the current file. Sink is closed
//!   before the rename and reopened on the same path afterwards.
//! * [`read_all`] flushes the held sink then returns the full file
//!   contents — the Settings → Logs viewer's initial-read shape.
//! * [`clear_all`] closes the sink and deletes the current file
//!   plus every rotated sibling. The caller (Dart `AppLogger`)
//!   decides whether to call [`open_sink`] again afterwards.
//! * [`close_sink`] flushes + drops the held handle; idempotent.
//!
//! All entry points return `Result<_, String>` matching the
//! project convention. The Dart layer logs and swallows so a
//! best-effort I/O miss never breaks the surrounding flow.

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// Held state for the routine-write sink. `sink == None` means
/// logging is currently off (the user has not picked a threshold
/// in Settings, or `close_sink` has been called explicitly). The
/// path stays populated across open/close cycles so subsequent
/// `read_all` / `clear_all` calls keep working without a fresh
/// [`open_sink`].
struct FileSinkState {
    log_path: Option<PathBuf>,
    sink: Option<std::io::BufWriter<File>>,
}

impl FileSinkState {
    const fn new() -> Self {
        Self {
            log_path: None,
            sink: None,
        }
    }
}

/// Process-wide held sink. `Mutex` (not `RwLock`) — every call
/// either reads + writes the path or holds the writer; there is
/// no read-mostly workload to optimise.
static STATE: Mutex<FileSinkState> = Mutex::new(FileSinkState::new());

/// Compose `<app_support_dir>/logs/letsflutssh.log` without
/// touching the filesystem. Pulled out for use by the open-fresh
/// `append_critical` path which needs the resolved path even when
/// the held sink is closed.
fn compose_log_path(app_support_dir: &str) -> PathBuf {
    Path::new(app_support_dir)
        .join("logs")
        .join("letsflutssh.log")
}

/// Open the routine-write sink rooted under [`app_support_dir`].
///
/// Resolves the final path to `<app_support_dir>/logs/letsflutssh.log`,
/// creates the `logs/` parent directory if absent, opens the file
/// in append mode, and hardens to `0600` on POSIX. Returns the
/// resolved log-path string for the caller to cache (Dart's
/// `AppLogger._logPath`).
///
/// Idempotent on the same [`app_support_dir`] — a second call
/// reuses the held sink. Switching to a different directory
/// closes the prior sink and reopens at the new path; rare in
/// production (would require switching app-support roots mid-run)
/// but used by tests that point successive cases at distinct
/// `tempfile::TempDir`s.
///
/// Failure modes: parent-dir create error, file open error, chmod
/// error. The chmod step is best-effort and never blocks the
/// open — a file at the umask-wide default is worse than no log
/// file at all.
pub fn open_sink(app_support_dir: &str) -> Result<String, String> {
    let target_path = compose_log_path(app_support_dir);
    let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
    if let Some(existing) = guard.log_path.as_ref() {
        if existing == &target_path && guard.sink.is_some() {
            return Ok(target_path.to_string_lossy().into_owned());
        }
        // Different directory or sink dropped — close the prior
        // handle before reopening so two `BufWriter`s never share
        // the same fd on top of one path.
        if let Some(mut prior) = guard.sink.take() {
            let _ = prior.flush();
        }
    }
    let logs_dir = target_path
        .parent()
        .ok_or_else(|| format!("invalid log path {}", target_path.display()))?;
    std::fs::create_dir_all(logs_dir).map_err(|e| format!("create {}: {e}", logs_dir.display()))?;
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&target_path)
        .map_err(|e| format!("open {}: {e}", target_path.display()))?;
    let writer = std::io::BufWriter::new(file);
    guard.log_path = Some(target_path.clone());
    guard.sink = Some(writer);
    drop(guard);
    // chmod 0600 on Unix; icacls on Windows. Errors are surfaced
    // for the caller to log but never propagate up — a hardening
    // miss must not block logging itself.
    let _ = crate::path::harden_file_perms(&target_path);
    Ok(target_path.to_string_lossy().into_owned())
}

/// Append a single rendered line to the held sink. The caller
/// hands in the full timestamp + level + tag + message body
/// already composed (and sanitised by `AppLogger.sanitize`); this
/// helper only writes `line + "\n"` through the `BufWriter`.
///
/// No-op when the held sink is `None` (routine logging is off);
/// returns `Ok(())` so call sites do not need to branch on
/// threshold state Rust-side. The Dart caller has already gated
/// against `_threshold == null` before reaching here.
///
/// Each `append_line` flushes the held `BufWriter` so the line
/// reaches the OS file cache before this returns. A crash within
/// the next few milliseconds still surfaces the entry — without
/// the flush, the line could sit buffered until the next
/// rotation / close.
pub fn append_line(line: &str) -> Result<(), String> {
    let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
    let Some(writer) = guard.sink.as_mut() else {
        return Ok(());
    };
    writer
        .write_all(line.as_bytes())
        .map_err(|e| format!("append: {e}"))?;
    writer
        .write_all(b"\n")
        .map_err(|e| format!("append: {e}"))?;
    writer.flush().map_err(|e| format!("flush: {e}"))?;
    Ok(())
}

/// Append a critical entry — the header line plus zero or more
/// continuation lines (typically `"  Error: ..."` followed by a
/// `"  Stack trace:"` block). Always flushed; opens a fresh
/// `OpenOptions::append` handle rather than going through the
/// held sink so the write lands even when routine logging is off
/// (the user has not flipped the Settings threshold).
///
/// Recreates the `logs/` parent directory if a prior
/// `clear_all` (or a user-side rm -rf) wiped it between the last
/// `open_sink` and this critical write — symmetric with the Dart
/// implementation's `file.parent.create(recursive: true)` belt.
///
/// No-op when no log path is registered (a `logCritical` fired
/// before `open_sink` ran is buffered Dart-side and replayed
/// post-FRB via the same entry point).
pub fn append_critical(line: &str, continuations: &[String]) -> Result<(), String> {
    let path: PathBuf = {
        let guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        match guard.log_path.as_ref() {
            Some(p) => p.clone(),
            None => return Ok(()),
        }
    };
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("create {}: {e}", parent.display()))?;
    }
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| format!("open {}: {e}", path.display()))?;
    file.write_all(line.as_bytes())
        .map_err(|e| format!("critical: {e}"))?;
    file.write_all(b"\n")
        .map_err(|e| format!("critical: {e}"))?;
    for c in continuations {
        file.write_all(c.as_bytes())
            .map_err(|e| format!("critical: {e}"))?;
        file.write_all(b"\n")
            .map_err(|e| format!("critical: {e}"))?;
    }
    file.flush().map_err(|e| format!("critical flush: {e}"))?;
    drop(file);
    // Re-harden after the fresh open in case the file was just
    // created here (no prior `open_sink` ran). On a pre-existing
    // file this is a no-op tightening of an already-0600 file.
    let _ = crate::path::harden_file_perms(&path);
    Ok(())
}

/// Flush the held `BufWriter`. Best-effort. No-op when the sink
/// is closed. Used by the Settings → Logs viewer's `read_all` to
/// drain any buffered routine writes before reading the file.
pub fn flush() -> Result<(), String> {
    let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
    if let Some(writer) = guard.sink.as_mut() {
        writer.flush().map_err(|e| format!("flush: {e}"))?;
    }
    Ok(())
}

/// Read the entire current log file. Flushes the held sink first
/// so routine entries written this run already reached the OS file
/// cache before the read. Returns an empty string when no log
/// path is registered or the file does not exist.
pub fn read_all() -> Result<String, String> {
    // Flush + capture path inside one lock window so a concurrent
    // `clear_all` cannot drop the file between flush and open.
    let path: PathBuf = {
        let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        if let Some(writer) = guard.sink.as_mut() {
            let _ = writer.flush();
        }
        match guard.log_path.as_ref() {
            Some(p) => p.clone(),
            None => return Ok(String::new()),
        }
    };
    if !path.exists() {
        return Ok(String::new());
    }
    let mut file = File::open(&path).map_err(|e| format!("open {}: {e}", path.display()))?;
    let mut buf = String::new();
    file.read_to_string(&mut buf)
        .map_err(|e| format!("read {}: {e}", path.display()))?;
    Ok(buf)
}

/// Rotate the current log file if it exceeds [`max_bytes`].
///
/// The on-disk chain is `<log>` → `<log>.1` → `<log>.2` → … →
/// `<log>.<max_rotated>`. Walks from the highest existing index
/// down so each step renames into a slot the previous step
/// vacated. Anything that would land at `<log>.<max_rotated + 1>`
/// is dropped on the floor (the bound is a hard ceiling).
///
/// Closes the held sink before renaming the current file and
/// reopens at the same path afterwards so subsequent
/// `append_line` calls see a fresh empty file. No-op when no
/// log path is registered or the file does not yet exist.
pub fn rotate_if_needed(max_bytes: u64, max_rotated: u32) -> Result<(), String> {
    let path: PathBuf = {
        let guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        match guard.log_path.as_ref() {
            Some(p) => p.clone(),
            None => return Ok(()),
        }
    };
    if !path.exists() {
        return Ok(());
    }
    let size = std::fs::metadata(&path)
        .map_err(|e| format!("stat {}: {e}", path.display()))?
        .len();
    if size < max_bytes {
        return Ok(());
    }
    // Drop the held writer so the rename is not racing a buffered
    // write into the file we are about to move out from under it.
    {
        let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        if let Some(mut writer) = guard.sink.take() {
            let _ = writer.flush();
        }
    }
    // Walk N-1 → N for N = max_rotated downto 1, then current → .1.
    // Highest index first so the chain shifts cleanly.
    for i in (1..max_rotated).rev() {
        let src = sibling_with_index(&path, i);
        if src.exists() {
            let dst = sibling_with_index(&path, i + 1);
            std::fs::rename(&src, &dst)
                .map_err(|e| format!("rotate {} -> {}: {e}", src.display(), dst.display()))?;
        }
    }
    let first = sibling_with_index(&path, 1);
    std::fs::rename(&path, &first)
        .map_err(|e| format!("rotate {} -> {}: {e}", path.display(), first.display()))?;
    // Reopen the same path so subsequent writes continue into a
    // fresh empty file. Harden perms again because the freshly
    // created post-rotate file lands at the umask default.
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| format!("reopen {}: {e}", path.display()))?;
    {
        let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        guard.sink = Some(std::io::BufWriter::new(file));
    }
    let _ = crate::path::harden_file_perms(&path);
    Ok(())
}

/// Delete the current log file and every rotated sibling up to
/// `<log>.<max_rotated>`. Closes the held sink before unlinking
/// so the kernel does not hold an fd open against a path we are
/// removing.
///
/// Idempotent on missing files. The caller (Dart `AppLogger`)
/// decides whether to call [`open_sink`] again to start a fresh
/// session; this helper deliberately leaves the sink closed so a
/// test that wants to assert "after clear, nothing on disk" can
/// see the empty state without race.
pub fn clear_all(max_rotated: u32) -> Result<(), String> {
    let path: PathBuf = {
        let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
        if let Some(mut writer) = guard.sink.take() {
            let _ = writer.flush();
        }
        match guard.log_path.as_ref() {
            Some(p) => p.clone(),
            None => return Ok(()),
        }
    };
    let mut targets: Vec<PathBuf> = Vec::with_capacity(max_rotated as usize + 1);
    targets.push(path.clone());
    for i in 1..=max_rotated {
        targets.push(sibling_with_index(&path, i));
    }
    for t in &targets {
        if t.exists() {
            std::fs::remove_file(t).map_err(|e| format!("rm {}: {e}", t.display()))?;
        }
    }
    Ok(())
}

/// Flush + drop the held writer. Idempotent — calling on an
/// already-closed sink is a no-op. The held log path is kept so
/// subsequent `append_critical` / `read_all` calls still resolve
/// against the same file without needing a fresh `open_sink`.
pub fn close_sink() -> Result<(), String> {
    let mut guard = STATE.lock().map_err(|e| format!("sink lock: {e}"))?;
    if let Some(mut writer) = guard.sink.take() {
        writer.flush().map_err(|e| format!("close flush: {e}"))?;
    }
    Ok(())
}

/// Compose `<log>.<index>` against the held log path. Inlined
/// here rather than in `path.rs` because the `<base>.<N>` index
/// convention is specific to the rotation chain owned by this
/// module.
fn sibling_with_index(base: &Path, index: u32) -> PathBuf {
    let mut s = base.as_os_str().to_owned();
    s.push(format!(".{index}"));
    PathBuf::from(s)
}

#[cfg(test)]
mod tests {
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
        // `.2` now holds the prior `.1`; `.3` holds the prior `.2`;
        // `.1` is the just-rotated current file.
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
}
