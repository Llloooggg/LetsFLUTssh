import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';
import '../../utils/platform.dart' as plat;

/// Prevents multiple instances of the app from running simultaneously.
///
/// Routes through `lfs_os_security::single_instance` (FRB sync). Rust
/// owns the file handle + the advisory `fcntl(F_SETLK)` /
/// `LockFileEx` lock; the OS releases it automatically on process
/// exit (even on crash) so there are no stale lock files to clean up.
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

  BigInt? _handleId;

  /// Whether the lock is currently held by this instance.
  bool get isAcquired => _handleId != null;

  static const _lockFileName = 'app.lock';

  /// Tries to acquire the single-instance lock.
  ///
  /// Returns `true` if this is the only running instance (lock
  /// acquired). Returns `false` if another instance already holds
  /// the lock. On mobile platforms, always returns `true`.
  Future<bool> acquire() async {
    if (!plat.isDesktopPlatform) return true;

    final dirPath = lockDir ?? (await getApplicationSupportDirectory()).path;
    final lockPath = '$dirPath/$_lockFileName';

    try {
      _handleId = rust_os.osSecurityAcquireSingleInstance(path: lockPath);
      AppLogger.instance.log(
        'Single-instance lock acquired: $lockPath',
        name: 'App',
      );
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Another instance is running (lock failed: $e)',
        name: 'App',
      );
      _handleId = null;
      return false;
    }
  }

  /// Releases the lock. Safe to call even if [acquire] was never
  /// called or failed. Rust-side `release` is idempotent so a
  /// double-call is a no-op.
  Future<void> release() async {
    final id = _handleId;
    if (id == null) return;
    _handleId = null;
    try {
      rust_os.osSecurityReleaseSingleInstance(handleId: id);
      AppLogger.instance.log('Single-instance lock released', name: 'App');
    } catch (e) {
      AppLogger.instance.log('Lock release error: $e', name: 'App', error: e);
    }
  }
}
