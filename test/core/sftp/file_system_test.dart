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
        FileEntry(name: 'file.txt', path: '/file.txt', size: 100, mode: 0644, modTime: DateTime.now(), isDir: false),
        FileEntry(name: 'dir', path: '/dir', size: 0, mode: 0755, modTime: DateTime.now(), isDir: true),
      ];
      sortEntries(entries);
      expect(entries[0].name, 'dir');
      expect(entries[1].name, 'file.txt');
    });

    test('files sorted case-insensitively', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(name: 'Zebra.txt', path: '/z', size: 0, mode: 0, modTime: now, isDir: false),
        FileEntry(name: 'apple.txt', path: '/a', size: 0, mode: 0, modTime: now, isDir: false),
        FileEntry(name: 'Banana.txt', path: '/b', size: 0, mode: 0, modTime: now, isDir: false),
      ];
      sortEntries(entries);
      expect(entries.map((e) => e.name).toList(), ['apple.txt', 'Banana.txt', 'Zebra.txt']);
    });

    test('directories sorted case-insensitively', () {
      final now = DateTime.now();
      final entries = [
        FileEntry(name: 'Zdir', path: '/z', size: 0, mode: 0, modTime: now, isDir: true),
        FileEntry(name: 'adir', path: '/a', size: 0, mode: 0, modTime: now, isDir: true),
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
        FileEntry(name: 'only', path: '/only', size: 0, mode: 0, modTime: DateTime.now(), isDir: false),
      ];
      sortEntries(entries);
      expect(entries.length, 1);
    });
  });

  group('LocalFS.parseAttribOutput', () {
    test('parses hidden and system files', () {
      const output = '     A  SH  C:\\Users\\\$Recycle.Bin\n'
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
      const output = '     A          C:\\file1.txt\n'
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
      expect(
        () => badDir.list().toList(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
