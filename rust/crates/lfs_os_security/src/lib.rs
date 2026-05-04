//! Process-hardening + memory-lock helpers.
//!
//! Per-OS FFI lives here (not in `lfs_core`) so the core stays
//! `unsafe_code = "forbid"`. This crate's public surface is a
//! small set of safe-to-call functions — `apply_startup_hardening`,
//! `lock_memory`, `unlock_memory`. The unsafe blocks are auditable
//! in one place.
//!
//! The single-instance file lock used to live here as a sibling
//! module; it now lives in `lib/core/single_instance/` as pure
//! Dart on top of `RandomAccessFile.lock`. The Rust route forced
//! the lock check to wait on `RustLib.init()` (~3 s on Windows
//! IoT), which conflicted with painting the splash before the
//! native blob load. `dart:io` calls the same `flock` /
//! `LockFileEx` syscalls the Rust module did, so going back to
//! Dart costs nothing and removes the load-order dependency.
//!
//! ## Hardening goals
//!
//! Make a debugger attach or a crash dump *not leak the DB key
//! and session credentials* that live in RAM while the app is
//! running.
//!
//! - **Linux / Android** — `prctl(PR_SET_DUMPABLE, 0)` clears the
//!   dumpable flag (kernel skips core dumps on SIGSEGV/SIGABRT;
//!   `/proc/<pid>/mem` and ptrace attach require CAP_SYS_PTRACE).
//!   `setrlimit(RLIMIT_CORE, {0, 0})` belt-and-braces against
//!   accidental dumps.
//! - **macOS** — `ptrace(PT_DENY_ATTACH, 0, 0, 0)` refuses any
//!   future `ptrace(PT_ATTACH)`. `setrlimit(RLIMIT_CORE, {0, 0})`
//!   blocks `/cores/<pid>.core` writes on SIGSEGV when
//!   `ulimit -c` is non-zero.
//! - **Windows** — `SetErrorMode(SEM_FAILCRITICALERRORS |
//!   SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)` suppresses
//!   the "stopped working" dialog and tells WER not to capture a
//!   crash dump.
//! - **iOS** — no userspace equivalent worth applying. iOS already
//!   sandboxes heavily.
//!
//! Failures are reported per step but never panic — a hardened
//! process that crashed at startup is worse than an unhardened
//! one that works.

/// Outcome of a single hardening step. Returned as a `Vec<Step>`
/// so the caller can log every per-step result with the same
/// shape it used pre-migration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HardeningStep {
    /// Human-readable label, e.g. `"prctl(PR_SET_DUMPABLE, 0)"`.
    pub label: String,
    /// `Ok` carries an integer return code (0 = success on POSIX,
    /// non-zero on Windows for previous mode); `Err` carries the
    /// error message.
    pub outcome: Result<i64, String>,
}

/// Apply whatever startup hardening the current platform supports.
/// Idempotent — re-running on a process where hardening already
/// landed is a no-op (the kernel-side flags don't reset). Returns
/// the per-step outcomes for the caller to log.
pub fn apply_startup_hardening() -> Vec<HardeningStep> {
    let mut steps = Vec::new();

    #[cfg(any(target_os = "linux", target_os = "android"))]
    {
        steps.push(prctl_no_dumpable());
        steps.push(setrlimit_core_zero());
    }

    #[cfg(target_os = "macos")]
    {
        steps.push(ptrace_deny_attach());
        steps.push(setrlimit_core_zero());
    }

    #[cfg(target_os = "windows")]
    {
        steps.push(set_error_mode());
    }

    // iOS: nothing to add.
    #[cfg(target_os = "ios")]
    {
        let _ = &mut steps;
    }

    steps
}

