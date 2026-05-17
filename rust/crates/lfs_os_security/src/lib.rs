#![warn(clippy::undocumented_unsafe_blocks)]

//! Process-hardening + memory-lock helpers.
//!
//! Per-OS FFI lives here (not in `lfs_core`) so the core stays
//! `unsafe_code = "forbid"`. This crate's public surface is a
//! small set of safe-to-call functions — `apply_startup_hardening`,
//! `lock_memory`, `unlock_memory`. The unsafe blocks are auditable
//! in one place.
//!
//! The single-instance file lock lives in `lib/core/single_instance/`
//! as pure Dart on top of `RandomAccessFile.lock`. Trap: routing it
//! through Rust forces the lock check to wait on `RustLib.init()`
//! before the splash can paint, which breaks the load-order goal
//! of "splash first, native blob second". `dart:io` calls the same
//! `flock` / `LockFileEx` syscalls, so Dart costs nothing extra
//! and keeps the splash on the fast path.
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
        // `proc_pidinfo` is a read-only kernel query that
        // populates the typed `proc_bsdinfo` struct exposed by
        // `libc`. We pass our own buffer + size; the kernel does
        // not retain the pointer past the call. Routing through
        // `proc_pidinfo(PROC_PIDTBSDINFO)` reads the typed
        // `pbi_flags` field straight off `proc_bsdinfo`, so the
        // binding mirrors the kernel ABI rather than depending on
        // a frozen byte offset.
        use std::mem;
        // `P_TRACED = 0x800` lives in `<sys/proc.h>` and is mirrored
        // into `pbi_flags` by the kernel's `fill_tbsdinfo()` shim.
        // libc does not export the constant, so we pin it locally.
        const P_TRACED: u32 = 0x0000_0800;
        // SAFETY: `getpid()` takes no arguments and returns the
        // current process's PID; no pointer aliasing.
        let pid = unsafe { libc::getpid() };
        // SAFETY: `proc_bsdinfo` is a plain-old-data POD layout
        // (`#[repr(C)]` struct of integer fields); all-zero is a
        // valid bit pattern and we immediately overwrite it via
        // the `proc_pidinfo` call below.
        let mut info: libc::proc_bsdinfo = unsafe { mem::zeroed() };
        let info_size = mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
        // SAFETY: `proc_pidinfo` writes up to `info_size` bytes
        // into the buffer pointed to by `&mut info`, which we own
        // on the stack and which is exactly that many bytes wide;
        // the kernel does not retain the pointer past the call.
        let rc = unsafe {
            libc::proc_pidinfo(
                pid,
                libc::PROC_PIDTBSDINFO,
                0,
                &mut info as *mut _ as *mut libc::c_void,
                info_size,
            )
        };
        // `proc_pidinfo` returns the number of bytes written; a
        // partial / failed read is best-treated as "can't tell, not
        // debugged" so we don't surface a false positive on a
        // healthy host.
        if rc != info_size {
            return false;
        }
        (info.pbi_flags & P_TRACED) != 0
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
    extern "C" {
        fn ptrace(
            request: libc::c_int,
            pid: libc::c_int,
            addr: *mut libc::c_void,
            data: libc::c_int,
        ) -> libc::c_int;
    }
    // SAFETY: ptrace with PT_DENY_ATTACH does not deref the
    // pointer arg (we pass a null pointer); the kernel reads the
    // request code and applies a process-level flag.
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

// OS-managed FIDO2 broker (Windows WebAuthn.dll, Apple
// AuthenticationServices, Android Credential Manager). Linux
// has no broker primitive — the module compiles to a no-op
// stub there and the dispatcher in `lfs_core::fido2::brokers`
// falls back to the direct HID transport.
pub mod fido2_broker;

// Cross-platform helpers used by per-OS modules. Lives outside
// any `cfg(target_os = "...")` gate so the unit tests inside it
// run in `rust-ci` (which only fires `cargo test` on Linux);
// helpers gated to a single OS would never see test execution
// because `rust-cross-check` is compile-validation only.
pub mod hardware_tier_vault;
pub mod installer_launch;
pub mod path;
pub mod secure_clipboard;
pub mod secure_key_storage;
pub mod session_lock_listener;
pub(crate) mod subprocess_util;
// Single helper exposed to `lfs_frb` for walking up from
// `Platform.resolvedExecutable` to the `.app` bundle root —
// path math the FRB shim runs before delegating into
// `macos::code_signing` / `macos::installer`. Re-exported
// without opening the whole `subprocess_util` module.
pub use subprocess_util::bundle_root_from_macos_executable;
// Cross-platform shape (`-1` outside Windows); real FFI behind
// a target_os gate inside the module.
pub mod winbio;

// PKCS#11 (Cryptoki) driver — smart-card / hardware-token signing
// for JaCarta / Рутокен / eToken / OpenPGP card / YubiKey PIV /
// EU eID / Thales Luna / AWS CloudHSM. Desktop-only (Linux + macOS
// + Windows); mobile cfg compiles to a stub that exposes the
// "unsupported" error so the FRB shim can pass the failure through
// without a separate cfg-gate on every call site. RFC 7512 URI
// parser is cross-target because the import-flow's saved-URI rebind
// path is shared regardless of whether the host can actually load
// the library.
pub mod pkcs11;

// Apple Secure Enclave SSH driver — ECDSA P-256 keypair generation
// + signing on macOS / iOS. Private bytes never leave the chip;
// every sign routes through `SecKeyCreateSignature` and the
// system biometric / passcode prompt fires at the OS layer per
// the access-control flags chosen at create time. Cfg-gated to
// Apple targets — the module body relies on `security-framework-sys`
// + `core-foundation` symbols that only exist on Darwin.
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub mod apple_se_ssh;

// Android-only — direct JNI to platform Java APIs
// (`java.security.KeyStore`, `androidx.biometric.BiometricPrompt`).
// See `android::keystore` status block for the verification gate.
#[cfg(target_os = "android")]
pub mod android;

// Windows-only — direct CNG / NCrypt bindings via `windows-rs`.
// Hosts `windows::hardware_vault` (the Tier 4 native CNG port that
// retires the C++ MethodChannel plugin in `windows/runner/`).
#[cfg(target_os = "windows")]
pub mod windows;

// Linux-only — TSS2 ESAPI bindings under `linux::tpm` /
// `linux::tpm_native`. Moved here from `lfs_core` so the audit
// invariant "lfs_os_security is the single OS-FFI perimeter"
// holds end-to-end across every supported platform.
#[cfg(target_os = "linux")]
pub mod linux;

// macOS-only — self-sign / re-sign code-signing pipeline that
// turns a freshly-installed `.app` into one with a stable
// signing identity in the user's keychain. Subprocess-driven
// over `/usr/bin/openssl` + `/usr/bin/security` +
// `/usr/bin/codesign`.
#[cfg(target_os = "macos")]
pub mod macos;
