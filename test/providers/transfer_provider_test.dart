/// Coverage for [TransfersState] + [ActiveTransferState] data classes
/// and the selector providers layered over [transfersProvider].
///
/// The notifier's bus + FRB enqueue / cancel pipeline runs end-to-end
/// in `test/integration/transfer_queue_test.dart`; what's testable
/// without a real Rust transfer queue is the pure data shape and the
/// `ref.watch` selectors that the UI panel header reads from.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

import '../helpers/fake_transfers_notifier.dart';
import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('ActiveTransferState', () {
    test('default constructor sets running=0, queued=0, currentInfo=null', () {
      const state = ActiveTransferState();
      expect(state.running, 0);
      expect(state.queued, 0);
      expect(state.currentInfo, isNull);
    });

    test('hasActive is false when both running and queued are zero', () {
      expect(const ActiveTransferState().hasActive, isFalse);
    });

    test('hasActive is true when running > 0', () {
      expect(const ActiveTransferState(running: 1).hasActive, isTrue);
    });

    test('hasActive is true when queued > 0', () {
      expect(const ActiveTransferState(queued: 1).hasActive, isTrue);
    });

    test('hasActive is true when both running and queued > 0', () {
      expect(
        const ActiveTransferState(running: 2, queued: 3).hasActive,
        isTrue,
      );
    });

    test('currentInfo string is preserved', () {
      const state = ActiveTransferState(running: 1, currentInfo: '3 of 5');
      expect(state.currentInfo, '3 of 5');
    });
  });

  group('TransfersState', () {
    test('default constructor has empty history + empty active', () {
      const state = TransfersState();
      expect(state.history, isEmpty);
      expect(state.active, isEmpty);
      expect(state.status.hasActive, isFalse);
    });

    test('explicit constructor preserves all three fields', () {
      const status = ActiveTransferState(running: 1, queued: 2);
      const state = TransfersState(status: status);
      expect(state.status.running, 1);
      expect(state.status.queued, 2);
    });
  });

  group('transfersProvider — initial state', () {
    test('build() returns an empty TransfersState', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(transfersProvider);
      // The notifier subscribes to the bus on build() but does not
      // synchronously populate history/active — that lands on the
      // first event or the explicit refresh call.
      expect(state.history, isEmpty);
      expect(state.active, isEmpty);
      expect(state.status.running, 0);
      expect(state.status.queued, 0);
    });
  });

  group('selector providers', () {
    test('transferHistoryProvider reads history from transfersProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Default state → empty history. The selector is a thin
      // `ref.watch(transfersProvider).history` projection; the
      // assertion verifies the wiring is intact, not the data
      // shape (which is already covered above).
      expect(container.read(transferHistoryProvider), isEmpty);
    });

    test('activeTransfersProvider reads active from transfersProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeTransfersProvider), isEmpty);
    });

    test('transferStatusProvider reads status from transfersProvider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final status = container.read(transferStatusProvider);
      expect(status.hasActive, isFalse);
      expect(status.running, 0);
      expect(status.queued, 0);
    });
  });

  group('FakeTransfersNotifier — selectors track seeded state', () {
    test(
      'history seed lands on both transfersProvider.history and selector',
      () {
        // Contract — the fake's `build()` plants the seeded
        // `TransfersState` so widget tests can render the panel
        // against a known history without a Rust queue. The selector
        // provider is a thin `.history` projection — feeding the
        // fake a completed entry must show up on both reads.
        final completed = HistoryEntry(
          id: 'h1',
          name: 'a.bin',
          direction: TransferDirection.download,
          sourcePath: '/srv/a.bin',
          targetPath: '/tmp/a.bin',
          status: TransferStatus.completed,
          lastPercent: 100,
          lastMessage: 'Done',
          createdAt: DateTime.utc(2026, 1, 1),
          sizeBytes: 128,
        );
        final container = ProviderContainer(
          overrides: [
            transfersProvider.overrideWith(
              () => FakeTransfersNotifier(history: [completed]),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(transfersProvider).history, hasLength(1));
        expect(container.read(transferHistoryProvider), hasLength(1));
        expect(container.read(transferHistoryProvider).first.id, 'h1');
      },
    );

    test('active + status seed flow through to the panel-header providers', () {
      // Contract — `transferStatusProvider` is a `.status`
      // projection, and `activeTransfersProvider` is `.active`.
      // Seeding the fake with one running entry + a 1/0 status
      // must drive both selectors so the panel header (running
      // count) and the active list (per-row progress) stay in
      // lockstep.
      const running = ActiveEntry(
        id: 'a1',
        name: 'b.bin',
        direction: TransferDirection.upload,
        sourcePath: '/tmp/b.bin',
        targetPath: '/srv/b.bin',
        status: TransferStatus.running,
        percent: 42,
        message: '42/100',
      );
      const status = ActiveTransferState(
        running: 1,
        queued: 0,
        currentInfo: 'b.bin 42%',
      );
      final container = ProviderContainer(
        overrides: [
          transfersProvider.overrideWith(
            () =>
                FakeTransfersNotifier(active: const [running], status: status),
          ),
        ],
      );
      addTearDown(container.dispose);

      final activeList = container.read(activeTransfersProvider);
      expect(activeList, hasLength(1));
      expect(activeList.first.status, TransferStatus.running);

      final readStatus = container.read(transferStatusProvider);
      expect(readStatus.running, 1);
      expect(readStatus.queued, 0);
      expect(readStatus.hasActive, isTrue);
      expect(readStatus.currentInfo, 'b.bin 42%');
    });

    test(
      'clearHistory wipes history but preserves active + status snapshots',
      () async {
        // Contract — the real `clearHistory` only drops terminal
        // entries; in-flight transfers keep running. The fake mirrors
        // that: `state.history` empties, `state.active` and
        // `state.status` stay put. The selector providers reflect
        // the partial wipe.
        final completed = HistoryEntry(
          id: 'h-old',
          name: 'old.bin',
          direction: TransferDirection.download,
          sourcePath: '/srv/old.bin',
          targetPath: '/tmp/old.bin',
          status: TransferStatus.completed,
          createdAt: DateTime.utc(2026, 1, 1),
        );
        const running = ActiveEntry(
          id: 'a-running',
          name: 'live.bin',
          direction: TransferDirection.upload,
          sourcePath: '/tmp/live.bin',
          targetPath: '/srv/live.bin',
          status: TransferStatus.running,
          percent: 10,
        );
        const status = ActiveTransferState(running: 1);
        final notifier = FakeTransfersNotifier(
          history: [completed],
          active: const [running],
          status: status,
        );
        final container = ProviderContainer(
          overrides: [transfersProvider.overrideWith(() => notifier)],
        );
        addTearDown(container.dispose);

        // Trigger via the notifier handle the production UI uses.
        await container.read(transfersProvider.notifier).clearHistory();

        expect(notifier.clearHistoryCalls, 1);
        expect(container.read(transferHistoryProvider), isEmpty);
        // Active + status untouched — the running upload survives.
        expect(container.read(activeTransfersProvider), hasLength(1));
        expect(container.read(transferStatusProvider).running, 1);
      },
    );
  });

  // The notifier's FRB-deep enqueue / cancel / refresh pipeline
  // (`enqueueDownload`, `enqueueUpload`, `cancel`, `cancelAll`,
  // `_doRefresh`, `_safeSnapshot`, `_displayName`) requires a real
  // Rust transfer queue + a connected SFTP session — see
  // `test/integration/transfer_queue_test.dart` for the end-to-end
  // coverage. The state-machine transitions (queued → running →
  // completed/failed/cancelled) are property-tested on the Rust
  // side under `lfs_core::transfer`; the Dart side just mirrors
  // the snapshot stream produced there. covered by integration:
  // batch progress aggregation + cancel/retry semantics rely on
  // worker-pool scheduling that the Dart-side fake cannot fake
  // without re-implementing the Rust state machine.
}
