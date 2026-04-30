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
