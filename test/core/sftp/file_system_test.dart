import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';

// Test the sorting logic used by LocalFS without needing real file I/O for sort.
// Also test LocalFS operations using temp directories.

void main() {
  group('LocalFS sort logic', () {
    // Re-implement the sort from LocalFS._sort() to test in isolation
    void sortEntries(List<FileEntry> entries) {
      entries.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    test('directories come before files', () {
      final entries = [
        FileEntry(
          name: 'file.txt',
          path: '/file.txt',
          size: 100,
          mode: 0644,
          modTime: DateTime.now(),
          isDir: false,
        ),
        FileEntry(
          name: 'dir',
          path: '/dir',
          size: 0,
          mode: 0755,
          modTime: DateTime.now(),
          isDir: true,
        ),
      ];
      sortEntries(entries);
      expect(entries[0].name, 'dir');
      expect(entries[1].name, 'file.txt');
    });

    test('files sorted case-insensitively', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(
          name: 'Zebra.txt',
          path: '/z',
          size: 0,
          mode: 0,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'apple.txt',
          path: '/a',
          size: 0,
          mode: 0,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'Banana.txt',
          path: '/b',
          size: 0,
          mode: 0,
          modTime: now,
          isDir: false,
        ),
      ];
      sortEntries(entries);
      expect(entries.map((e) => e.name).toList(), [
        'apple.txt',
        'Banana.txt',
        'Zebra.txt',
      ]);
    });

    test('directories sorted case-insensitively', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(
          name: 'Zdir',
          path: '/z',
          size: 0,
          mode: 0,
          modTime: now,
          isDir: true,
        ),
        FileEntry(
          name: 'adir',
          path: '/a',
          size: 0,
          mode: 0,
          modTime: now,
          isDir: true,
        ),
      ];
      sortEntries(entries);
      expect(entries[0].name, 'adir');
      expect(entries[1].name, 'Zdir');
    });

    test('empty list sorts without error', () {
      final entries = <FileEntry>[];
      sortEntries(entries);
      expect(entries, isEmpty);
    });

    test('single entry sorts without error', () {
      final entries = [
        FileEntry(
          name: 'only',
          path: '/only',
          size: 0,
          mode: 0,
          modTime: DateTime.now(),
          isDir: false,
        ),
      ];
      sortEntries(entries);
      expect(entries.length, 1);
    });
  });

  group('LocalFS.parseAttribOutput', () {
    test('parses hidden and system files', () {
      const output =
          '     A  SH  C:\\Users\\\$Recycle.Bin\n'
          '     A          C:\\Users\\Documents\n'
          '     A    H     C:\\Users\\desktop.ini\n'
          '     A  S       C:\\System Volume Information\n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, contains('\$recycle.bin'));
      expect(result, contains('desktop.ini'));
      expect(result, contains('system volume information'));
      expect(result, isNot(contains('documents')));
    });

    test('returns empty set for empty output', () {
      expect(LocalFS.parseAttribOutput(''), isEmpty);
    });

    test('returns empty set for output with no H/S flags', () {
      const output =
          '     A          C:\\file1.txt\n'
          '     A    R     C:\\file2.txt\n';
      expect(LocalFS.parseAttribOutput(output), isEmpty);
    });

    test('handles lines without valid format', () {
      const output = 'some garbage\n\n     A  SH  C:\\hidden.dat\n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, contains('hidden.dat'));
      expect(result.length, 1);
    });
  });

  group('LocalFS file operations', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('mkdir creates directory recursively', () async {
      final path = '${tempDir.path}/a/b/c';
      await Directory(path).create(recursive: true);
      expect(Directory(path).existsSync(), isTrue);
    });

    test('remove deletes file', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('hello');
      expect(file.existsSync(), isTrue);
      await file.delete();
      expect(file.existsSync(), isFalse);
    });

    test('remove deletes directory recursively', () async {
      final dir = Directory('${tempDir.path}/subdir');
      await dir.create();
      await File('${dir.path}/file.txt').writeAsString('data');
      await Directory(dir.path).delete(recursive: true);
      expect(dir.existsSync(), isFalse);
    });

    test('rename file', () async {
      final old = File('${tempDir.path}/old.txt');
      await old.writeAsString('content');
      final newFile = await old.rename('${tempDir.path}/new.txt');
      expect(newFile.existsSync(), isTrue);
      expect(File('${tempDir.path}/old.txt').existsSync(), isFalse);
    });

    test('rename directory', () async {
      final old = Directory('${tempDir.path}/olddir');
      await old.create();
      await File('${old.path}/inside.txt').writeAsString('data');
      final newDir = await old.rename('${tempDir.path}/newdir');
      expect(newDir.existsSync(), isTrue);
      expect(File('${newDir.path}/inside.txt').existsSync(), isTrue);
      expect(Directory('${tempDir.path}/olddir').existsSync(), isFalse);
    });

    test('list returns files and directories', () async {
      await File('${tempDir.path}/file1.txt').writeAsString('a');
      await File('${tempDir.path}/file2.txt').writeAsString('b');
      await Directory('${tempDir.path}/subdir').create();

      final entities = await tempDir.list().toList();
      expect(entities.length, 3);
    });

    test('list throws on non-existent directory', () async {
      final badDir = Directory('${tempDir.path}/nonexistent');
      expect(() => badDir.list().toList(), throwsA(isA<FileSystemException>()));
    });
  });

  group('LocalFS.list() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_list_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns sorted entries with directories first', () async {
      await File('${tempDir.path}/zebra.txt').writeAsString('z');
      await File('${tempDir.path}/apple.txt').writeAsString('a');
      await Directory('${tempDir.path}/mydir').create();

      final entries = await fs.list(tempDir.path);
      expect(entries.length, 3);
      // Directory should come first
      expect(entries[0].name, 'mydir');
      expect(entries[0].isDir, isTrue);
      // Files sorted alphabetically
      expect(entries[1].name, 'apple.txt');
      expect(entries[2].name, 'zebra.txt');
    });

    test('returns empty list for empty directory', () async {
      final entries = await fs.list(tempDir.path);
      expect(entries, isEmpty);
    });

    test('throws FileSystemException for non-existent path', () async {
      final badPath = '${tempDir.path}/does_not_exist';
      expect(() => fs.list(badPath), throwsA(isA<FileSystemException>()));
    });

    test('populates file size and type correctly', () async {
      const content = 'hello world';
      await File('${tempDir.path}/data.txt').writeAsString(content);
      await Directory('${tempDir.path}/sub').create();

      final entries = await fs.list(tempDir.path);
      final file = entries.firstWhere((e) => e.name == 'data.txt');
      final dir = entries.firstWhere((e) => e.name == 'sub');

      expect(file.isDir, isFalse);
      expect(file.size, content.length);
      expect(file.path, endsWith('data.txt'));

      expect(dir.isDir, isTrue);
    });
  });

  group('LocalFS.dirSize() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_dirsize_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns 0 for non-existent directory', () async {
      final size = await fs.dirSize('${tempDir.path}/nonexistent');
      expect(size, 0);
    });

    test('returns 0 for empty directory', () async {
      final size = await fs.dirSize(tempDir.path);
      expect(size, 0);
    });

    test('sums file sizes recursively', () async {
      const data1 = 'hello'; // 5 bytes
      const data2 = 'world!'; // 6 bytes
      await File('${tempDir.path}/a.txt').writeAsString(data1);
      await Directory('${tempDir.path}/sub').create();
      await File('${tempDir.path}/sub/b.txt').writeAsString(data2);

      final size = await fs.dirSize(tempDir.path);
      expect(size, data1.length + data2.length);
    });

    test('ignores subdirectories in size count', () async {
      await Directory('${tempDir.path}/emptydir').create();
      final size = await fs.dirSize(tempDir.path);
      expect(size, 0);
    });
  });

  group('LocalFS.mkdir() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_mkdir_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('creates nested directories', () async {
      final path = '${tempDir.path}/a/b/c';
      await fs.mkdir(path);
      expect(Directory(path).existsSync(), isTrue);
    });
  });

  group('LocalFS.remove() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_remove_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('removes a file', () async {
      final filePath = '${tempDir.path}/test.txt';
      await File(filePath).writeAsString('data');
      expect(File(filePath).existsSync(), isTrue);

      await fs.remove(filePath);
      expect(File(filePath).existsSync(), isFalse);
    });

    test('removes a directory recursively', () async {
      final dirPath = '${tempDir.path}/subdir';
      await Directory(dirPath).create();
      await File('$dirPath/file.txt').writeAsString('data');

      await fs.remove(dirPath);
      expect(Directory(dirPath).existsSync(), isFalse);
    });
  });

  group('LocalFS.removeDir() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_removedir_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('removes directory with contents', () async {
      final dirPath = '${tempDir.path}/target';
      await Directory(dirPath).create();
      await File('$dirPath/inner.txt').writeAsString('content');

      await fs.removeDir(dirPath);
      expect(Directory(dirPath).existsSync(), isFalse);
    });
  });

  group('LocalFS.rename() via instance', () {
    late Directory tempDir;
    late LocalFS fs;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localfs_rename_');
      fs = LocalFS();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('renames a file', () async {
      final oldPath = '${tempDir.path}/old.txt';
      final newPath = '${tempDir.path}/new.txt';
      await File(oldPath).writeAsString('content');

      await fs.rename(oldPath, newPath);
      expect(File(newPath).existsSync(), isTrue);
      expect(File(oldPath).existsSync(), isFalse);
    });

    test('renames a directory', () async {
      final oldPath = '${tempDir.path}/olddir';
      final newPath = '${tempDir.path}/newdir';
      await Directory(oldPath).create();
      await File('$oldPath/file.txt').writeAsString('data');

      await fs.rename(oldPath, newPath);
      expect(Directory(newPath).existsSync(), isTrue);
      expect(File('$newPath/file.txt').existsSync(), isTrue);
      expect(Directory(oldPath).existsSync(), isFalse);
    });
  });

  group('LocalFS.parseAttribOutput edge cases', () {
    test('handles mixed attributes on same file', () {
      const output = '  A  SHR  C:\\Users\\secret.dat\n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, contains('secret.dat'));
    });

    test('handles path with spaces', () {
      const output = '     A    H     C:\\Program Files\\hidden file.dat\n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, contains('hidden file.dat'));
    });

    test('handles only whitespace lines', () {
      const output = '   \n   \n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, isEmpty);
    });

    test('converts names to lowercase for case-insensitive matching', () {
      const output = '     A  SH  C:\\Users\\HIDDEN.DAT\n';
      final result = LocalFS.parseAttribOutput(output);
      expect(result, contains('hidden.dat'));
      expect(result, isNot(contains('HIDDEN.DAT')));
    });
  });

  group('sortFileEntries (from sftp_models)', () {
    test('sorts directories before files', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(
          name: 'file.txt',
          path: '/file.txt',
          size: 100,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'dir',
          path: '/dir',
          size: 0,
          modTime: now,
          isDir: true,
        ),
      ];
      sortFileEntries(entries);
      expect(entries[0].name, 'dir');
      expect(entries[1].name, 'file.txt');
    });

    test('sorts files case-insensitively', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(
          name: 'Zebra.txt',
          path: '/z',
          size: 0,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'apple.txt',
          path: '/a',
          size: 0,
          modTime: now,
          isDir: false,
        ),
      ];
      sortFileEntries(entries);
      expect(entries[0].name, 'apple.txt');
      expect(entries[1].name, 'Zebra.txt');
    });

    test('handles empty list', () {
      final entries = <FileEntry>[];
      sortFileEntries(entries);
      expect(entries, isEmpty);
    });

    test('handles single entry', () {
      final entries = [
        FileEntry(
          name: 'only',
          path: '/only',
          size: 0,
          modTime: DateTime.now(),
          isDir: false,
        ),
      ];
      sortFileEntries(entries);
      expect(entries.length, 1);
      expect(entries[0].name, 'only');
    });

    test('mixed directories and files sorted correctly', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(
          name: 'zeta.txt',
          path: '/zeta.txt',
          size: 0,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'beta',
          path: '/beta',
          size: 0,
          modTime: now,
          isDir: true,
        ),
        FileEntry(
          name: 'alpha.txt',
          path: '/alpha.txt',
          size: 0,
          modTime: now,
          isDir: false,
        ),
        FileEntry(
          name: 'gamma',
          path: '/gamma',
          size: 0,
          modTime: now,
          isDir: true,
        ),
      ];
      sortFileEntries(entries);
      expect(entries.map((e) => e.name).toList(), [
        'beta',
        'gamma',
        'alpha.txt',
        'zeta.txt',
      ]);
    });
  });
}
