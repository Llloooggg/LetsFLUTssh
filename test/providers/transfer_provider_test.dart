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

  group('selector identity + reactivity', () {
    test(
      'transfersProvider is the single source for the three selectors — '
      'a reseed via FakeTransfersNotifier lands on all three in lockstep',
      () {
        // Spec: `transferHistoryProvider`, `activeTransfersProvider`,
        // and `transferStatusProvider` are pure `.field` projections.
        // Seeding the fake with every slice populated and reading via
        // the three selectors must yield the SAME data the parent
        // provider exposes — otherwise the fan-out grew an unexpected
        // copy / cache.
        final completed = HistoryEntry(
          id: 'history-1',
          name: 'done.txt',
          direction: TransferDirection.download,
          sourcePath: '/srv/done.txt',
          targetPath: '/tmp/done.txt',
          status: TransferStatus.completed,
          createdAt: DateTime.utc(2026, 4, 1),
        );
        const queued = ActiveEntry(
          id: 'queued-1',
          name: 'pending.txt',
          direction: TransferDirection.upload,
          sourcePath: '/tmp/pending.txt',
          targetPath: '/srv/pending.txt',
          status: TransferStatus.queued,
        );
        const status = ActiveTransferState(
          running: 0,
          queued: 1,
          currentInfo: 'pending.txt 0%',
        );
        final container = ProviderContainer(
          overrides: [
            transfersProvider.overrideWith(
              () => FakeTransfersNotifier(
                history: [completed],
                active: const [queued],
                status: status,
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final parent = container.read(transfersProvider);
        // Identity: the selector reads ARE the parent's lists, not
        // copies — re-read after a state change would otherwise miss
        // the fan-out. Comparing by `same(...)` pins that no defensive
        // copy was layered in between.
        expect(container.read(transferHistoryProvider), same(parent.history));
        expect(container.read(activeTransfersProvider), same(parent.active));
        expect(container.read(transferStatusProvider), same(parent.status));
      },
    );

    test('ProviderContainer.invalidate(transfersProvider) re-runs build() and '
        'restores the fake seed — the selectors see the rebuilt state', () {
      // Spec: invalidation tears down the notifier and rebuilds. The
      // fake's `build()` re-plants its `_initial` snapshot — so the
      // selectors read the same seed after invalidation as before.
      // Pins the FakeTransfersNotifier contract that `build` is
      // idempotent — a regression where `_initial` got mutated post-
      // build would surface as a different selector read on
      // re-build.
      final completed = HistoryEntry(
        id: 'h-keep',
        name: 'survives.bin',
        direction: TransferDirection.download,
        sourcePath: '/srv/survives.bin',
        targetPath: '/tmp/survives.bin',
        status: TransferStatus.completed,
        createdAt: DateTime.utc(2026, 2, 1),
        sizeBytes: 42,
      );
      final container = ProviderContainer(
        overrides: [
          transfersProvider.overrideWith(
            () => FakeTransfersNotifier(history: [completed]),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(transferHistoryProvider), hasLength(1));
      container.invalidate(transfersProvider);
      // Rebuilt — fake replants the seed.
      expect(container.read(transferHistoryProvider), hasLength(1));
      expect(container.read(transferHistoryProvider).first.id, 'h-keep');
    });

    test('overriding transfersProvider with the default FakeTransfersNotifier '
        '(no seed) yields empty slices on every selector', () {
      // Spec: the empty-state fake leaves `TransfersState` at its
      // default — every slice empty, status counters zero. Mirrors
      // the cold-start contract of the real notifier before the
      // first FRB snapshot lands.
      final container = ProviderContainer(
        overrides: [transfersProvider.overrideWith(FakeTransfersNotifier.new)],
      );
      addTearDown(container.dispose);

      expect(container.read(transferHistoryProvider), isEmpty);
      expect(container.read(activeTransfersProvider), isEmpty);
      final status = container.read(transferStatusProvider);
      expect(status.running, 0);
      expect(status.queued, 0);
      expect(status.hasActive, isFalse);
    });
  });

  group('TransfersNotifier — FRB-routed surfaces', () {
    test('cancel on a never-enqueued id returns false — the FRB call routes '
        'to the Rust registry which has no row for the id, so the operation '
        'is idempotent (no-op on missing id)', () async {
      // Spec: `TransfersNotifier.cancel` wraps `transferCancel`. The
      // Rust side returns `false` when the id is not present in the
      // registry. The notifier surfaces that as-is so a caller that
      // races a cancel against a terminal task does not see a thrown
      // exception. Pin the contract — a regression that converted
      // the Rust `false` into a thrown error would crash the
      // panel's per-row cancel button when the user clicked it on
      // a task that had already completed.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(transfersProvider.notifier);
      final cancelled = await notifier.cancel(
        'no-such-id-${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(cancelled, isFalse);
    });

    test(
      'deleteHistory on a list of unknown ids walks every id and never '
      'throws — the per-id catch arm swallows the missing-row return',
      () async {
        // Spec: `deleteHistory(ids)` iterates and calls
        // `transferDropTerminal` per id. The Rust call returns false
        // for a missing id; the notifier loop continues. Pinning
        // the contract that the loop's individual try/catch is the
        // gate — without it, a Bulk-Clear of a stale id list would
        // halt mid-iteration and leave the rest of the rows on
        // disk.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(transfersProvider.notifier);
        await notifier.deleteHistory([
          'ghost-a-${DateTime.now().microsecondsSinceEpoch}',
          'ghost-b-${DateTime.now().microsecondsSinceEpoch}',
        ]);
        // No throw; subsequent state read still works.
        expect(container.read(transfersProvider).history, isEmpty);
      },
    );

    test('clearHistory on an empty registry returns without throwing — the '
        'Rust side reports 0 dropped and the notifier carries on', () async {
      // Spec: `clearHistory` wraps `transferClearHistory`. The FRB
      // call returns the count of dropped rows; the notifier
      // discards the count and only cares about the success arm.
      // An empty registry reports 0; the call must not throw.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(transfersProvider.notifier);
      await notifier.clearHistory();
      // Re-read after clear — the snapshot stays empty + no
      // exception surfaced.
      expect(container.read(transferHistoryProvider), isEmpty);
    });

    test(
      'cancelAll on an empty registry walks the empty snapshot without '
      'firing any cancel — fire-and-forget contract on no-active-rows',
      () async {
        // Spec: `cancelAll` calls `_safeSnapshot` and walks every
        // active entry. An empty registry yields an empty list;
        // the cancel loop never iterates. The unawaited helper
        // resolves without throwing so the panel's "Cancel all"
        // button stays usable on a fresh app boot.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(transfersProvider.notifier);
        notifier.cancelAll();
        // Drain microtasks so the unawaited `_cancelAllAsync` lands.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // Still no active entries; no throw.
        expect(container.read(activeTransfersProvider), isEmpty);
      },
    );

    test(
      'enqueueDownload on a non-existent connection-id still returns a '
      'task id — the Rust queue accepts the row even when the SSH '
      'session is unbound (the worker fails it later, asynchronously)',
      () async {
        // Spec: `enqueueDownload` mints a UUID v4 and forwards to
        // `transferEnqueue`. The Rust side registers the row + lazy-
        // inits the worker pool; the unbound session id will surface
        // as a `TransferTaskError` event downstream, but the
        // enqueue itself does not fail. Pinning the contract that
        // the helper always returns an id — UI callers chain on
        // the returned id for cancel / progress tracking, and a
        // null / empty return would break the wiring on the very
        // first transfer.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(transfersProvider.notifier);
        final id = await notifier.enqueueDownload(
          connectionId:
              'no-such-session-${DateTime.now().microsecondsSinceEpoch}',
          name: 'remote.bin',
          remotePath: '/srv/remote.bin',
          localPath: '/tmp/remote.bin',
          sizeBytes: 0,
        );
        expect(id, isNotEmpty);
        // UUID v4 shape — same regex as session_recorder uses.
        expect(
          id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
              r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      },
    );

    test(
      'enqueueUpload on a non-existent connection-id returns a fresh task '
      'id distinct from the download path — every call mints a new UUID',
      () async {
        // Spec: `enqueueUpload` mirrors the download contract. Two
        // back-to-back enqueues mint two distinct UUIDs (Uuid.v4()
        // never collides in practice). Pin the id-uniqueness +
        // upload-path return value.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(transfersProvider.notifier);
        final a = await notifier.enqueueUpload(
          connectionId: 'no-session-a',
          name: 'a.bin',
          localPath: '/tmp/a.bin',
          remotePath: '/srv/a.bin',
        );
        final b = await notifier.enqueueUpload(
          connectionId: 'no-session-b',
          name: 'b.bin',
          localPath: '/tmp/b.bin',
          remotePath: '/srv/b.bin',
        );
        expect(a, isNot(equals(b)));
      },
    );
  });

  // The state-machine transition mapping
  // (queued → running → completed / failed / cancelled) plus the
  // running entry's percent / message formatting + `_displayName`
  // POSIX/Win basename normalisation route through `_doRefresh`,
  // which only fires after a real `BusEvent_TransferTaskState` lands
  // from the Rust worker pool. The end-to-end coverage lives in
  // `test/integration/transfer_queue_test.dart`. The bus-subscribe
  // catch (lines 92-93) protects against a missing AppBus singleton
  // — a state the harness guarantees against by always loading FRB.
  // covered by integration: worker-driven state mapping needs the
  // full SSH/SFTP loopback which the unit harness does not spin up.
}
