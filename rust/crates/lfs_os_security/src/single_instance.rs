//! Cross-platform single-instance file lock.
//!
//! Holds an exclusive advisory lock on a file inside the app
//! support directory; a second process that opens the same file
//! and tries to lock it sees `EWOULDBLOCK` and exits early. The OS
//! releases the lock automatically when the process terminates
//! (even on crash) so there are no stale lock files to clean up.
//!
//! ## Lock primitive choice
//!
//! POSIX defines two independent advisory-lock families:
//! - `fcntl(F_SETLK)` — POSIX record locks, per-fd / inode.
//! - `flock()` — BSD whole-file locks, per-file-description.
//!
//! On Linux they do not contend with each other — a process holding
//! `flock` does not block a different process taking `fcntl(F_SETLK)`,
//! and vice versa. Dart `RandomAccessFile.lock(FileLock.exclusive)`
//! resolves to `flock()` on Linux/macOS, so this module also uses
//! `flock` (via `libc::flock(LOCK_EX | LOCK_NB)`) — that way, any
//! Dart-side test or third-party tool that probes the lock with
//! `RandomAccessFile.lock` sees the conflict.
//!
//! On Windows, `LockFileEx` is the only advisory-lock primitive and
//! Dart's `RandomAccessFile.lock` uses it — we mirror that here.
//!
//! Both flavours are *advisory* — a cooperating process must call
//! into a lock primitive to honour the lock; a malicious process
//! that ignores the lock and writes to the file directly is out of
//! scope (single-instance is a UX convenience, not a security gate).

use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::Write;
#[cfg(not(target_os = "windows"))]
use std::os::fd::AsRawFd;
#[cfg(target_os = "windows")]
use std::os::windows::io::AsRawHandle;
use std::sync::{Mutex, OnceLock};

/// Opaque handle the caller stores. The actual lock state lives in
/// the static registry below; the handle is just a counter the
/// registry indexes.
pub type HandleId = u64;

/// Per-handle owned state. Holding the `File` keeps the OS file
/// descriptor open; closing it is what releases the lock.
struct Entry {
    file: std::fs::File,
    path: String,
}

static REGISTRY: OnceLock<Mutex<HashMap<HandleId, Entry>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<HandleId>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<HandleId, Entry>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_id() -> HandleId {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock().expect("single_instance id mutex poisoned");
    let id = *g;
    *g = g.wrapping_add(1);
    id
}

/// Acquire an exclusive advisory lock on `path`. Creates the file
/// if it doesn't exist, truncates and writes the current PID for
/// diagnostics, then locks it. Returns the handle id on success;
/// returns `Err` with a human-readable reason on:
///
/// - parent directory missing
/// - file open denied (perms / read-only filesystem)
/// - lock contention (another process holds it — the
///   single-instance second-launch path)
/// - any other I/O error
///
/// Cooperative pattern: the caller treats `Err` as "another
/// instance is running" and exits. There is no retry — the OS
/// releases the lock on the first instance's process exit (even
/// on crash) so a stale lock file scenario is impossible.
pub fn acquire(path: &str) -> Result<HandleId, String> {
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)
        .map_err(|e| format!("open {path}: {e}"))?;

    try_lock_exclusive(&file).map_err(|e| format!("lock {path}: {e}"))?;

    // Best-effort PID for diagnostics. Failures are non-fatal — the
    // lock works whether the body wrote or not.
    let _ = writeln!(file, "{}", std::process::id());

    let id = next_id();
    let mut reg = registry()
        .lock()
        .expect("single_instance registry poisoned");
    reg.insert(
        id,
        Entry {
            file,
            path: path.to_string(),
        },
    );
    Ok(id)
}

/// Release the lock previously acquired under [`HandleId`]. Idempotent —
/// repeated releases of the same handle are silently ignored. The OS
/// would release the lock on process exit anyway; this is the
/// shutdown-hook path for the rare clean-shutdown case.
pub fn release(id: HandleId) {
    let mut reg = registry()
        .lock()
        .expect("single_instance registry poisoned");
    if let Some(entry) = reg.remove(&id) {
        // Dropping the file closes the fd, which releases `flock` /
        // `LockFileEx` atomically.
        drop(entry.file);
        // Best-effort unlink. Production callers expect the lock
        // file to disappear on clean shutdown — same contract the
        // Dart-era `RandomAccessFile.lock`-based guard offered.
        // Failures are non-fatal (file missing, perms changed).
        let _ = std::fs::remove_file(&entry.path);
    }
}

