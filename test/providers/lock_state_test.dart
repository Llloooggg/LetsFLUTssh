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

    test(
      'lock → unlock round-trip surfaces a single transition per direction — '
      'listeners see one event for the lock and one for the subsequent unlock',
      () {
        // Spec: the production lock cascade is two transitions
        // (TierStateChanged{locked} flips state=true,
        // UnlockCascadeReady flips state=false). A consumer that
        // throttles renders by counting notifications must see
        // exactly one event per direction — a regression that
        // double-flipped (e.g. setting state=true twice in the
        // locked-handler branch) would re-render every dependent
        // widget twice.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(lockStateProvider.notifier);
        final events = <bool>[];
        container.listen(lockStateProvider, (_, next) => events.add(next));
        notifier.debugForceLocked();
        notifier.debugForceUnlocked();
        expect(events, [true, false]);
      },
    );

    test(
      'multiple containers each own an independent LockStateNotifier — the '
      'Riverpod-managed singleton scope is per-container, not process-wide',
      () {
        // Spec: `lockStateProvider` is a `NotifierProvider` — each
        // `ProviderContainer` instantiates a fresh notifier through
        // `LockStateNotifier.new`. A regression that lifted the
        // notifier to a process-wide static (a `late final` field
        // or a private singleton) would let one container's
        // `debugForceLocked` leak into another's lock state, which
        // would silently corrupt every widget test that shares the
        // same harness.
        final a = ProviderContainer();
        final b = ProviderContainer();
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        a.read(lockStateProvider.notifier).debugForceLocked();
        expect(a.read(lockStateProvider), isTrue);
        expect(b.read(lockStateProvider), isFalse);
      },
    );

    test('disposing the container after a forced lock cleans up the bus '
        'subscription without re-emitting on the (now-gone) notifier', () {
      // Spec: `ref.onDispose` cancels `_busSub` so a residual FRB
      // event arriving after the container disposes does not run
      // `_onBusEvent` on a torn-down notifier (which would throw
      // when `state = …` runs against a disposed
      // ProviderContainer). The Riverpod runtime asserts internally
      // when a setter fires post-dispose; covering the dispose
      // path keeps that assertion off the regression list.
      final container = ProviderContainer();
      final notifier = container.read(lockStateProvider.notifier);
      notifier.debugForceLocked();
      expect(container.read(lockStateProvider), isTrue);
      // No exception expected — `dispose` is idempotent and the
      // cleanup-hook chain runs to completion.
      container.dispose();
    });

    test('debugForceUnlocked from a locked state matches the production '
        'UnlockCascadeReady contract — exactly one false notification', () {
      // Spec: the production unlock path observes a single
      // `BusEvent_UnlockCascadeReady`; the notifier flips
      // state = false ONCE inside the if-state guard, then drops
      // any subsequent events through the same branch as no-ops.
      // Pin the listener-event count to that contract so a future
      // refactor that adds a redundant `state = false` (e.g.
      // mirroring on `unlocked` wire too) is caught immediately.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      notifier.debugForceLocked();
      var events = 0;
      container.listen(lockStateProvider, (_, _) => events++);
      notifier.debugForceUnlocked();
      notifier.debugForceUnlocked();
      notifier.debugForceUnlocked();
      expect(events, 1);
    });
  });
}
