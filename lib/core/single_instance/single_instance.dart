import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import '../../utils/platform.dart' as plat;

/// Prevents multiple instances of the app from running simultaneously.
///
/// Uses exclusive file locking via [RandomAccessFile.lock]. The OS
/// automatically releases the lock when the process exits (even on crash),
/// so there are no stale lock files to clean up.
///
/// Desktop only — on mobile, the OS manages single-instance natively.
class SingleInstance {
  /// Creates a [SingleInstance] guard.
  ///
  /// [lockDir] overrides the directory for the lock file (useful in tests).
  /// When null, uses [getApplicationSupportDirectory].
  SingleInstance({this.lockDir});

  /// Override for the lock file directory (for testing).
  final String? lockDir;

  RandomAccessFile? _lockFile;

  /// Whether the lock is currently held by this instance.
  bool get isAcquired => _lockFile != null;

  static const _lockFileName = 'app.lock';

  /// Tries to acquire the single-instance lock.
  ///
  /// Returns `true` if this is the only running instance (lock acquired).
  /// Returns `false` if another instance already holds the lock.
  /// On mobile platforms, always returns `true`.
  Future<bool> acquire() async {
    if (!plat.isDesktopPlatform) return true;

    final dirPath =
        lockDir ?? (await getApplicationSupportDirectory()).path;
    final lockPath = '$dirPath${Platform.pathSeparator}$_lockFileName';

    try {
      final file = File(lockPath);
      _lockFile = await file.open(mode: FileMode.write);
      await _lockFile!.lock(FileLock.exclusive);
      // Write PID for diagnostics (not used for logic).
      await _lockFile!.writeString('$pid\n');
      await _lockFile!.flush();
      AppLogger.instance
          .log('Single-instance lock acquired: $lockPath', name: 'App');
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Another instance is running (lock failed: $e)',
        name: 'App',
      );
      try {
        await _lockFile?.close();
      } catch (_) {}
      _lockFile = null;
      return false;
    }
  }

  /// Releases the lock and removes the lock file.
  ///
  /// Safe to call even if [acquire] was never called or failed.
  Future<void> release() async {
    if (_lockFile == null) return;

    try {
      final path = _lockFile!.path;
      await _lockFile!.unlock();
      await _lockFile!.close();
      await File(path).delete();
      AppLogger.instance.log('Single-instance lock released', name: 'App');
    } catch (e) {
      AppLogger.instance
          .log('Lock release error: $e', name: 'App', error: e);
    }
    _lockFile = null;
  }
}
