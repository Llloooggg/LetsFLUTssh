import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';

void main() {
  late Directory tempDir;
  late LocalFS fs;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfs_real_test_');
    fs = LocalFS();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('LocalFS.list', () {
    test('lists files and directories sorted (dirs first)', () async {
      await File('${tempDir.path}/zebra.txt').writeAsString('z');
      await File('${tempDir.path}/apple.txt').writeAsString('a');
      await Directory('${tempDir.path}/mydir').create();

      final entries = await fs.list(tempDir.path);
      expect(entries.length, 3);
      // Directory first
      expect(entries[0].name, 'mydir');
      expect(entries[0].isDir, isTrue);
      // Then files sorted case-insensitively
      expect(entries[1].name, 'apple.txt');
      expect(entries[2].name, 'zebra.txt');
    });

    test('returns correct file properties', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('hello world');

      final entries = await fs.list(tempDir.path);
      expect(entries.length, 1);
      expect(entries[0].name, 'test.txt');
      expect(entries[0].path, file.path);
      expect(entries[0].size, greaterThan(0));
      expect(entries[0].isDir, isFalse);
      expect(entries[0].modTime, isA<DateTime>());
    });

    test('returns empty list for empty directory', () async {
      final entries = await fs.list(tempDir.path);
      expect(entries, isEmpty);
    });

    test('throws on non-existent directory', () async {
      expect(
        () => fs.list('${tempDir.path}/nonexistent'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('LocalFS.mkdir', () {
    test('creates directory recursively', () async {
      final path = '${tempDir.path}/a/b/c';
      await fs.mkdir(path);
      expect(Directory(path).existsSync(), isTrue);
    });

    test('no-op if directory already exists', () async {
      final path = '${tempDir.path}/existing';
      await Directory(path).create();
      // Should not throw
      await fs.mkdir(path);
      expect(Directory(path).existsSync(), isTrue);
    });
  });

  group('LocalFS.remove', () {
    test('removes a file', () async {
      final path = '${tempDir.path}/file.txt';
      await File(path).writeAsString('data');
      await fs.remove(path);
      expect(File(path).existsSync(), isFalse);
    });

    test('removes a directory recursively', () async {
      final dirPath = '${tempDir.path}/subdir';
      await Directory(dirPath).create();
      await File('$dirPath/inside.txt').writeAsString('data');
      await fs.remove(dirPath);
      expect(Directory(dirPath).existsSync(), isFalse);
    });
  });

  group('LocalFS.removeDir', () {
    test('removes directory recursively', () async {
      final dirPath = '${tempDir.path}/deep';
      await Directory('$dirPath/nested').create(recursive: true);
      await File('$dirPath/nested/file.txt').writeAsString('x');
      await fs.removeDir(dirPath);
      expect(Directory(dirPath).existsSync(), isFalse);
    });
  });

  group('LocalFS.rename', () {
    test('renames a file', () async {
      final oldPath = '${tempDir.path}/old.txt';
      final newPath = '${tempDir.path}/new.txt';
      await File(oldPath).writeAsString('content');
      await fs.rename(oldPath, newPath);
      expect(File(oldPath).existsSync(), isFalse);
      expect(File(newPath).existsSync(), isTrue);
      expect(await File(newPath).readAsString(), 'content');
    });

    test('renames a directory', () async {
      final oldPath = '${tempDir.path}/olddir';
      final newPath = '${tempDir.path}/newdir';
      await Directory(oldPath).create();
      await File('$oldPath/file.txt').writeAsString('data');
      await fs.rename(oldPath, newPath);
      expect(Directory(oldPath).existsSync(), isFalse);
      expect(Directory(newPath).existsSync(), isTrue);
      expect(File('$newPath/file.txt').existsSync(), isTrue);
    });
  });

  group('LocalFS.initialDir', () {
    test('returns a non-empty path', () async {
      final dir = await fs.initialDir();
      expect(dir, isNotEmpty);
    });
  });
}
