//! Filesystem helpers that need OS-API or subprocess invocation.
//! Lives in `lfs_os_security` (not `lfs_core::path` /
//! `lfs_core::fs::local`) because the crate is the single audit
//! perimeter for OS-API FFI and subprocess spawning; the Win32
//! ACL hardening that locks files to owner-only on Windows and the
//! `cmd /c attrib *` shell-out that enumerates H/S-attributed names
//! would otherwise leak `windows`-crate security calls /
//! `tokio::process::Command` into `lfs_core`, which we keep free of
//! both OS-API FFI and subprocess invocations.
//!
//! The Unix arm of file-perm hardening (`std::fs::set_permissions`
//! with `Permissions::from_mode(0o600)`) stays in `lfs_core::path`
//! because it is a single libc `chmod(2)` syscall — no subprocess,
//! no FFI surface beyond what `std::fs` already exposes — and the
//! audit-perimeter rule only governs OS-API FFI and subprocess
//! spawning.

#[cfg(target_os = "windows")]
use std::path::Path;

/// Tighten [`path`]'s on-disk ACL to owner-only: a single explicit
/// ACE granting the current process's token user full control, with
/// inheritance disabled so the inherited `%LOCALAPPDATA%` ACEs
/// (SYSTEM / Administrators) are dropped. Net effect equals
/// `icacls <path> /inheritance:r /grant:r <user>:(F)`.
///
/// Implemented with the Win32 security APIs (`OpenProcessToken` →
/// `GetTokenInformation(TokenUser)` → `SetEntriesInAclW` →
/// `SetNamedSecurityInfoW`) rather than shelling out to `icacls`.
/// The shell-out spawned a console process per call, which on a
/// Windows 11 host whose default terminal is Windows Terminal
/// flashed a transparent terminal window; the startup write paths
/// (logger, recorder, archive apply, sidecar) call this several
/// times, so the user saw a cascade of them on launch. The native
/// API has no subprocess, no console, and no dependency on
/// `icacls.exe` being on `PATH`.
///
/// The SID comes from the process token, not the `USERNAME` env var,
/// so it works in service-account / env-stripped contexts the old
/// shell-out treated as a no-op.
///
/// Best-effort hardening — failure is reported but never aborts the
/// surrounding write. Sync because every lfs_core caller
/// (`write_bytes_atomic`, DB / recorder / logger / sidecar flush)
/// is sync and these calls are pure userspace + a few syscalls.
#[cfg(target_os = "windows")]
pub fn harden_file_perms_windows(path: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt as _;
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{
        CloseHandle, LocalFree, ERROR_SUCCESS, GENERIC_ALL, HANDLE, HLOCAL,
    };
    use windows::Win32::Security::Authorization::{
        BuildTrusteeWithSidW, SetEntriesInAclW, SetNamedSecurityInfoW, EXPLICIT_ACCESS_W,
        SET_ACCESS, SE_FILE_OBJECT, TRUSTEE_W,
    };
    use windows::Win32::Security::{
        GetTokenInformation, TokenUser, ACL, DACL_SECURITY_INFORMATION, NO_INHERITANCE,
        PROTECTED_DACL_SECURITY_INFORMATION, TOKEN_QUERY, TOKEN_USER,
    };
    use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    let wide: Vec<u16> = path
        .as_os_str()
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();

    // SAFETY: every Win32 call's result is checked; `buf` stays alive
    // until after `SetEntriesInAclW` copies the SID into its own ACL;
    // the ACL that call allocates is released with `LocalFree` on both
    // exit paths. The DACL grants only the running process's own token
    // user, so the caller never locks itself out of its own file.
    unsafe {
        let mut token = HANDLE::default();
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token)
            .map_err(|e| format!("OpenProcessToken: {e}"))?;

        // Size probe (returns ERROR_INSUFFICIENT_BUFFER), then fetch.
        let mut len = 0u32;
        let _ = GetTokenInformation(token, TokenUser, None, 0, &mut len);
        let mut buf = vec![0u8; len as usize];
        let info = GetTokenInformation(
            token,
            TokenUser,
            Some(buf.as_mut_ptr().cast()),
            len,
            &mut len,
        );
        let _ = CloseHandle(token);
        info.map_err(|e| format!("GetTokenInformation: {e}"))?;
        // `buf` is `Vec<u8>` (1-byte align); read the SID pointer out
        // of the TOKEN_USER without forming an unaligned reference.
        let sid =
            std::ptr::addr_of!((*buf.as_ptr().cast::<TOKEN_USER>()).User.Sid).read_unaligned();

        let mut trustee = TRUSTEE_W::default();
        BuildTrusteeWithSidW(&mut trustee, Some(sid));
        let ea = EXPLICIT_ACCESS_W {
            grfAccessPermissions: GENERIC_ALL.0,
            grfAccessMode: SET_ACCESS,
            grfInheritance: NO_INHERITANCE,
            Trustee: trustee,
        };

        let mut acl: *mut ACL = std::ptr::null_mut();
        let err = SetEntriesInAclW(Some(&[ea]), None, &mut acl);
        if err != ERROR_SUCCESS {
            return Err(format!("SetEntriesInAclW: {err:?}"));
        }

        let err = SetNamedSecurityInfoW(
            PCWSTR(wide.as_ptr()),
            SE_FILE_OBJECT,
            DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
            None,
            None,
            Some(acl as *const ACL),
            None,
        );
        let _ = LocalFree(Some(HLOCAL(acl.cast())));
        if err != ERROR_SUCCESS {
            return Err(format!("SetNamedSecurityInfoW: {err:?}"));
        }
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
    // The Windows arm mutates the on-disk ACL (`harden_file_perms_
    // windows`) or runs `cmd /c attrib *` (`windows_hidden_names_raw`),
    // which would (a) only run on a real Windows host and (b) touch
    // host state: a unit test for the hardening would re-ACL the test
    // file (and on a WSL host with Windows interop enabled, the real
    // filesystem); the attrib test would depend on the test working
    // dir. We want neither in CI. The clippy-cross matrix guards the
    // cfg arm compiling; the runtime path is exercised end-to-end on
    // real Windows hosts in manual / release-build smoke tests.
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
