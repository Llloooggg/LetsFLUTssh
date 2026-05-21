import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/lock_state.dart';

void main() {
  group('LockStateNotifier', () {
    test('starts unlocked', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(lockStateProvider), isFalse);
    });

    test('debugForceLocked flips to true', () {
      // The production lock path drives through
      // `tierMachineDispatch(LockRequested)` → bus event → notifier;
      // flutter_test contexts don't load the FRB native lib so the
      // bus never delivers. The test seam stages a locked state
      // directly so the rest of the contract (idempotence, unlock
      // flip) is exercisable without a fake bus stream.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(lockStateProvider.notifier).debugForceLocked();
      expect(container.read(lockStateProvider), isTrue);
    });

    test('debugForceUnlocked flips back to false', () {
      // Mirrors the production path where Rust's
      // `run_post_unlock_cascade` publishes `UnlockCascadeReady`;
      // `LockStateNotifier._onBusEvent` flips `state = false`. The
      // test seam stages the same transition without a live FRB bus.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      notifier.debugForceLocked();
      notifier.debugForceUnlocked();
      expect(container.read(lockStateProvider), isFalse);
    });

    test('debugForceLocked is idempotent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      var events = 0;
      container.listen(lockStateProvider, (_, _) => events++);
      notifier.debugForceLocked();
      notifier.debugForceLocked();
      notifier.debugForceLocked();
      expect(events, 1);
    });

    test('debugForceUnlocked on an unlocked notifier is a no-op', () {
      // Matches the production `UnlockCascadeReady` handler: the
      // overlay flip short-circuits when already off so a duplicate
      // event from a retry / reconnect path doesn't re-notify
      // listeners.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      var events = 0;
      container.listen(lockStateProvider, (_, _) => events++);
      notifier.debugForceUnlocked();
      notifier.debugForceUnlocked();
      expect(events, 0);
      expect(container.read(lockStateProvider), isFalse);
    });
  });
}
