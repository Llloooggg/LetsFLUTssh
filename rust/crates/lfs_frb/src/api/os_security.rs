//! FRB adapter for `lfs_os_security`. Process hardening +
//! page-lock helpers. The unsafe FFI lives in
//! `lfs_os_security::*`; this shim only marshals.

/// Per-step result reported by [`os_security_apply_startup_hardening`].
/// `code` carries the underlying syscall return code (0 = POSIX
/// success). `error` is `None` on success.
#[derive(Debug, Clone)]
pub struct DbHardeningStep {
    pub label: String,
    pub code: i64,
    pub error: Option<String>,
}

/// Apply whatever startup hardening the current platform supports.
/// Idempotent — re-running a process where hardening already
/// landed is a no-op. Returns the per-step outcomes for the
/// caller to log.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_apply_startup_hardening() -> Vec<DbHardeningStep> {
    lfs_os_security::apply_startup_hardening()
        .into_iter()
        .map(|s| {
            let (code, error) = match s.outcome {
                Ok(c) => (c, None),
                Err(e) => (0, Some(e)),
            };
            DbHardeningStep {
                label: s.label,
                code,
                error,
            }
        })
        .collect()
}

/// Page-lock `len` bytes at `addr`. Returns `true` on success.
/// `addr` is the integer address of a Dart-side native buffer
/// (e.g. `Pointer.address`); the kernel reads the address-range
/// descriptor and never derefs into Dart heap.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_lock_memory(addr: usize, len: usize) -> bool {
    lfs_os_security::lock_memory(addr, len)
}

/// Reverse of [`os_security_lock_memory`]. Errors swallowed —
/// best-effort cleanup.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_unlock_memory(addr: usize, len: usize) {
    lfs_os_security::unlock_memory(addr, len);
}

/// Acquire an exclusive advisory file lock for the
/// single-instance guard. Creates `path` if missing, writes the
/// current PID for diagnostics, and returns an opaque handle id
/// the caller passes back to [`os_security_release_single_instance`].
///
/// Returns the handle wrapped in `Result` — the `Err` arm carries
/// a human-readable reason: lock contention (another instance is
/// running), file open denied, parent directory missing, etc.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_acquire_single_instance(path: String) -> Result<u64, String> {
    lfs_os_security::single_instance::acquire(&path)
}

/// Release the lock for [`HandleId`]. Idempotent.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_release_single_instance(handle_id: u64) {
    lfs_os_security::single_instance::release(handle_id);
}

/// Set `NSURLIsExcludedFromBackupKey = true` on the directory at
/// `path` so iCloud Backup / iTunes / Time Machine skip it.
/// No-op on Linux / Windows / Android. Returns the underlying
/// Foundation error string when the call fails on Apple.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_exclude_from_backup(path: String) -> Result<(), String> {
    lfs_os_security::backup_exclusion::exclude_from_backup(&path)
}