/// Detect whether a debugger is currently attached to the
/// process. Best-effort runtime probe — orthogonal to the
/// startup-time `apply_startup_hardening` (which BLOCKS new
/// attaches), this answers "is something already attached
/// right now?".
///
/// Per-platform probe:
/// - **Linux / Android** — parse `/proc/self/status` for the
///   `TracerPid:` line. Non-zero TracerPid means `ptrace(PT_ATTACH)`
///   succeeded against us (despite `PR_SET_PTRACER, 0`, which
///   only restricts NEW attaches — a parent debugger or
///   `setcap cap_sys_ptrace+ep` binary still gets through).
/// - **macOS** — `sysctl({CTL_KERN, KERN_PROC, KERN_PROC_PID,
///   getpid()})` returns `kinfo_proc` with `kp_proc.p_flag &
///   P_TRACED`. The Apple-recommended runtime detection;
///   `ptrace(PT_DENY_ATTACH)` BLOCKS attach, this READS the
///   current state.
/// - **Windows** — `IsDebuggerPresent()` (kernel32.dll). Standard
///   Win32 anti-debug primitive.
/// - **iOS** — same `sysctl` shape as macOS. Apple gates app-
///   store apps from `ptrace`; this detection still catches
///   Xcode debugger attached to a development build.
///
/// **Caveats** (well-known to anti-debug practitioners):
/// - Casual `gdb` / `lldb` attach is detected; sophisticated
///   attackers replace `/proc/self/status` reads via `LD_PRELOAD`
///   or hook `IsDebuggerPresent` in-place.
/// - This is one signal of many; pair with timing-anomaly
///   checks for higher confidence (not implemented here —
///   timing checks have false-positive rates that hurt
///   battery-throttled mobile devices).
/// - NEVER auto-terminate from this signal. Call sites should
///   surface to telemetry and let policy decide (e.g. lock
///   sensitive tiers immediately, require fresh unlock).
pub fn is_being_debugged() -> bool {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    {
        let status = match std::fs::read_to_string("/proc/self/status") {
            Ok(s) => s,
            // /proc unreadable → can't tell. Assume worst-case
            // false rather than asserting we're clean.
            Err(_) => return false,
        };
        for line in status.lines() {
            if let Some(rest) = line.strip_prefix("TracerPid:") {
                let pid: i32 = rest.trim().parse().unwrap_or(0);
                return pid != 0;
            }
        }
        false
    }

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        // SAFETY: `sysctl` is a read-only kernel query; the
        // returned `kinfo_proc` is a fixed-size struct stamped
        // by the kernel. We pass our own buffer + length pair;
        // the kernel does not retain the pointer.
        use std::mem;
        const CTL_KERN: libc::c_int = 1;
        const KERN_PROC: libc::c_int = 14;
        const KERN_PROC_PID: libc::c_int = 1;
        const P_TRACED: i32 = 0x800;
        // `kinfo_proc` is large + Apple-private; we only need
        // the `p_flag` field's offset within `kp_proc.p_flag`.
        // The struct layout is stable (Apple ABI); the offset
        // for p_flag inside kinfo_proc is 32 bytes on every
        // 64-bit Darwin since 10.4. Hard-code the offset rather
        // than depend on bindgen.
        let mut info = [0u8; 648]; // sizeof(kinfo_proc) on darwin64
        let mut size: libc::size_t = info.len();
        let mib: [libc::c_int; 4] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, unsafe {
            libc::getpid()
        }];
        let rc = unsafe {
            libc::sysctl(
                mib.as_ptr() as *mut libc::c_int,
                mib.len() as libc::c_uint,
                info.as_mut_ptr() as *mut libc::c_void,
                &mut size,
                std::ptr::null_mut(),
                0,
            )
        };
        if rc != 0 {
            return false;
        }
        // p_flag is at offset 32 inside kinfo_proc.kp_proc on
        // 64-bit darwin; read as i32 little-endian.
        if size < 36 {
            return false;
        }
        let bytes: [u8; 4] = match info[32..36].try_into() {
            Ok(b) => b,
            Err(_) => return false,
        };
        let flags = i32::from_le_bytes(bytes);
        let _ = mem::size_of::<libc::c_int>();
        (flags & P_TRACED) != 0
    }

    #[cfg(target_os = "windows")]
    {
        extern "system" {
            fn IsDebuggerPresent() -> i32;
        }
        // SAFETY: Win32 query, no arguments, returns BOOL.
        unsafe { IsDebuggerPresent() != 0 }
    }
}

