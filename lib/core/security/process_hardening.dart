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
}
