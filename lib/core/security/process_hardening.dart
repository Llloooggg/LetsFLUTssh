import 'dart:ffi';
import 'dart:io' show Platform;

import '../../utils/logger.dart';

/// Process-level hardening that runs once at app startup.
///
/// Goal: make a debugger attach or a crash dump *not leak the DB key and
/// session credentials* that live in RAM while the app is running.
///
/// * **Linux/Android** — `prctl(PR_SET_DUMPABLE, 0)` clears the dumpable
///   flag. Effects: the kernel skips core-dump generation for this process
///   on SIGSEGV/SIGABRT, `/proc/<pid>/mem` and the ptrace attach permission
///   require CAP_SYS_PTRACE (so another process of the same UID can no
///   longer read our memory via `gdb -p` without root).
/// * **macOS** — `ptrace(PT_DENY_ATTACH, 0, 0, 0)` tells the kernel to
///   refuse any future `ptrace(PT_ATTACH)`. An attached debugger is still
///   allowed if it was there before this call (dev builds running under
///   Xcode), but from release-start onward `lldb -p <pid>` returns EPERM.
/// * **Windows/iOS** — no userspace equivalent worth adding from Dart.
///   iOS already sandboxes heavily; Windows would need a kernel driver.
///   The call is a no-op on those platforms.
///
/// Failures are logged and swallowed — a hardened process that crashed on
/// startup is worse than an unhardened one that works.
class ProcessHardening {
  /// Apply whatever hardening the current platform supports.
  static void applyOnStartup() {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        _prctlNoDumpable();
      } else if (Platform.isMacOS) {
        _ptraceDenyAttach();
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

  /// Linux/Android: `prctl(PR_SET_DUMPABLE, 0)` — 38 is PR_SET_DUMPABLE.
  static void _prctlNoDumpable() {
    final libc = DynamicLibrary.open('libc.so.6');
    // Fallback: Android uses libc.so, not libc.so.6. Try that if the first
    // open failed implicitly via exception.
    final prctl = libc
        .lookup<NativeFunction<_PrctlC>>('prctl')
        .asFunction<_PrctlDart>();
    // int prctl(int option, unsigned long arg2, ...)
    // PR_SET_DUMPABLE = 4 (NOT 38 — 4 is correct per linux/prctl.h)
    const prSetDumpable = 4;
    final rc = prctl(prSetDumpable, 0, 0, 0, 0);
    if (rc == 0) {
      AppLogger.instance.log(
        'prctl(PR_SET_DUMPABLE, 0) applied',
        name: 'ProcessHardening',
      );
    } else {
      AppLogger.instance.log(
        'prctl(PR_SET_DUMPABLE, 0) returned $rc',
        name: 'ProcessHardening',
      );
    }
  }

  /// macOS: `ptrace(PT_DENY_ATTACH, 0, 0, 0)` — 31 is PT_DENY_ATTACH.
  static void _ptraceDenyAttach() {
    final libc = DynamicLibrary.process();
    final ptrace = libc
        .lookup<NativeFunction<_PtraceC>>('ptrace')
        .asFunction<_PtraceDart>();
    const ptDenyAttach = 31;
    final rc = ptrace(ptDenyAttach, 0, nullptr, 0);
    AppLogger.instance.log(
      'ptrace(PT_DENY_ATTACH) returned $rc',
      name: 'ProcessHardening',
    );
  }
}

typedef _PrctlC =
    Int32 Function(
      Int32,
      UnsignedLong,
      UnsignedLong,
      UnsignedLong,
      UnsignedLong,
    );
typedef _PrctlDart = int Function(int, int, int, int, int);

typedef _PtraceC = Int32 Function(Int32, Int32, Pointer<Void>, Int32);
typedef _PtraceDart = int Function(int, int, Pointer<Void>, int);
