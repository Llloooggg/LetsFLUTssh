import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/single_instance/single_instance.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
  // Single-instance lock is pure-Dart on top of
  // `RandomAccessFile.lock(FileLock.exclusive)`; no FRB bootstrap
  // required.
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('single_instance_test_');
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
  });

  tearDown(() {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  group('SingleInstance', () {
    test('acquire succeeds on first call', () async {
      final lock = SingleInstance(lockDir: tmpDir.path);
      expect(await lock.acquire(), isTrue);
      expect(lock.isAcquired, isTrue);

      // Lock file should exist with our PID.
      final lockFile = File('${tmpDir.path}${Platform.pathSeparator}app.lock');
      expect(lockFile.existsSync(), isTrue);
      final content = await lockFile.readAsString();
      expect(content.trim(), equals('$pid'));

      await lock.release();
    });

    // Same-process contention is NOT covered as a unit test:
    // Dart's `RandomAccessFile.lock(FileLock.exclusive)` uses
    // `fcntl(F_SETLK, F_WRLCK)` on POSIX, which is a per-PROCESS
    // namespace — a second open + lock in the same process silently
    // succeeds because the kernel sees the lock as already held
    // by us. Real cross-process contention (the only case that
    // matters for single-instance UX) is covered at the OS layer
    // by the kernel and is exempt from unit tests per
    // AGENT_RULES § Testing Methodology.

    test('acquire succeeds after first releases', () async {
      final first = SingleInstance(lockDir: tmpDir.path);
      expect(await first.acquire(), isTrue);
      await first.release();
      expect(first.isAcquired, isFalse);

      final second = SingleInstance(lockDir: tmpDir.path);
      expect(await second.acquire(), isTrue);
      await second.release();
    });

    test('release removes lock file', () async {
      final lock = SingleInstance(lockDir: tmpDir.path);
      await lock.acquire();

      final lockFile = File('${tmpDir.path}${Platform.pathSeparator}app.lock');
      expect(lockFile.existsSync(), isTrue);

      await lock.release();
      expect(lockFile.existsSync(), isFalse);
      expect(lock.isAcquired, isFalse);
    });

    test('release is safe to call without acquire', () async {
      final lock = SingleInstance(lockDir: tmpDir.path);
      await lock.release();
      expect(lock.isAcquired, isFalse);
    });

    test('release is safe to call twice', () async {
      final lock = SingleInstance(lockDir: tmpDir.path);
      await lock.acquire();
      await lock.release();
      await lock.release();
      expect(lock.isAcquired, isFalse);
    });

    test('skips locking on mobile platforms', () async {
      plat.debugDesktopPlatformOverride = false;
      plat.debugMobilePlatformOverride = true;

      final lock = SingleInstance(lockDir: tmpDir.path);
      expect(await lock.acquire(), isTrue);
      // No lock file should be created on mobile.
      final lockFile = File('${tmpDir.path}${Platform.pathSeparator}app.lock');
      expect(lockFile.existsSync(), isFalse);
      // isAcquired is false because no file handle was opened.
      expect(lock.isAcquired, isFalse);
    });
  });
}
