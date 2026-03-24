import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';

void main() {
  group('TransferDirection', () {
    test('has upload and download', () {
      expect(TransferDirection.values.length, 2);
      expect(TransferDirection.values, contains(TransferDirection.upload));
      expect(TransferDirection.values, contains(TransferDirection.download));
    });
  });

  group('TransferStatus', () {
    test('has all statuses', () {
      expect(TransferStatus.values.length, 4);
      expect(TransferStatus.values, contains(TransferStatus.queued));
      expect(TransferStatus.values, contains(TransferStatus.running));
      expect(TransferStatus.values, contains(TransferStatus.completed));
      expect(TransferStatus.values, contains(TransferStatus.failed));
    });
  });

  group('TransferTask', () {
    test('stores all fields', () {
      final task = TransferTask(
        name: 'test.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        run: (_) async {},
      );
      expect(task.name, 'test.txt');
      expect(task.direction, TransferDirection.upload);
      expect(task.sourcePath, '/local/test.txt');
      expect(task.targetPath, '/remote/test.txt');
    });
  });

  group('HistoryEntry', () {
    test('duration calculated from startedAt and endedAt', () {
      final start = DateTime(2024, 1, 1, 10, 0, 0);
      final end = DateTime(2024, 1, 1, 10, 0, 5);
      final entry = HistoryEntry(
        id: '1',
        name: 'file.txt',
        direction: TransferDirection.upload,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.completed,
        createdAt: start,
        startedAt: start,
        endedAt: end,
      );
      expect(entry.duration, const Duration(seconds: 5));
    });

    test('duration is null when startedAt is null', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'file.txt',
        direction: TransferDirection.download,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.failed,
        createdAt: DateTime.now(),
      );
      expect(entry.duration, isNull);
    });

    test('duration is null when endedAt is null', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'file.txt',
        direction: TransferDirection.upload,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.running,
        createdAt: DateTime.now(),
        startedAt: DateTime.now(),
      );
      expect(entry.duration, isNull);
    });

    test('directionIcon for upload', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'f',
        direction: TransferDirection.upload,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.completed,
        createdAt: DateTime.now(),
      );
      expect(entry.directionIcon, '\u2191'); // ↑
    });

    test('directionIcon for download', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'f',
        direction: TransferDirection.download,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.completed,
        createdAt: DateTime.now(),
      );
      expect(entry.directionIcon, '\u2193'); // ↓
    });

    test('defaults for lastPercent and lastMessage', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'f',
        direction: TransferDirection.upload,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.queued,
        createdAt: DateTime.now(),
      );
      expect(entry.lastPercent, 0);
      expect(entry.lastMessage, '');
      expect(entry.error, isNull);
    });

    test('stores error message', () {
      final entry = HistoryEntry(
        id: '1',
        name: 'f',
        direction: TransferDirection.upload,
        sourcePath: '/a',
        targetPath: '/b',
        status: TransferStatus.failed,
        error: 'Permission denied',
        createdAt: DateTime.now(),
      );
      expect(entry.error, 'Permission denied');
    });
  });
}
