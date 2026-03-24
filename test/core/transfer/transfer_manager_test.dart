import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';

void main() {
  group('TransferManager', () {
    late TransferManager manager;

    setUp(() {
      manager = TransferManager(parallelism: 2, maxHistory: 10);
    });

    tearDown(() {
      manager.dispose();
    });

    test('enqueue returns unique ids', () {
      final id1 = manager.enqueue(_dummyTask('file1'));
      final id2 = manager.enqueue(_dummyTask('file2'));
      expect(id1, isNot(equals(id2)));
    });

    test('completed tasks appear in history', () async {
      manager.enqueue(TransferTask(
        name: 'test.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/test.txt',
        targetPath: '/remote/test.txt',
        run: (update) async {
          update(50, 'half');
          update(100, 'done');
        },
      ));

      // Wait for task to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.history, hasLength(1));
      expect(manager.history.first.name, 'test.txt');
      expect(manager.history.first.status, TransferStatus.completed);
      expect(manager.history.first.lastPercent, 100);
    });

    test('failed tasks appear in history with error', () async {
      manager.enqueue(TransferTask(
        name: 'fail.txt',
        direction: TransferDirection.download,
        sourcePath: '/remote/fail.txt',
        targetPath: '/local/fail.txt',
        run: (update) async {
          update(10, 'starting');
          throw Exception('network error');
        },
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.history, hasLength(1));
      expect(manager.history.first.status, TransferStatus.failed);
      expect(manager.history.first.error, contains('network error'));
    });

    test('respects parallelism limit', () async {
      final running = <String>[];
      int maxConcurrent = 0;
      final allDone = Completer<void>();
      int completed = 0;

      for (int i = 0; i < 5; i++) {
        manager.enqueue(TransferTask(
          name: 'file$i',
          direction: TransferDirection.upload,
          sourcePath: '/local/file$i',
          targetPath: '/remote/file$i',
          run: (update) async {
            running.add('file$i');
            if (running.length > maxConcurrent) {
              maxConcurrent = running.length;
            }
            await Future.delayed(const Duration(milliseconds: 50));
            running.remove('file$i');
            completed++;
            if (completed == 5) allDone.complete();
          },
        ));
      }

      await allDone.future.timeout(const Duration(seconds: 5));
      expect(maxConcurrent, lessThanOrEqualTo(2));
      expect(manager.history, hasLength(5));
    });

    test('clearHistory removes all entries', () async {
      manager.enqueue(_dummyTask('file1'));
      manager.enqueue(_dummyTask('file2'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.history, hasLength(2));
      manager.clearHistory();
      expect(manager.history, isEmpty);
    });

    test('deleteHistory removes specific entries', () async {
      final id1 = manager.enqueue(_dummyTask('file1'));
      manager.enqueue(_dummyTask('file2'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.history, hasLength(2));
      manager.deleteHistory([id1]);
      expect(manager.history, hasLength(1));
      expect(manager.history.first.name, 'file2');
    });

    test('history capped at maxHistory', () async {
      for (int i = 0; i < 15; i++) {
        manager.enqueue(_dummyTask('file$i'));
      }
      await Future.delayed(const Duration(milliseconds: 500));

      expect(manager.history.length, lessThanOrEqualTo(10));
    });

    test('onChange stream fires on state changes', () async {
      int eventCount = 0;
      final sub = manager.onChange.listen((_) => eventCount++);

      manager.enqueue(_dummyTask('file1'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(eventCount, greaterThan(0));
      await sub.cancel();
    });

    test('history entry has duration', () async {
      manager.enqueue(TransferTask(
        name: 'slow.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/slow.txt',
        targetPath: '/remote/slow.txt',
        run: (update) async {
          await Future.delayed(const Duration(milliseconds: 50));
        },
      ));
      await Future.delayed(const Duration(milliseconds: 200));

      final entry = manager.history.first;
      expect(entry.duration, isNotNull);
      expect(entry.duration!.inMilliseconds, greaterThanOrEqualTo(40));
    });
  });
}

TransferTask _dummyTask(String name) {
  return TransferTask(
    name: name,
    direction: TransferDirection.upload,
    sourcePath: '/local/$name',
    targetPath: '/remote/$name',
    run: (update) async {
      update(100, 'done');
    },
  );
}
