import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

void main() {
  group('ActiveTransferState', () {
    test('defaults', () {
      const state = ActiveTransferState();
      expect(state.running, 0);
      expect(state.queued, 0);
      expect(state.currentInfo, isNull);
      expect(state.hasActive, isFalse);
    });

    test('hasActive when running > 0', () {
      const state = ActiveTransferState(running: 1);
      expect(state.hasActive, isTrue);
    });

    test('hasActive when queued > 0', () {
      const state = ActiveTransferState(queued: 2);
      expect(state.hasActive, isTrue);
    });

    test('stores currentInfo', () {
      const state = ActiveTransferState(
        running: 1,
        queued: 0,
        currentInfo: 'file.txt 50%',
      );
      expect(state.currentInfo, 'file.txt 50%');
    });
  });

  group('transfer providers', () {
    test('transferManagerProvider returns TransferManager', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final manager = container.read(transferManagerProvider);
      expect(manager, isA<TransferManager>());
      expect(manager.history, isEmpty);
      expect(manager.queueLength, 0);
      expect(manager.runningCount, 0);
    });

    test('transferHistoryProvider yields empty list initially', () async {
      final container = ProviderContainer();

      // Subscribe to force stream to start
      final sub = container.listen(transferHistoryProvider, (_, _) {});

      // Wait for initial emission
      await container.read(transferHistoryProvider.future);
      final history = container.read(transferHistoryProvider).value;
      expect(history, isEmpty);

      sub.close();
      container.dispose();
    });

    test('transferStatusProvider yields idle state initially', () async {
      final container = ProviderContainer();

      final sub = container.listen(transferStatusProvider, (_, _) {});

      final status = await container.read(transferStatusProvider.future);
      expect(status.running, 0);
      expect(status.queued, 0);
      expect(status.hasActive, isFalse);

      sub.close();
      container.dispose();
    });

    test('transferManagerProvider disposes on container dispose', () {
      final container = ProviderContainer();
      final manager = container.read(transferManagerProvider);
      expect(manager, isNotNull);
      container.dispose();
    });

    test('transferStatusProvider updates after enqueue completes', () async {
      final container = ProviderContainer();

      final manager = container.read(transferManagerProvider);

      // Subscribe to streams to force providers to listen
      final historySubscription = container.listen(
        transferHistoryProvider,
        (_, _) {},
      );
      final statusSubscription = container.listen(
        transferStatusProvider,
        (_, _) {},
      );

      // Wait for initial values
      await container.read(transferHistoryProvider.future);
      await container.read(transferStatusProvider.future);

      // Enqueue a task that takes a moment
      manager.enqueue(
        TransferTask(
          name: 'status_test.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/status_test.txt',
          targetPath: '/remote/status_test.txt',
          run: (onProgress) async {
            await Future.delayed(const Duration(milliseconds: 50));
          },
        ),
      );

      // Wait for task to complete and streams to emit
      await Future.delayed(const Duration(milliseconds: 300));

      final status = await container.read(transferStatusProvider.future);
      expect(status.running, 0);
      expect(status.queued, 0);

      final history = await container.read(transferHistoryProvider.future);
      expect(history, isNotEmpty);
      expect(history.first.name, 'status_test.txt');

      historySubscription.close();
      statusSubscription.close();
      container.dispose();
    });

    test('transferHistoryProvider updates after enqueue completes', () async {
      final container = ProviderContainer();

      // Subscribe before enqueue
      final sub = container.listen(transferHistoryProvider, (_, _) {});
      await container.read(transferHistoryProvider.future);

      final manager = container.read(transferManagerProvider);

      manager.enqueue(
        TransferTask(
          name: 'test.txt',
          direction: TransferDirection.upload,
          sourcePath: '/local/test.txt',
          targetPath: '/remote/test.txt',
          run: (onProgress) async {},
        ),
      );

      // Wait for task to complete
      await Future.delayed(const Duration(milliseconds: 100));

      final history = await container.read(transferHistoryProvider.future);
      expect(history, isNotEmpty);
      expect(history.first.name, 'test.txt');
      expect(history.first.status, TransferStatus.completed);

      sub.close();
      container.dispose();
    });
  });
}
