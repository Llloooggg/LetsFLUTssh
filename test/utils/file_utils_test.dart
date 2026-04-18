import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/file_utils.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_utils_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('writeFileAtomic', () {
    test('creates file with correct content', () async {
      final path = '${tempDir.path}/test.txt';
      await writeFileAtomic(path, 'hello world');
      expect(File(path).readAsStringSync(), 'hello world');
    });

    test('overwrites existing file atomically', () async {
      final path = '${tempDir.path}/test.txt';
      await writeFileAtomic(path, 'first');
      await writeFileAtomic(path, 'second');
      expect(File(path).readAsStringSync(), 'second');
    });

    test('creates parent directories', () async {
      final path = '${tempDir.path}/sub/dir/test.txt';
      await writeFileAtomic(path, 'nested');
      expect(File(path).readAsStringSync(), 'nested');
    });

    test('no .tmp file remains after write', () async {
      final path = '${tempDir.path}/test.txt';
      await writeFileAtomic(path, 'content');
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('preserves content on concurrent writes', () async {
      final path = '${tempDir.path}/test.txt';
      // Write multiple times; final file should have last content
      await Future.wait([
        writeFileAtomic(path, 'a'),
        writeFileAtomic(path, 'b'),
        writeFileAtomic(path, 'c'),
      ]);
      final content = File(path).readAsStringSync();
      expect(content.length, 1); // one of a, b, c — not corrupted
    });
  });

  group('writeBytesAtomic', () {
    test('creates file with correct bytes', () async {
      final path = '${tempDir.path}/test.bin';
      final bytes = [0x01, 0x02, 0x03, 0xFF];
      await writeBytesAtomic(path, bytes);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('overwrites existing file', () async {
      final path = '${tempDir.path}/test.bin';
      await writeBytesAtomic(path, [1, 2, 3]);
      await writeBytesAtomic(path, [4, 5]);
      expect(File(path).readAsBytesSync(), [4, 5]);
    });

    test('no .tmp file remains after write', () async {
      final path = '${tempDir.path}/test.bin';
      await writeBytesAtomic(path, [1]);
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('creates parent directories', () async {
      final path = '${tempDir.path}/a/b/test.bin';
      await writeBytesAtomic(path, [42]);
      expect(File(path).readAsBytesSync(), [42]);
    });
  });

  group('hardenFilePerms', () {
    test('runs without error on current platform', () async {
      final path = '${tempDir.path}/perm_test.txt';
      File(path).writeAsStringSync('test');
      // Should not throw on any platform
      await hardenFilePerms(path);
    });

    test('sets 600 permissions on Unix', () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final path = '${tempDir.path}/perm_test.txt';
      File(path).writeAsStringSync('secret');
      await hardenFilePerms(path);
      final result = Process.runSync('stat', ['-c', '%a', path]);
      expect(result.stdout.toString().trim(), '600');
    });

    test('restricts ACLs on Windows', () async {
      if (!Platform.isWindows) return;
      final path = '${tempDir.path}/perm_test.txt';
      File(path).writeAsStringSync('secret');
      await hardenFilePerms(path);
      // Verify icacls was applied — file should only have current user ACL
      final result = Process.runSync('icacls', [path]);
      final output = result.stdout.toString();
      final user = Platform.environment['USERNAME'] ?? '';
      expect(output, contains(user));
    });

    test('handles non-existent file gracefully', () async {
      // Should not throw — logs error internally
      await hardenFilePerms('${tempDir.path}/no_such_file');
    });
  });
}
