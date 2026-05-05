import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/transfer_task.dart';

void main() {
  group('TransferDirection', () {
    test('exposes upload + download', () {
      expect(TransferDirection.values, [
        TransferDirection.upload,
        TransferDirection.download,
      ]);
    });
  });

  group('TransferStatus', () {
    test('exposes the five lifecycle states', () {
      expect(TransferStatus.values, [
        TransferStatus.queued,
        TransferStatus.running,
        TransferStatus.completed,
        TransferStatus.failed,
        TransferStatus.cancelled,
      ]);
    });
  });

  group('HistoryEntry', () {
    HistoryEntry make({
      TransferDirection direction = TransferDirection.upload,
      TransferStatus status = TransferStatus.completed,
      Object? error,
      DateTime? startedAt,
      DateTime? endedAt,
    }) => HistoryEntry(
      id: 'task-1',
      name: 'photo.jpg',
      direction: direction,
      sourcePath: '/local/photo.jpg',
      targetPath: '/remote/photo.jpg',
      status: status,
      error: error,
      createdAt: DateTime.utc(2026, 1, 1),
      startedAt: startedAt,
      endedAt: endedAt,
    );

    test('required fields land on the instance', () {
      final h = make();
      expect(h.id, 'task-1');
      expect(h.name, 'photo.jpg');
      expect(h.sourcePath, '/local/photo.jpg');
      expect(h.targetPath, '/remote/photo.jpg');
      expect(h.status, TransferStatus.completed);
      expect(h.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('optional fields default to documented zero state', () {
      final h = make();
      expect(h.error, isNull);
      expect(h.lastPercent, 0);
      expect(h.lastMessage, isEmpty);
      expect(h.startedAt, isNull);
      expect(h.endedAt, isNull);
      expect(h.sizeBytes, 0);
    });

    test('direction icon flips based on direction', () {
      expect(make(direction: TransferDirection.upload).directionIcon, '↑');
      expect(make(direction: TransferDirection.download).directionIcon, '↓');
    });

    test('duration is null when either timestamp is missing', () {
      expect(make().duration, isNull);
      expect(make(startedAt: DateTime.utc(2026, 1, 1, 12)).duration, isNull);
      expect(make(endedAt: DateTime.utc(2026, 1, 1, 12)).duration, isNull);
    });

    test('duration is endedAt - startedAt when both present', () {
      final h = make(
        startedAt: DateTime.utc(2026, 1, 1, 12),
        endedAt: DateTime.utc(2026, 1, 1, 12, 0, 5),
      );
      expect(h.duration, const Duration(seconds: 5));
    });

    test('failure carries an error object', () {
      final h = make(
        status: TransferStatus.failed,
        error: const FormatException('boom'),
      );
      expect(h.status, TransferStatus.failed);
      expect(h.error, isA<FormatException>());
    });
  });

  group('ActiveEntry', () {
    ActiveEntry make({
      TransferDirection direction = TransferDirection.upload,
      TransferStatus status = TransferStatus.running,
      double percent = 0,
      String message = '',
    }) => ActiveEntry(
      id: 'task-2',
      name: 'photo.jpg',
      direction: direction,
      sourcePath: '/local/photo.jpg',
      targetPath: '/remote/photo.jpg',
      status: status,
      percent: percent,
      message: message,
    );

    test('required fields land on the instance', () {
      final a = make(percent: 0.5, message: 'in flight');
      expect(a.id, 'task-2');
      expect(a.name, 'photo.jpg');
      expect(a.sourcePath, '/local/photo.jpg');
      expect(a.targetPath, '/remote/photo.jpg');
      expect(a.status, TransferStatus.running);
      expect(a.percent, 0.5);
      expect(a.message, 'in flight');
    });

    test('optional fields default to documented zero state', () {
      final a = make();
      expect(a.percent, 0);
      expect(a.message, isEmpty);
    });

    test('direction icon flips based on direction', () {
      expect(make(direction: TransferDirection.upload).directionIcon, '↑');
      expect(make(direction: TransferDirection.download).directionIcon, '↓');
    });

    test('queued state is representable', () {
      final a = make(status: TransferStatus.queued);
      expect(a.status, TransferStatus.queued);
    });
  });
}
