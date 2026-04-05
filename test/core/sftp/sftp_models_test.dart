import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/sftp/sftp_models.dart';

void main() {
  group('FileEntry', () {
    test('modeString for zero mode', () {
      final entry = FileEntry(name: 'test', path: '/test', size: 0, mode: 0, modTime: DateTime(2025), isDir: false);
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

  group('TransferProgress', () {
    test('percent calculation', () {
      const p = TransferProgress(fileName: 'test', totalBytes: 1000, doneBytes: 500, isUpload: true);
      expect(p.percent, 50.0);
    });

    test('percent is 0 when totalBytes is 0', () {
      const p = TransferProgress(fileName: 'test', totalBytes: 0, doneBytes: 0, isUpload: false);
      expect(p.percent, 0.0);
    });

    test('percent clamped to 100', () {
      const p = TransferProgress(fileName: 'test', totalBytes: 100, doneBytes: 150, isUpload: true);
      expect(p.percent, 100.0);
    });
  });
}
