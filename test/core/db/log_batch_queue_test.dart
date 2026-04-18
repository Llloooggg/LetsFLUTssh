import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/log_batch_queue.dart';

void main() {
  group('LogBatchQueue', () {
    test('size trigger flushes at maxBatchSize', () async {
      final flushed = <List<int>>[];
      final queue = LogBatchQueue<int>(
        flush: (batch) async => flushed.add(batch),
        maxBatchSize: 3,
        flushInterval: const Duration(seconds: 30),
      );
      queue.add(1);
      queue.add(2);
      queue.add(3); // triggers size-based flush
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(flushed, [
        [1, 2, 3],
      ]);
      await queue.dispose();
    });

    test(
      'time trigger flushes on flushInterval when size cap unreached',
      () async {
        final flushed = <List<int>>[];
        final queue = LogBatchQueue<int>(
          flush: (batch) async => flushed.add(batch),
          maxBatchSize: 100,
          flushInterval: const Duration(milliseconds: 50),
        );
        queue.add(1);
        queue.add(2);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(flushed, [
          [1, 2],
        ]);
        await queue.dispose();
      },
    );

    test('flushNow drains the current batch immediately', () async {
      final flushed = <List<int>>[];
      final queue = LogBatchQueue<int>(
        flush: (batch) async => flushed.add(batch),
        maxBatchSize: 100,
        flushInterval: const Duration(seconds: 30),
      );
      queue.add(1);
      queue.add(2);
      await queue.flushNow();
      expect(flushed, [
        [1, 2],
      ]);
      await queue.dispose();
    });

    test('flush failure preserves the batch for retry', () async {
      var attempt = 0;
      final queue = LogBatchQueue<int>(
        flush: (batch) async {
          attempt++;
          if (attempt == 1) throw StateError('boom');
        },
        maxBatchSize: 100,
        flushInterval: const Duration(seconds: 30),
      );
      queue.add(1);
      queue.add(2);
      await expectLater(queue.flushNow(), throwsA(isA<StateError>()));
      expect(queue.length, 2);
      await queue.flushNow();
      expect(attempt, 2);
      expect(queue.length, 0);
      await queue.dispose();
    });

    test('dispose flushes pending events and ignores further adds', () async {
      final flushed = <List<int>>[];
      final queue = LogBatchQueue<int>(
        flush: (batch) async => flushed.add(batch),
        maxBatchSize: 100,
        flushInterval: const Duration(seconds: 30),
      );
      queue.add(1);
      await queue.dispose();
      queue.add(2); // ignored post-dispose
      expect(flushed, [
        [1],
      ]);
    });
  });
}
