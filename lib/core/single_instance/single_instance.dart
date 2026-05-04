import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import '../../utils/platform.dart' as plat;

/// Prevents multiple instances of the app from running simultaneously.
///
/// Uses `dart:io`'s `RandomAccessFile.lock(FileLock.exclusive)` —
/// resolves to `fcntl(F_SETLK, F_WRLCK)` on Linux/macOS and
/// `LockFileEx(LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY)`
/// on Windows. The OS releases the advisory lock automatically on
/// process exit (even on crash) so there are no stale lock files
/// to clean up.
///
/// Pure Dart on purpose: a previous iteration routed through a
/// Rust crate (`lfs_os_security::single_instance`) that called
/// `flock()`. That forced the lock check to wait on
/// `RustLib.init()` — ~3 s on Windows IoT because of Defender's
/// real-time scan of the bundled native blob. The order conflict
/// broke splash-first boot: putting the check before `RustLib.init`
/// threw "RustLib not initialised", the catch reported contention,
/// and every solo cold-start landed on `AlreadyRunningApp`. Going
/// back to Dart drops the FFI dependency entirely, so the check
/// happens at the very top of `_mainBody` before any heavy init.
///
/// **POSIX `fcntl(F_SETLK)` footgun:** locks are per-PROCESS, not
/// per-fd. Two `RandomAccessFile.lock` calls in the same process
/// to the same file do *not* contend — the kernel sees the lock as
/// already held by us. Cross-process contention (the only case
/// that matters for single-instance) works correctly. The other
/// edge: closing ANY fd in this process pointing to the locked
/// file releases the lock. Nothing else in the app re-opens
/// `app.lock`, so this stays inert; if a future feature ever needs
/// to read the file, route it through this class instead of
/// opening the path directly.
///
/// Desktop only — on mobile, the OS manages single-instance natively.
class SingleInstance {
  /// Creates a [SingleInstance] guard.
  ///
  /// [lockDir] overrides the directory for the lock file (useful in
  /// tests). When null, uses [getApplicationSupportDirectory].
  SingleInstance({this.lockDir});

  /// Override for the lock file directory (for testing).
  final String? lockDir;

  RandomAccessFile? _lockHandle;
  String? _lockPath;

  /// Whether the lock is currently held by this instance.
  bool get isAcquired => _lockHandle != null;

  static const _lockFileName = 'app.lock';

  /// Tries to acquire the single-instance lock.
  ///
  /// Returns `true` if this is the only running instance (lock
  /// acquired). Returns `false` if another instance already holds
  /// the lock. On mobile platforms, always returns `true`.
  Future<bool> acquire() async {
    if (!plat.isDesktopPlatform) return true;

    final dirPath = lockDir ?? (await getApplicationSupportDirectory()).path;
    final lockPath = '$dirPath${Platform.pathSeparator}$_lockFileName';

    RandomAccessFile? handle;
    try {
      handle = await File(lockPath).open(mode: FileMode.write);
      await handle.lock(FileLock.exclusive);
      // Best-effort PID write for diagnostics — `truncate` then
      // write so a stale PID from a previous process does not
      // linger in the file. Failures are non-fatal; the lock works
      // either way.
      try {
        await handle.truncate(0);
        await handle.setPosition(0);
        await handle.writeString('$pid\n');
        await handle.flush();
      } catch (_) {
        // Diagnostic write failure does not affect the lock.
      }
      _lockHandle = handle;
      _lockPath = lockPath;
      AppLogger.instance.log(
        'Single-instance lock acquired: $lockPath',
        name: 'App',
      );
      return true;
    } catch (e) {
      // Lock contention or open failure (perms, missing parent
      // dir, read-only fs). Either way the second-instance UX
      // path is the same: bail to AlreadyRunningApp.
      AppLogger.instance.log(
        'Another instance is running (lock failed: $e)',
        name: 'App',
      );
      try {
        await handle?.close();
      } catch (_) {
        // Best-effort cleanup.
      }
      return false;
    }
  }

  /// Releases the lock. Safe to call even if [acquire] was never
  /// called or failed. Closing the file handle releases the
  /// `flock` / `LockFileEx` lock atomically; we then unlink the
  /// lock file so a clean shutdown leaves no on-disk trace.
  Future<void> release() async {
    final handle = _lockHandle;
    final path = _lockPath;
    _lockHandle = null;
    _lockPath = null;
    if (handle == null) return;
    try {
      await handle.unlock();
    } catch (_) {
      // Already released by close; non-fatal.
    }
    try {
      await handle.close();
    } catch (e) {
      AppLogger.instance.log('Lock close error: $e', name: 'App', error: e);
    }
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Unlink failure is non-fatal — OS released the lock
        // when the fd closed; a stale empty file does not block
        // the next launch.
      }
    }
    AppLogger.instance.log('Single-instance lock released', name: 'App');
  }
}
