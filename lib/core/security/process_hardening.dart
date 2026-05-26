import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';

/// Process-level hardening that runs once at app startup.
///
/// Goal: make a debugger attach or a crash dump *not leak the DB key
/// and session credentials* that live in RAM while the app is
/// running.
///
/// Routes through `lfs_os_security::apply_startup_hardening` (FRB
/// sync). The unsafe FFI lives in the `lfs_os_security` crate so
/// `lfs_core` keeps `unsafe_code = "forbid"`.
///
/// Per-OS effects:
/// * **Linux / Android** — `prctl(PR_SET_DUMPABLE, 0)` clears the
///   dumpable flag (kernel skips core dumps on SIGSEGV/SIGABRT;
///   `/proc/<pid>/mem` and ptrace attach require CAP_SYS_PTRACE).
///   `setrlimit(RLIMIT_CORE, {0, 0})` belt-and-braces.
/// * **macOS** — `ptrace(PT_DENY_ATTACH, 0, 0, 0)` refuses any
///   future `ptrace(PT_ATTACH)`. `setrlimit(RLIMIT_CORE, {0, 0})`
///   blocks `/cores/<pid>.core` writes on SIGSEGV.
/// * **Windows** — `SetErrorMode(SEM_FAILCRITICALERRORS |
///   SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)` suppresses
///   the "stopped working" dialog and tells WER not to capture a
///   crash dump.
/// * **iOS** — no userspace equivalent worth applying.
///
/// Failures are logged and swallowed — a hardened process that
/// crashed at startup is worse than an unhardened one that works.
class ProcessHardening {
  /// Apply whatever hardening the current platform supports.
  static void applyOnStartup() {
    try {
      final steps = rust_os.osSecurityApplyStartupHardening();
      for (final step in steps) {
        final code = step.code.toInt();
        final err = step.error;
        if (err != null) {
          AppLogger.instance.log(
            '${step.label} failed: $err',
            name: 'ProcessHardening',
            level: LogLevel.warn,
          );
        } else {
          AppLogger.instance.log(
            '${step.label} returned $code',
            name: 'ProcessHardening',
          );
        }
      }
    } catch (e) {
      // Defensive: never let hardening break app startup.
      AppLogger.instance.log(
        'Process hardening error: $e',
        name: 'ProcessHardening',
        error: e,
      );
    }
  }

  /// Read the *current* tracer state. `true` when a debugger is
  /// attached to this process right now. Pure runtime probe —
  /// distinct from [applyOnStartup], which BLOCKS new attaches.
  ///
  /// Routes through `lfs_os_security::is_being_debugged` (FRB sync).
  /// Linux / Android read `/proc/self/status` → `TracerPid`, macOS
  /// reads `sysctl KERN_PROC_PID` → `P_TRACED`, Windows calls
  /// `IsDebuggerPresent`. iOS short-circuits to `false` — sandbox
  /// blocks `ptrace`-style probes from store-signed apps.
  ///
  /// Fail-safe: any I/O / FRB error returns `false`. An unreadable
  /// `/proc` is not the same as "definitely no debugger", but
  /// asserting `true` on a probe error would brick legitimate
  /// startup on hosts with hardened `/proc` ACLs.
  ///
  /// Canonical wiring: the security stack consults this on every
  /// biometric unlock attempt and skips the OS-stored-password
  /// shortcut on a positive probe — see
  /// [`SecurityInitController._unlockKeychainWithPassword`] and
  /// [`SecurityInitController._unlockHardware`]. The user falls
  /// through to the typed-secret form, so a debugger watching the
  /// process cannot scoop the master password / PIN out of an
  /// auto-released keychain slot.
  static bool isBeingDebugged() {
    try {
      return rust_os.osSecurityIsBeingDebugged();
    } catch (e) {
      // FRB unreachable (flutter_test pre-init) → fail-safe false.
      // The probe is best-effort; missing it costs UX (one extra
      // password entry) only in attack conditions, never blocks
      // a legitimate user.
      AppLogger.instance.log(
        'is_being_debugged probe FRB unreachable: $e',
        name: 'ProcessHardening',
        level: LogLevel.warn,
      );
      return false;
    }
  }
}