/// Page-lock `len` bytes at `addr` in RAM so the OS doesn't page
/// them out to swap or hibernation. Returns `true` on success.
/// `mlock` (POSIX) returns 0 on success; `VirtualLock` (Windows)
/// returns non-zero on success — both shapes normalised here.
///
/// Caller passes the address as `usize` (typically obtained from
/// a Dart `ffi.Pointer<...>.address`). The crate doesn't keep
/// any reference to the pointed-at memory.
pub fn lock_memory(addr: usize, len: usize) -> bool {
    if len == 0 {
        return false;
    }

    #[cfg(not(target_os = "windows"))]
    {
        // SAFETY: `mlock` reads the address-range descriptor only;
        // it does not deref the pointer. Caller owns `addr..addr+len`
        // for the duration of the lock.
        let rc = unsafe { libc::mlock(addr as *const libc::c_void, len) };
        rc == 0
    }

    #[cfg(target_os = "windows")]
    {
        // Win32 `VirtualLock(LPVOID, SIZE_T) -> BOOL` — non-zero
        // = success. Loaded via dynamic extern; no `windows-sys`
        // dep needed for two functions.
        extern "system" {
            fn VirtualLock(addr: *const std::ffi::c_void, size: usize) -> i32;
        }
        // SAFETY: Win32 API call, address-range descriptor only.
        let rc = unsafe { VirtualLock(addr as *const std::ffi::c_void, len) };
        rc != 0
    }
}

/// Reverse of [`lock_memory`]. Errors are swallowed — best-effort
/// cleanup; a process tearing down doesn't care if the unlock
/// fails.
pub fn unlock_memory(addr: usize, len: usize) {
    if len == 0 {
        return;
    }

    #[cfg(not(target_os = "windows"))]
    {
        // SAFETY: see `lock_memory`.
        let _ = unsafe { libc::munlock(addr as *const libc::c_void, len) };
    }

    #[cfg(target_os = "windows")]
    {
        extern "system" {
            fn VirtualUnlock(addr: *const std::ffi::c_void, size: usize) -> i32;
        }
        // SAFETY: see `lock_memory`.
        let _ = unsafe { VirtualUnlock(addr as *const std::ffi::c_void, len) };
    }
}

// ── Per-OS hardening steps ───────────────────────────────────────────

#[cfg(any(target_os = "linux", target_os = "android"))]
fn prctl_no_dumpable() -> HardeningStep {
    // PR_SET_DUMPABLE = 4 per linux/prctl.h.
    const PR_SET_DUMPABLE: libc::c_int = 4;
    // SAFETY: `prctl` with PR_SET_DUMPABLE is a process-flag flip
    // — no pointer args, fixed semantics, no aliasing.
    let rc = unsafe { libc::prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) };
    HardeningStep {
        label: "prctl(PR_SET_DUMPABLE, 0)".to_string(),
        outcome: Ok(rc as i64),
    }
}

#[cfg(target_os = "macos")]
fn ptrace_deny_attach() -> HardeningStep {
    // PT_DENY_ATTACH = 31 on Darwin (private; not in libc crate).
    const PT_DENY_ATTACH: libc::c_int = 31;
    // SAFETY: ptrace with PT_DENY_ATTACH does not deref pointer
    // args; the kernel reads the request code and applies a
    // process-level flag.
    extern "C" {
        fn ptrace(
            request: libc::c_int,
            pid: libc::c_int,
            addr: *mut libc::c_void,
            data: libc::c_int,
        ) -> libc::c_int;
    }
    let rc = unsafe { ptrace(PT_DENY_ATTACH, 0, std::ptr::null_mut(), 0) };
    HardeningStep {
        label: "ptrace(PT_DENY_ATTACH)".to_string(),
        outcome: Ok(rc as i64),
    }
}

