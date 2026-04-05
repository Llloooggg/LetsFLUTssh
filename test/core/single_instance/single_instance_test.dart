import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/single_instance/single_instance.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
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

    test('second process cannot acquire lock', () async {
      final lock = SingleInstance(lockDir: tmpDir.path);
      expect(await lock.acquire(), isTrue);

      // Spawn a child process that tries to exclusively lock the same file.
      // POSIX fcntl locks are per-process, so we must use a real subprocess.
      final lockPath = '${tmpDir.path}${Platform.pathSeparator}app.lock'.replaceAll(r'\', '/');
      final scriptPath = '${tmpDir.path}${Platform.pathSeparator}try_lock.dart'.replaceAll(r'\', '/');
      File(scriptPath).writeAsStringSync(
        'import "dart:io";\n'
        'void main() async {\n'
        '  final raf = await File("$lockPath").open(mode: FileMode.write);\n'
        '  try {\n'
        '    await raf.lock(FileLock.exclusive);\n'
        '    await raf.unlock();\n'
        '    await raf.close();\n'
        '    exit(0);\n'
        '  } catch (_) {\n'
        '    await raf.close();\n'
        '    exit(1);\n'
        '  }\n'
        '}\n',
      );

      // Use `dart run` (not Platform.resolvedExecutable which may be
      // the Flutter test harness).
      final result = await Process.run('dart', ['run', scriptPath]);
      expect(result.exitCode, 1, reason: 'child process should fail to acquire lock');

      await lock.release();
    }, timeout: const Timeout(Duration(seconds: 60)));

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
