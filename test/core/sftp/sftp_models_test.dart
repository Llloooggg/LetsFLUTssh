import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/src/rust/api/sftp_models.dart' as rust_sftp_models;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // FileEntry.modeString and sortFileEntries route through
  // `lfs_core::sftp_models` — bootstrap FRB so the canonical Rust
  // chmod-letter grammar and dirs-first sort are exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('FileEntry', () {
    test('modeString for zero mode', () {
      final entry = FileEntry(
        name: 'test',
        path: '/test',
        size: 0,
        mode: 0,
        modTime: DateTime(2025),
        isDir: false,
      );
      expect(entry.modeString, '---');
    });

    test('modeString for 0755 directory', () {
      final entry = FileEntry(
        name: 'dir',
        path: '/dir',
        size: 0,
        mode: int.parse('755', radix: 8),
        modTime: DateTime(2025),
        isDir: true,
      );
      // 0755 = rwxr-xr-x
      expect(entry.modeString, 'drwxr-xr-x');
    });

    test('modeString for 0644 file', () {
      final entry = FileEntry(
        name: 'file',
        path: '/file',
        size: 100,
        mode: int.parse('644', radix: 8),
        modTime: DateTime(2025),
        isDir: false,
      );
      // 0644 = rw-r--r--
      expect(entry.modeString, '-rw-r--r--');
    });
  });

  group('sortFileEntriesBy (Rust-backed keyed sort)', () {
    FileEntry mk(
      String name, {
      bool isDir = false,
      int size = 0,
      int mode = 0,
      String owner = '',
      DateTime? modTime,
    }) => FileEntry(
      name: name,
      path: '/$name',
      size: size,
      mode: mode,
      owner: owner,
      modTime: modTime ?? DateTime(2025),
      isDir: isDir,
    );

    test('directories always lead regardless of column and direction', () {
      // Spec: dirs-first is invariant; only within-kind order responds
      // to the column + direction. Size-descending must still keep the
      // (size-0) directory ahead of the larger file.
      final entries = [mk('big.bin', size: 900), mk('adir', isDir: true)];
      sortFileEntriesBy(entries, rust_sftp_models.DbSortField.size, false);
      expect(entries.map((e) => e.name), ['adir', 'big.bin']);
    });

    test('size ascending orders smallest file first', () {
      final entries = [
        mk('big', size: 900),
        mk('small', size: 10),
        mk('mid', size: 100),
      ];
      sortFileEntriesBy(entries, rust_sftp_models.DbSortField.size, true);
      expect(entries.map((e) => e.name), ['small', 'mid', 'big']);
    });

    test('owner sorts case-insensitively', () {
      final entries = [
        mk('a', owner: 'Zoe'),
        mk('b', owner: 'alice'),
        mk('c', owner: 'Bob'),
      ];
      sortFileEntriesBy(entries, rust_sftp_models.DbSortField.owner, true);
      // alice, Bob, Zoe — case folded.
      expect(entries.map((e) => e.owner), ['alice', 'Bob', 'Zoe']);
    });

    test('name descending reverses within kind', () {
      final entries = [mk('apple'), mk('cherry'), mk('banana')];
      sortFileEntriesBy(entries, rust_sftp_models.DbSortField.name, false);
      expect(entries.map((e) => e.name), ['cherry', 'banana', 'apple']);
    });

    test('default sortFileEntries is name ascending, dirs first', () {
      final entries = [
        mk('zebra.txt'),
        mk('adir', isDir: true),
        mk('apple.txt'),
      ];
      sortFileEntries(entries);
      expect(entries.map((e) => e.name), ['adir', 'apple.txt', 'zebra.txt']);
    });
  });

  group('TransferProgress', () {
    test('percent calculation', () {
      const p = TransferProgress(
        fileName: 'test',
        totalBytes: 1000,
        doneBytes: 500,
        isUpload: true,
      );
      expect(p.percent, 50.0);
    });

    test('percent is 0 when totalBytes is 0', () {
      const p = TransferProgress(
        fileName: 'test',
        totalBytes: 0,
        doneBytes: 0,
        isUpload: false,
      );
      expect(p.percent, 0.0);
    });

    test('percent clamped to 100', () {
      const p = TransferProgress(
        fileName: 'test',
        totalBytes: 100,
        doneBytes: 150,
        isUpload: true,
      );
      expect(p.percent, 100.0);
    });
  });
}
