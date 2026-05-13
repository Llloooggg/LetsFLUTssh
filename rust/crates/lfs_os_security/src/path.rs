//! Filesystem-perm hardening that needs OS-API or subprocess
//! invocation. Lives in `lfs_os_security` (not `lfs_core::path`)
//! because the crate is the single audit perimeter for OS-API FFI
//! and subprocess spawning; the icacls shell-out used to harden
//! files on Windows otherwise leaks a `std::process::Command`
//! call into `lfs_core`, which we keep free of subprocess
//! invocations.
//!
//! The Unix arm of file-perm hardening (`std::fs::set_permissions`
//! with `Permissions::from_mode(0o600)`) stays in `lfs_core::path`
//! because it is a single libc `chmod(2)` syscall — no subprocess,
//! no FFI surface beyond what `std::fs` already exposes — and the
//! audit-perimeter rule only governs OS-API FFI and subprocess
//! spawning.

#[cfg(target_os = "windows")]
use std::path::Path;

/// Tighten [`path`]'s on-disk ACL to owner-only via
/// `icacls <path> /inheritance:r /grant:r <USER>:(F)`. Removes
/// inherited ACLs and grants the current user full control. No-op
/// when the `USERNAME` env var is empty (CI / service-account
/// contexts that do not carry the variable).
///
/// Same syscalls icacls itself wraps, no extra crate surface to
/// audit. Best-effort hardening — failure is reported but never
/// aborts the surrounding write.
///
/// Sync because the lfs_core callers (`write_bytes_atomic`,
/// DB / recorder / logger / sidecar file-flush paths) are sync
/// today; routing through an async helper would force `.await`
/// up through every artefact-writing call site without a runtime
/// benefit (the icacls child exits in milliseconds and the
/// callers are already off the Dart event loop on `spawn_blocking`).
#[cfg(target_os = "windows")]
pub fn harden_file_perms_windows(path: &Path) -> Result<(), String> {
    let user = std::env::var("USERNAME").unwrap_or_default();
    if user.is_empty() {
        return Ok(());
    }
    let status = std::process::Command::new("icacls")
        .arg(path)
        .arg("/inheritance:r")
        .arg("/grant:r")
        .arg(format!("{user}:(F)"))
        .status()
        .map_err(|e| format!("spawn icacls: {e}"))?;
    if !status.success() {
        return Err(format!(
            "icacls {} exited with {:?}",
            path.display(),
            status.code()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    // The Windows arm spawns `icacls`, which would (a) only run on
    // a real Windows host and (b) actually mutate the on-disk ACL
    // of the test file. We do NOT want either in CI — a unit test
    // that touches `icacls` on a WSL host with Windows interop
    // enabled would alter the host filesystem. The clippy-cross CI
    // matrix is the regression guard for the cfg arm compiling;
    // the runtime path is exercised end-to-end on real Windows
    // hosts in manual / release-build smoke tests.
    //
    // The only branch testable without spawning is the early
    // return when `USERNAME` is empty, but pinning that branch
    // requires mutating process-global env state (racy across
    // parallel tests) for one assertion of a no-op return — not
    // worth the test-isolation cost. Left intentionally without
    // a no-spawn pin.
    #[cfg(target_os = "windows")]
    #[test]
    fn windows_arm_compiles() {
        // Reference the symbol so a rename / signature change
        // fails the build rather than silently de-linking. Does
        // not spawn — the function pointer is taken, never called.
        let _f: fn(&std::path::Path) -> Result<(), String> = super::harden_file_perms_windows;
    }
}
