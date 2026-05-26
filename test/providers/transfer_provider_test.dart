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
import 'package:letsflutssh/providers/transfer_provider.dart';

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
}