#[cfg(any(target_os = "linux", target_os = "android", target_os = "macos",))]
fn setrlimit_core_zero() -> HardeningStep {
    // RLIMIT_CORE = 4 on both Linux and macOS (matches Dart-era
    // const).
    let rlim = libc::rlimit {
        rlim_cur: 0,
        rlim_max: 0,
    };
    // SAFETY: `setrlimit` reads the rlimit struct by reference;
    // we own it on the stack for the duration of the call.
    let rc = unsafe { libc::setrlimit(libc::RLIMIT_CORE, &rlim) };
    HardeningStep {
        label: "setrlimit(RLIMIT_CORE, {0, 0})".to_string(),
        outcome: Ok(rc as i64),
    }
}

#[cfg(target_os = "windows")]
fn set_error_mode() -> HardeningStep {
    extern "system" {
        fn SetErrorMode(uMode: u32) -> u32;
    }
    // Bit values from winbase.h:
    //   SEM_FAILCRITICALERRORS = 0x0001
    //   SEM_NOGPFAULTERRORBOX  = 0x0002
    //   SEM_NOOPENFILEERRORBOX = 0x8000
    const FLAGS: u32 = 0x0001 | 0x0002 | 0x8000;
    // SAFETY: Win32 API call, single integer argument.
    let prev = unsafe { SetErrorMode(FLAGS) };
    HardeningStep {
        label: format!("SetErrorMode({FLAGS})"),
        outcome: Ok(prev as i64),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_being_debugged_returns_without_panic() {
        // Real value depends on test runner — assertion-free,
        // we only verify the call returns at all.
        let _ = is_being_debugged();
    }

    #[test]
    fn apply_startup_hardening_returns_steps() {
        let steps = apply_startup_hardening();
        // At least one step on supported OSes; iOS returns an
        // empty Vec (test runs on a build host, not iOS).
        if cfg!(any(
            target_os = "linux",
            target_os = "android",
            target_os = "macos",
            target_os = "windows",
        )) {
            assert!(!steps.is_empty(), "expected at least one step");
            // No panics, every step has a label.
            for step in &steps {
                assert!(!step.label.is_empty());
            }
        }
    }

    #[test]
    fn lock_unlock_zero_len_is_noop() {
        assert!(!lock_memory(0xdead_beef, 0));
        unlock_memory(0xdead_beef, 0);
    }

    #[test]
    fn lock_unlock_real_buffer() {
        // Allocate a 4 KiB buffer (one page on most archs) on the
        // heap; lock + unlock against its address. Skipped on
        // hosts where mlock requires CAP_SYS_RESOURCE — failure
        // here is informational, not a test fail.
        let buf = vec![0u8; 4096];
        let addr = buf.as_ptr() as usize;
        let _locked = lock_memory(addr, buf.len());
        // Either outcome is acceptable — RLIMIT_MEMLOCK on CI may
        // be tight. Just verify unlock doesn't panic.
        unlock_memory(addr, buf.len());
    }
}

pub mod backup_exclusion;
pub mod biometric_auth;
pub mod hardware_tier_vault;
pub mod secure_clipboard;
pub mod secure_key_storage;
pub mod session_lock_listener;
// Cross-platform shape (`-1` outside Windows); real FFI behind
// a target_os gate inside the module.
pub mod winbio;

// Android-only — direct JNI to platform Java APIs
// (`java.security.KeyStore`, `androidx.biometric.BiometricPrompt`).
// See `android::keystore` status block for the verification gate.
#[cfg(target_os = "android")]
pub mod android;