#[cfg(not(target_os = "windows"))]
fn try_lock_exclusive(file: &std::fs::File) -> Result<(), String> {
    // BSD-style whole-file advisory lock via `flock(2)`. Dart's
    // `RandomAccessFile.lock(FileLock.exclusive)` resolves to the
    // same syscall on POSIX, so cross-process contention works
    // both ways. `LOCK_NB` makes the call return immediately with
    // EWOULDBLOCK rather than blocking.
    const LOCK_EX: libc::c_int = 2;
    const LOCK_NB: libc::c_int = 4;
    // SAFETY: `flock` reads only the fd integer; no pointer args,
    // no aliasing. The fd outlives the call (file is borrowed for
    // `&self`).
    let rc = unsafe { libc::flock(file.as_raw_fd(), LOCK_EX | LOCK_NB) };
    if rc == 0 {
        Ok(())
    } else {
        let errno = std::io::Error::last_os_error();
        Err(errno.to_string())
    }
}

#[cfg(target_os = "windows")]
fn try_lock_exclusive(file: &std::fs::File) -> Result<(), String> {
    use std::ffi::c_void;
    use std::mem::zeroed;
    extern "system" {
        fn LockFileEx(
            hFile: *mut c_void,
            dwFlags: u32,
            dwReserved: u32,
            nNumberOfBytesToLockLow: u32,
            nNumberOfBytesToLockHigh: u32,
            lpOverlapped: *mut c_void,
        ) -> i32;
    }
    const LOCKFILE_EXCLUSIVE_LOCK: u32 = 0x00000002;
    const LOCKFILE_FAIL_IMMEDIATELY: u32 = 0x00000001;
    // OVERLAPPED struct — five fields, all zero for our purposes.
    // SAFETY: `OVERLAPPED` is a POD struct; zeroed is the correct
    // initialiser for "lock from offset 0".
    let mut overlapped: [u8; 32] = unsafe { zeroed() };
    let handle = file.as_raw_handle();
    // SAFETY: Win32 API call, single Win32 handle + scratch struct.
    let rc = unsafe {
        LockFileEx(
            handle as *mut c_void,
            LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
            0,
            u32::MAX,
            u32::MAX,
            overlapped.as_mut_ptr() as *mut c_void,
        )
    };
    if rc != 0 {
        Ok(())
    } else {
        let errno = std::io::Error::last_os_error();
        Err(errno.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_lock_path() -> String {
        let dir = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        dir.join(format!("lfs_si_test_{pid}_{nanos}.lock"))
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn acquire_returns_handle_and_release_is_idempotent() {
        let path = temp_lock_path();
        let id = acquire(&path).expect("first acquire");
        // Lock file exists and contains the PID.
        let pid = std::fs::read_to_string(&path).unwrap_or_default();
        assert!(!pid.trim().is_empty());
        release(id);
        // After release, the file is unlinked.
        assert!(!std::path::Path::new(&path).exists());
        // Idempotent — second release is a no-op.
        release(id);
    }

    #[test]
    fn second_acquire_against_held_lock_returns_err() {
        let path = temp_lock_path();
        let first = acquire(&path).expect("first acquire");
        let second = acquire(&path);
        assert!(second.is_err(), "expected lock contention, got {second:?}");
        release(first);
        // After the first releases, a fresh acquire should succeed.
        let third = acquire(&path).expect("third acquire after release");
        release(third);
    }

    #[test]
    fn release_with_unknown_handle_is_noop() {
        // Acquire and release a real handle so the registry is
        // initialised; then release a fictional handle.
        let path = temp_lock_path();
        let id = acquire(&path).expect("acquire");
        release(id);
        release(0xdead_beef_dead_beef);
    }
}
