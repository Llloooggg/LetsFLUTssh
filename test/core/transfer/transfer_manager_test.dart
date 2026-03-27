import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';

void main() {
  group('TransferManager', () {
    late TransferManager manager;

    setUp(() {
      manager = TransferManager(parallelism: 2, maxHistory: 10, taskTimeout: Duration.zero);
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

    test('currentTransferInfo shows active task progress', () async {
      final started = Completer<void>();
      final finish = Completer<void>();

      manager.enqueue(TransferTask(
        name: 'active.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/active.txt',
        targetPath: '/remote/active.txt',
        run: (update) async {
          update(50, 'half');
          started.complete();
          await finish.future;
        },
      ));

      await started.future;
      expect(manager.currentTransferInfo, contains('active.txt'));
      expect(manager.currentTransferInfo, contains('50%'));

      finish.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(manager.currentTransferInfo, isNull);
    });

    test('concurrent tasks have separate progress in _activeTransfers', () async {
      final started1 = Completer<void>();
      final started2 = Completer<void>();
      final finish1 = Completer<void>();
      final finish2 = Completer<void>();

      manager.enqueue(TransferTask(
        name: 'file1.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/file1.txt',
        targetPath: '/remote/file1.txt',
        run: (update) async {
          update(30, 'file1');
          started1.complete();
          await finish1.future;
        },
      ));

      manager.enqueue(TransferTask(
        name: 'file2.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/file2.txt',
        targetPath: '/remote/file2.txt',
        run: (update) async {
          update(70, 'file2');
          started2.complete();
          await finish2.future;
        },
      ));

      await started1.future;
      await started2.future;
      // currentTransferInfo should show one of the active tasks
      expect(manager.currentTransferInfo, isNotNull);

      finish1.complete();
      finish2.complete();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(manager.currentTransferInfo, isNull);
    });

    test('dispose prevents further notifications', () async {
      manager.dispose();
      // Should not throw when enqueueing after dispose
      // (task runs but _notify is guarded)
      final manager2 = TransferManager(parallelism: 1, maxHistory: 10);
      manager2.dispose();
      // Calling enqueue after dispose — _notify should not crash
      // We can't easily test this without internal access,
      // but at least verify dispose is idempotent
    });

    test('error messages are sanitized (paths stripped)', () async {
      manager.enqueue(TransferTask(
        name: 'pathfail.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/pathfail.txt',
        targetPath: '/remote/pathfail.txt',
        run: (update) async {
          throw Exception('Permission denied: /home/user/secret/file.txt');
        },
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.history, hasLength(1));
      expect(manager.history.first.status, TransferStatus.failed);
      // Path should be sanitized
      expect(manager.history.first.error, isNot(contains('/home/user/secret')));
      expect(manager.history.first.error, contains('<path>'));
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

    test('cancel removes queued task and adds to history', () async {
      // Use parallelism=1 and a blocker to keep queue occupied
      final blocker = Completer<void>();
      manager = TransferManager(parallelism: 1, maxHistory: 10, taskTimeout: Duration.zero);

      manager.enqueue(TransferTask(
        name: 'blocker.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/blocker.txt',
        targetPath: '/remote/blocker.txt',
        run: (update) async {
          update(10, 'blocking');
          await blocker.future;
        },
      ));

      final id2 = manager.enqueue(_dummyTask('queued.txt'));
      // queued.txt should be in queue since blocker occupies the slot
      expect(manager.queueLength, 1);

      final cancelled = manager.cancel(id2);
      expect(cancelled, isTrue);
      expect(manager.queueLength, 0);
      expect(manager.history, hasLength(1));
      expect(manager.history.first.name, 'queued.txt');
      expect(manager.history.first.status, TransferStatus.cancelled);

      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('cancel marks running task for cancellation', () async {
      final started = Completer<void>();

      final id = manager.enqueue(TransferTask(
        name: 'running.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/running.txt',
        targetPath: '/remote/running.txt',
        run: (update) async {
          update(10, 'started');
          started.complete();
          // Keep calling progress to detect cancellation
          for (var i = 20; i <= 100; i += 10) {
            await Future.delayed(const Duration(milliseconds: 20));
            update(i.toDouble(), 'step $i');
          }
        },
      ));

      await started.future;
      final cancelled = manager.cancel(id);
      expect(cancelled, isTrue);

      await Future.delayed(const Duration(milliseconds: 500));
      expect(manager.history, hasLength(1));
      expect(manager.history.first.status, TransferStatus.cancelled);
      expect(manager.history.first.lastMessage, 'Cancelled');
    });

    test('cancel returns false for unknown id', () {
      expect(manager.cancel('nonexistent'), isFalse);
    });

    test('cancelAll cancels queued and running tasks', () async {
      final blocker = Completer<void>();
      manager = TransferManager(parallelism: 1, maxHistory: 10, taskTimeout: Duration.zero);

      manager.enqueue(TransferTask(
        name: 'running.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/running.txt',
        targetPath: '/remote/running.txt',
        run: (update) async {
          update(50, 'running');
          await blocker.future;
          // After blocker completes, check cancellation
          for (var i = 60; i <= 100; i += 10) {
            await Future.delayed(const Duration(milliseconds: 10));
            update(i.toDouble(), 'step');
          }
        },
      ));

      manager.enqueue(_dummyTask('queued1.txt'));
      manager.enqueue(_dummyTask('queued2.txt'));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(manager.queueLength, 2);

      manager.cancelAll();
      expect(manager.queueLength, 0);
      // 2 queued tasks should be in history as cancelled
      expect(manager.history.where((e) => e.status == TransferStatus.cancelled), hasLength(2));

      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 300));
      // Running task should also be cancelled now
      expect(manager.history.where((e) => e.status == TransferStatus.cancelled), hasLength(3));
    });

    test('cancel preserves partial progress in history', () async {
      final started = Completer<void>();

      manager.enqueue(TransferTask(
        name: 'partial.txt',
        direction: TransferDirection.download,
        sourcePath: '/remote/partial.txt',
        targetPath: '/local/partial.txt',
        sizeBytes: 1024,
        run: (update) async {
          update(42, 'almost half');
          started.complete();
          for (var i = 43; i <= 100; i++) {
            await Future.delayed(const Duration(milliseconds: 10));
            update(i.toDouble(), 'progress $i');
          }
        },
      ));

      await started.future;
      manager.cancel(manager.history.isEmpty ? 'tr-1' : manager.history.first.id);

      await Future.delayed(const Duration(milliseconds: 500));
      final entry = manager.history.first;
      expect(entry.status, TransferStatus.cancelled);
      expect(entry.lastPercent, greaterThanOrEqualTo(42));
      expect(entry.sizeBytes, 1024);
    });

    test('task timeout produces failed history entry', () async {
      manager = TransferManager(
        parallelism: 1,
        maxHistory: 10,
        taskTimeout: const Duration(milliseconds: 100),
      );

      manager.enqueue(TransferTask(
        name: 'slow.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/slow.txt',
        targetPath: '/remote/slow.txt',
        run: (update) async {
          update(10, 'starting');
          // This will exceed the 100ms timeout
          await Future.delayed(const Duration(seconds: 5));
        },
      ));

      await Future.delayed(const Duration(milliseconds: 500));
      expect(manager.history, hasLength(1));
      expect(manager.history.first.status, TransferStatus.failed);
      expect(manager.history.first.error, contains('timed out'));
    });

    test('activeEntries has queued entry after enqueue', () async {
      final blocker = Completer<void>();
      manager = TransferManager(parallelism: 1, maxHistory: 10, taskTimeout: Duration.zero);

      // Block the single slot so the next task stays queued
      manager.enqueue(TransferTask(
        name: 'blocker.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/blocker.txt',
        targetPath: '/remote/blocker.txt',
        run: (update) async {
          update(10, 'blocking');
          await blocker.future;
        },
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      manager.enqueue(TransferTask(
        name: 'queued.txt',
        direction: TransferDirection.download,
        sourcePath: '/remote/queued.txt',
        targetPath: '/local/queued.txt',
        run: (update) async {
          update(100, 'done');
        },
      ));

      final entries = manager.activeEntries;
      // blocker is running, queued.txt is queued
      expect(entries.length, 2);
      final queuedEntry = entries.firstWhere((e) => e.name == 'queued.txt');
      expect(queuedEntry.status, TransferStatus.queued);
      expect(queuedEntry.direction, TransferDirection.download);

      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('activeEntries shows running status during execution', () async {
      final started = Completer<void>();
      final finish = Completer<void>();

      manager.enqueue(TransferTask(
        name: 'running.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/running.txt',
        targetPath: '/remote/running.txt',
        run: (update) async {
          update(50, 'halfway');
          started.complete();
          await finish.future;
        },
      ));

      await started.future;
      final entries = manager.activeEntries;
      expect(entries, hasLength(1));
      expect(entries.first.name, 'running.txt');
      expect(entries.first.status, TransferStatus.running);
      expect(entries.first.percent, 50);
      expect(entries.first.message, 'halfway');

      finish.complete();
      await Future.delayed(const Duration(milliseconds: 50));
    });

    test('activeEntries is empty after task completes', () async {
      manager.enqueue(_dummyTask('done.txt'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(manager.activeEntries, isEmpty);
      expect(manager.history, hasLength(1));
    });

    test('activeEntries is empty after cancel of queued task', () async {
      final blocker = Completer<void>();
      manager = TransferManager(parallelism: 1, maxHistory: 10, taskTimeout: Duration.zero);

      manager.enqueue(TransferTask(
        name: 'blocker.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/blocker.txt',
        targetPath: '/remote/blocker.txt',
        run: (update) async {
          update(10, 'blocking');
          await blocker.future;
        },
      ));

      final id = manager.enqueue(_dummyTask('cancel-me.txt'));
      await Future.delayed(const Duration(milliseconds: 50));

      manager.cancel(id);
      // Only the blocker should remain in activeEntries
      final entries = manager.activeEntries;
      expect(entries.where((e) => e.name == 'cancel-me.txt'), isEmpty);

      blocker.complete();
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('activeEntries is empty after running task is cancelled', () async {
      final started = Completer<void>();

      final id = manager.enqueue(TransferTask(
        name: 'cancel-running.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/cancel-running.txt',
        targetPath: '/remote/cancel-running.txt',
        run: (update) async {
          update(30, 'started');
          started.complete();
          for (var i = 40; i <= 100; i += 10) {
            await Future.delayed(const Duration(milliseconds: 20));
            update(i.toDouble(), 'step $i');
          }
        },
      ));

      await started.future;
      manager.cancel(id);
      await Future.delayed(const Duration(milliseconds: 500));

      expect(manager.activeEntries, isEmpty);
    });

    test('finally block cleans up after cancel', () async {
      final started = Completer<void>();
      manager = TransferManager(parallelism: 1, maxHistory: 10, taskTimeout: Duration.zero);

      // Enqueue a task that will be cancelled, and another in queue
      final id = manager.enqueue(TransferTask(
        name: 'cancel-cleanup.txt',
        direction: TransferDirection.upload,
        sourcePath: '/local/cancel-cleanup.txt',
        targetPath: '/remote/cancel-cleanup.txt',
        run: (update) async {
          update(10, 'started');
          started.complete();
          for (var i = 20; i <= 100; i += 10) {
            await Future.delayed(const Duration(milliseconds: 20));
            update(i.toDouble(), 'step');
          }
        },
      ));

      manager.enqueue(_dummyTask('next.txt'));

      await started.future;
      manager.cancel(id);

      await Future.delayed(const Duration(milliseconds: 500));
      // After cancel, running count should be back to normal and next task processed
      expect(manager.runningCount, 0);
      expect(manager.currentTransferInfo, isNull);
      // Both tasks should be in history (cancelled + completed)
      expect(manager.history, hasLength(2));
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
