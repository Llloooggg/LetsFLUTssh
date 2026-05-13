//! Filesystem helpers that need OS-API or subprocess invocation.
//! Lives in `lfs_os_security` (not `lfs_core::path` /
//! `lfs_core::fs::local`) because the crate is the single audit
//! perimeter for OS-API FFI and subprocess spawning; the icacls
//! shell-out used to harden files on Windows and the `cmd /c
//! attrib *` shell-out used to enumerate H/S-attributed names
//! would otherwise leak `std::process::Command` /
//! `tokio::process::Command` calls into `lfs_core`, which we keep
//! free of subprocess invocations.
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

/// Enumerate Hidden (H) / System (S) attributed entries under
/// [`dir`] by shelling out to `cmd /c attrib *` and returning the
/// raw stdout as a lossily-decoded `String`. Empty `String` on
/// spawn failure or non-zero exit. The pure parser lives in
/// `lfs_core::path::parse_windows_attrib_output`; this helper
/// owns only the subprocess invocation so the lfs_core caller
/// stays free of `tokio::process::Command`.
///
/// `CREATE_NO_WINDOW = 0x08000000` (Win32 process-creation flag) is
/// load-bearing: without it, every `cmd.exe` spawn flashes a
/// console window for the duration of `attrib`. The file browser
/// fires this on every directory listing, so a directory-heavy
/// session showed dozens of black-window blinks. The flag tells
/// CreateProcessW to skip console allocation; the spawned process
/// still has a stdout pipe (we read it) — only the visible
/// console window is suppressed. Documented at
/// https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags.
///
/// Async because the lfs_core caller (`fs::local::windows_hidden_names`)
/// is awaited from the FRB worker pool on every directory listing;
/// blocking the worker on a synchronous wait would stall the UI
/// thread waiting for the FRB response. `tokio::process::Command`
/// integrates with the same runtime the rest of the FRB API uses.
#[cfg(target_os = "windows")]
pub async fn windows_hidden_names_raw(dir: String) -> String {
    // `tokio::process::Command::creation_flags` is provided as an
    // inherent method under `cfg_windows!`, not via the std
    // `CommandExt` trait — no extra `use` needed.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let output = tokio::process::Command::new("cmd")
        .args(["/c", "attrib", "*"])
        .current_dir(&dir)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .await;
    let Ok(output) = output else {
        return String::new();
    };
    if !output.status.success() {
        return String::new();
    }
    // attrib emits OEM-codepage bytes on Windows. We accept some
    // mojibake on non-ASCII filenames here — the H/S filter only
    // needs to match the lowercase basename, which is ASCII for
    // 99% of dotfiles / system files. Worth revisiting if a real
    // user trips over a Cyrillic system file.
    String::from_utf8_lossy(&output.stdout).into_owned()
}

#[cfg(test)]
mod tests {
    // The Windows arm spawns `icacls` / `cmd /c attrib *`, which
    // would (a) only run on a real Windows host and (b) actually
    // mutate (icacls) the on-disk ACL of the test file. We do NOT
    // want either in CI — a unit test that touches `icacls` on a
    // WSL host with Windows interop enabled would alter the host
    // filesystem; a unit test that runs `cmd /c attrib *` would
    // depend on whatever happens to live in the test working dir.
    // The clippy-cross CI matrix is the regression guard for the
    // cfg arm compiling; the runtime path is exercised end-to-end
    // on real Windows hosts in manual / release-build smoke tests.
    //
    // The only branch testable without spawning is the
    // `harden_file_perms_windows` early return when `USERNAME` is
    // empty, but pinning that branch requires mutating
    // process-global env state (racy across parallel tests) for
    // one assertion of a no-op return — not worth the
    // test-isolation cost. Left intentionally without a no-spawn
    // pin.
    #[cfg(target_os = "windows")]
    #[test]
    fn windows_arm_compiles() {
        // Reference the symbols so a rename / signature change
        // fails the build rather than silently de-linking. Does
        // not spawn — the symbols are bound to `_` items, never
        // called.
        let _f: fn(&std::path::Path) -> Result<(), String> = super::harden_file_perms_windows;
        let _g = super::windows_hidden_names_raw;
    }
}
