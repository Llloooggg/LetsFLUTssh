/// Coverage for [AppBus] — the Dart-side façade over the FRB bus.
///
/// The crucial contract the cold-start path leans on: `subscribe()`
/// must NOT throw before `RustLib.init` has run, the returned stream
/// must be a broadcast pipe regardless of FRB readiness, and a
/// later `retryFrbSubscriptions()` (called from
/// `_LetsFLUTsshAppState._bootstrap` immediately after Rust core
/// boot) must promote any cached topic to a live FRB subscription
/// without re-entering the throwy paths.
///
/// The pre-FRB tests run first so RustLib stays uninitialised; the
/// post-FRB group then loads the workspace dylib and asserts the
/// promotion works without exception. Once FRB is up in a process
/// it can't be turned back off — flutter_test runs each file in its
/// own isolate, so this ordering is stable across the suite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/bus/app_bus.dart';
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBus singleton', () {
    test('AppBus.instance returns the same singleton across calls', () {
      expect(identical(AppBus.instance, AppBus.instance), isTrue);
    });
  });

  group('cold-start safety — RustLib not yet initialized', () {
    setUp(() {
      // Sanity: this group only means anything when FRB has not yet
      // been loaded. Skip if a sibling test bootstrapped it earlier
      // in the file (none should, but guard against accidental
      // re-ordering).
      if (RustLib.instance.initialized) {
        fail(
          'cold-start group ran with RustLib already initialised — test '
          'ordering invariant broken. Pre-FRB tests must run before any '
          '`requireFrbLoaded` call.',
        );
      }
    });

    test('subscribe does not throw before RustLib.init', () {
      // The whole reason `_SharedTopic.ensureFrbSub` early-outs on
      // `!RustLib.instance.initialized` instead of just letting the
      // FRB call throw: a Riverpod `Notifier.build()` that mounts
      // during the first runApp frame would otherwise crash the
      // widget tree before the splash gets a chance to paint.
      expect(
        () => AppBus.instance.subscribe(rust_bus.BusTopic.connection),
        returnsNormally,
      );
    });

    test('subscribe returns a broadcast stream even pre-FRB', () {
      final stream = AppBus.instance.subscribe(rust_bus.BusTopic.recorder);
      expect(stream.isBroadcast, isTrue);
    });

    test('subscribe is idempotent on the same topic — a listener-able stream '
        'every call', () async {
      final a = AppBus.instance.subscribe(rust_bus.BusTopic.transfer);
      final b = AppBus.instance.subscribe(rust_bus.BusTopic.transfer);
      // Both expose the same underlying broadcast controller — we
      // can't assert `identical` on the wrapper streams (broadcast
      // streams synthesise a new view each access), but listening
      // to both must succeed without "stream already listened to".
      final subA = a.listen((_) {});
      final subB = b.listen((_) {});
      addTearDown(() {
        subA.cancel();
        subB.cancel();
      });
    });

    test('retryFrbSubscriptions does not throw before RustLib.init', () {
      AppBus.instance.subscribe(rust_bus.BusTopic.knownHosts);
      expect(AppBus.instance.retryFrbSubscriptions, returnsNormally);
    });

    test(
      'subscribeConnection returns a broadcast stream usable pre-FRB',
      () async {
        final stream = AppBus.instance.subscribeConnection('conn-cold-1');
        expect(stream.isBroadcast, isTrue);
        // Listening must not throw — the underlying chain is
        // subscribe → .where → broadcast. Pre-FRB the source emits
        // nothing, but the listen-side contract still holds.
        final sub = stream.listen((_) {});
        addTearDown(sub.cancel);
      },
    );

    test(
      'subscribeRecorder returns a broadcast stream usable pre-FRB',
      () async {
        final stream = AppBus.instance.subscribeRecorder('rec-cold-1');
        expect(stream.isBroadcast, isTrue);
        final sub = stream.listen((_) {});
        addTearDown(sub.cancel);
      },
    );
  });

  group('post-FRB promotion — RustLib loaded', () {
    setUpAll(requireFrbLoaded);

    test('subscribe still returns a broadcast stream after FRB load', () {
      final stream = AppBus.instance.subscribe(rust_bus.BusTopic.connection);
      expect(stream.isBroadcast, isTrue);
    });

    test('retryFrbSubscriptions does not throw after FRB load', () {
      // The cold-start subscriptions cached above (connection, recorder,
      // transferQueue, knownHosts) all need to promote to live FRB
      // streams. The method itself is fire-and-forget — the meaningful
      // assertion is that walking the cache and re-entering ensureFrbSub
      // doesn't throw on any of them.
      expect(AppBus.instance.retryFrbSubscriptions, returnsNormally);
    });

    test('a fresh subscribe after FRB init opens a live FRB pipe', () async {
      // BusTopic.tier wasn't touched by the cold-start group, so
      // this exercises the "first subscribe() lands post-FRB-init"
      // path that production hits when a feature mounts late (e.g.
      // a settings screen pushed from main).
      final stream = AppBus.instance.subscribe(rust_bus.BusTopic.tier);
      expect(stream.isBroadcast, isTrue);
      final sub = stream.listen((_) {});
      addTearDown(sub.cancel);
    });
  });
}
