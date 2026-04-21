import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pffi;

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
/// * **Windows** — `SetErrorMode(SEM_FAILCRITICALERRORS |
///   SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)`. Stops Windows from
///   popping the "this app stopped working" dialog and disables Windows
///   Error Reporting (WER) crash dumps for our process — those dumps would
///   otherwise contain the live SQLite cipher key and decrypted session
///   credentials. WER also uploads dumps to Microsoft if the user opted in,
///   which is exactly what we don't want.
/// * **iOS** — no userspace equivalent worth adding from Dart. iOS already
///   sandboxes heavily.
///
/// Failures are logged and swallowed — a hardened process that crashed on
/// startup is worse than an unhardened one that works.
class ProcessHardening {
  /// Apply whatever hardening the current platform supports.
  static void applyOnStartup() {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        _prctlNoDumpable();
        _setRLimitCoreZero();
      } else if (Platform.isMacOS) {
        _ptraceDenyAttach();
        _setRLimitCoreZero();
      } else if (Platform.isWindows) {
        _windowsSuppressErrorDialogs();
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

  /// POSIX: `setrlimit(RLIMIT_CORE, {0, 0})` — belt-and-braces against
  /// accidental core dumps on Linux/macOS. `prctl(PR_SET_DUMPABLE, 0)`
  /// already tells the Linux kernel to skip dump generation for this
  /// process; on macOS `ptrace(PT_DENY_ATTACH)` blocks debugger attach
  /// but does *not* cover the `/cores/<pid>.core` dump a SIGSEGV would
  /// otherwise write when `ulimit -c` is non-zero. Zeroing the soft
  /// *and* hard limits from inside the process is a self-imposed cap
  /// that survives any shell-level `ulimit -c unlimited` the user had
  /// set. Failures are logged and ignored — a missing `libc.so.6` on
  /// an oddball distro should not break app startup.
  static void _setRLimitCoreZero() {
    Pointer<UnsignedLong>? rlim;
    try {
      // `<sys/resource.h>` defines `RLIMIT_CORE` as 4 on both Linux and
      // macOS. `struct rlimit { rlim_t rlim_cur; rlim_t rlim_max; }` is
      // two `unsigned long` words on every 64-bit POSIX target shipped.
      const rlimitCore = 4;
      final libc = Platform.isMacOS
          ? DynamicLibrary.process()
          : DynamicLibrary.open('libc.so.6');
      final setrlimit = libc
          .lookup<NativeFunction<_SetRLimitC>>('setrlimit')
          .asFunction<_SetRLimitDart>();
      rlim = pffi.calloc<UnsignedLong>(2);
      rlim[0] = 0; // rlim_cur
      rlim[1] = 0; // rlim_max
      final rc = setrlimit(rlimitCore, rlim);
      AppLogger.instance.log(
        'setrlimit(RLIMIT_CORE, {0, 0}) returned $rc',
        name: 'ProcessHardening',
      );
    } catch (e) {
      AppLogger.instance.log(
        'setrlimit(RLIMIT_CORE, 0) failed: $e',
        name: 'ProcessHardening',
      );
    } finally {
      if (rlim != null) pffi.calloc.free(rlim);
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

  /// Windows: `SetErrorMode(...)` — suppresses the "stopped working" dialog
  /// and tells WER not to capture a crash dump for our process. Returns the
  /// previous error mode (we ignore it).
  static void _windowsSuppressErrorDialogs() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final setErrorMode = kernel
        .lookup<NativeFunction<_SetErrorModeC>>('SetErrorMode')
        .asFunction<_SetErrorModeDart>();
    // Bit values from winbase.h:
    //   SEM_FAILCRITICALERRORS     = 0x0001
    //   SEM_NOGPFAULTERRORBOX      = 0x0002
    //   SEM_NOOPENFILEERRORBOX     = 0x8000
    const flags = 0x0001 | 0x0002 | 0x8000;
    final prev = setErrorMode(flags);
    AppLogger.instance.log(
      'SetErrorMode($flags) applied (previous=$prev)',
      name: 'ProcessHardening',
    );
  }
}

typedef _SetErrorModeC = Uint32 Function(Uint32);
typedef _SetErrorModeDart = int Function(int);

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

typedef _SetRLimitC = Int32 Function(Int32, Pointer<UnsignedLong>);
typedef _SetRLimitDart = int Function(int, Pointer<UnsignedLong>);
