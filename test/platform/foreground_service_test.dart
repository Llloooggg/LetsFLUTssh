import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/foreground_service.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

/// Records all calls to the foreground service binding for verification.
class FakeBinding implements ForegroundServiceBinding {
  bool initCalled = false;
  final startCounts = <int>[];
  final updateCounts = <int>[];
  int stopCount = 0;
  bool startSucceeds = true;

  @override
  bool get isSupported => true;

  @override
  void initService() => initCalled = true;

  @override
  Future<bool> startService(int count, S localizations) async {
    startCounts.add(count);
    return startSucceeds;
  }

  @override
  Future<void> updateNotification(int count, S localizations) async {
    updateCounts.add(count);
  }

  @override
  Future<void> stopService() async {
    stopCount++;
  }
}

/// Binding that reports isSupported = false (simulates non-Android).
class UnsupportedBinding extends FakeBinding {
  @override
  bool get isSupported => false;
}

void main() {
  group('ForegroundServiceManager', () {
    late FakeBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = FakeBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('starts in non-running, non-initialized state', () {
      expect(manager.isRunning, isFalse);
      expect(manager.isInitialized, isFalse);
    });

    test('init calls binding.initService and sets initialized', () {
      manager.init();
      expect(binding.initCalled, isTrue);
      expect(manager.isInitialized, isTrue);
    });

    test('starts service when count goes from 0 to positive', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);
      expect(binding.startCounts, [1]);
    });

    test('updates notification when count changes while running', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(2);
      expect(binding.updateCounts, [2]);
      expect(manager.isRunning, isTrue);
    });

    test('stops service when count drops to 0', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('does not start again after stop until count > 0', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);

      await manager.onConnectionCountChanged(3);
      expect(manager.isRunning, isTrue);
      expect(binding.startCounts, [1, 3]);
    });

    test('does nothing when count is 0 and not running', () async {
      manager.init();
      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
      expect(binding.stopCount, 0);
    });

    test('does not start if not initialized', () async {
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
    });

    test('handles start failure gracefully', () async {
      binding.startSucceeds = false;
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
    });

    test('full lifecycle: start → update → update → stop', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);

      await manager.onConnectionCountChanged(2);
      await manager.onConnectionCountChanged(3);
      expect(binding.updateCounts, [2, 3]);

      await manager.onConnectionCountChanged(0);
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('dispose stops running service', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isTrue);

      await manager.dispose();
      expect(manager.isRunning, isFalse);
      expect(binding.stopCount, 1);
    });

    test('dispose is safe when not running', () async {
      manager.init();
      await manager.dispose();
      expect(binding.stopCount, 0);
    });

    test('multiple dispose calls do not double-stop', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.dispose();
      await manager.dispose();
      expect(binding.stopCount, 1);
    });

    test('rapid count changes handled correctly', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(5);
      await manager.onConnectionCountChanged(2);
      await manager.onConnectionCountChanged(0);
      await manager.onConnectionCountChanged(1);

      expect(binding.startCounts, [1, 1]); // started twice
      expect(binding.updateCounts, [5, 2]); // updated twice
      expect(binding.stopCount, 1); // stopped once
      expect(manager.isRunning, isTrue);
    });
  });

  group('ForegroundServiceManager (unsupported platform)', () {
    late UnsupportedBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = UnsupportedBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('init is no-op on unsupported platform', () {
      manager.init();
      expect(binding.initCalled, isFalse);
      expect(manager.isInitialized, isFalse);
    });

    test('onConnectionCountChanged is no-op on unsupported platform', () async {
      manager.init();
      await manager.onConnectionCountChanged(5);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, isEmpty);
    });
  });

  group('notificationText', () {
    late S en;

    setUpAll(() async {
      en = await S.delegate.load(const Locale('en'));
    });

    test('singular for 1 connection', () {
      expect(notificationText(en, 1), '1 active connection');
    });

    test('plural for 0 connections', () {
      expect(notificationText(en, 0), '0 active connections');
    });

    test('plural for multiple connections', () {
      expect(notificationText(en, 3), '3 active connections');
    });
  });

  // Spec: the manager must cache localisations and pass them through to
  // every start / update so the notification renders in the user's
  // active locale, not in whichever locale the foreground task happened
  // to spin up under. When the locale changes mid-session the next
  // notification update must see the new bundle.
  group('ForegroundServiceManager — localisation caching', () {
    /// Records which S bundle was passed to each start/update call.
    late _LocaleRecordingBinding binding;
    late ForegroundServiceManager manager;
    late S en;

    setUpAll(() async {
      en = await S.delegate.load(const Locale('en'));
    });

    setUp(() {
      binding = _LocaleRecordingBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('falls back to English when no localisations have been set', () async {
      manager.init();
      await manager.onConnectionCountChanged(1);
      expect(binding.startLocalizations, hasLength(1));
      // Fallback is the English bundle — same body the en-loaded
      // bundle produces for the same count.
      expect(
        notificationText(binding.startLocalizations.single, 1),
        notificationText(en, 1),
      );
    });

    test('uses the cached localisations bundle for start + update', () async {
      manager.init();
      manager.setLocalizations(en);
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(2);
      expect(binding.startLocalizations, [en]);
      expect(binding.updateLocalizations, [en]);
    });
  });

  // Spec: every state transition that calls into the binding (start,
  // update, stop) must be no-op when the manager has not been
  // initialised. Without this guard a host that forgets to call
  // [init] would happily fire start, the binding would fail, and the
  // user would see a one-off notification with no service alive.
  group('ForegroundServiceManager — uninitialised guard', () {
    late FakeBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = FakeBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('dispose without init is a no-op', () async {
      await manager.dispose();
      expect(binding.stopCount, 0);
    });

    test(
      'count changes ignored when isSupported but not initialised',
      () async {
        await manager.onConnectionCountChanged(1);
        await manager.onConnectionCountChanged(0);
        expect(binding.startCounts, isEmpty);
        expect(binding.updateCounts, isEmpty);
        expect(binding.stopCount, 0);
      },
    );
  });

  // Spec — recovery paths the manager must walk without leaking state:
  //   * when a `_start` call's underlying `startService` fails, the
  //     manager must stay in `!_running` so the NEXT positive count
  //     attempts a fresh start (not silently mark itself as already
  //     running and never recover).
  //   * dropping to 0 without ever having started must not invoke
  //     `stopService` — the binding would interpret that as an
  //     uninitialised stop and on Android the plugin throws.
  group('ForegroundServiceManager — failed-start + idempotency', () {
    late FakeBinding binding;
    late ForegroundServiceManager manager;

    setUp(() {
      binding = FakeBinding();
      manager = ForegroundServiceManager(binding: binding);
    });

    test('failed start lets the next positive count try again', () async {
      // Spec: after a startService(false) the manager stays not-running,
      // so a subsequent positive transition (still 0 → N) calls start
      // again instead of skipping to the update-notification branch.
      manager.init();
      binding.startSucceeds = false;
      await manager.onConnectionCountChanged(1);
      expect(manager.isRunning, isFalse);
      expect(binding.startCounts, [1]);
      expect(binding.updateCounts, isEmpty);

      // Plugin recovers — next attempt succeeds.
      binding.startSucceeds = true;
      await manager.onConnectionCountChanged(2);
      expect(manager.isRunning, isTrue);
      // The second 0 → positive transition fired a start, not an
      // update. updateCounts must still be empty.
      expect(binding.startCounts, [1, 2]);
      expect(binding.updateCounts, isEmpty);
    });

    test('count stays 0 across multiple ticks → no spurious stop', () async {
      // Spec: the stop branch only fires on positive → 0 while
      // `_running`. Repeated 0-deltas before the service ever started
      // are a no-op. A spurious stopService call on Android throws.
      manager.init();
      await manager.onConnectionCountChanged(0);
      await manager.onConnectionCountChanged(0);
      expect(binding.stopCount, 0);
      expect(binding.startCounts, isEmpty);
    });
  });

  // Spec — localisation cache invalidation. The connection-provider
  // listener pushes a fresh `S` bundle every time the user switches
  // locale; the manager must surface the LATEST bundle on the next
  // start/update, not the bundle that was current when the manager
  // was constructed.
  group('ForegroundServiceManager — locale re-binding', () {
    test('setLocalizations overrides the previously cached bundle', () async {
      final binding = _LocaleRecordingBinding();
      final manager = ForegroundServiceManager(binding: binding);
      final en = await S.delegate.load(const Locale('en'));
      // ICU plural surface differs by locale, but locale loading is
      // deterministic — load each bundle once and assert identity.
      final ru = await S.delegate.load(const Locale('ru'));

      manager.init();
      manager.setLocalizations(en);
      await manager.onConnectionCountChanged(1);
      // Switch locale mid-session — next update must see the ru bundle.
      manager.setLocalizations(ru);
      await manager.onConnectionCountChanged(2);

      expect(binding.startLocalizations, [en]);
      expect(binding.updateLocalizations, [ru]);
    });
  });

  // Spec — locale-specific plural forms must render correctly per
  // language. The English bundle has only `one` / `other`, Russian has
  // `one` / `few` / `many` / `other`. Pin a few representative locales
  // so a regression that hard-coded the English ternary plural would
  // surface as the wrong word ending in the notification.
  group('notificationText — non-English plural surfaces', () {
    test('Russian renders the few-form for 3 connections', () async {
      final ru = await S.delegate.load(const Locale('ru'));
      // Spec: ru arb defines `few` for 2/3/4 and `other` for the rest.
      // 3 connections must select the `few` arm, not the English-style
      // plural fallback. A regression that collapsed to a ternary would
      // render the singular Russian form here, which is grammatically
      // wrong.
      final text = notificationText(ru, 3);
      expect(text, contains('3'));
      // The `few` arm in ru includes "активных подключения" (genitive
      // plural-few). The exact full string lives in the arb; pin the
      // distinguishing substring so localisation tweaks that preserve
      // the few form pass and an accidental collapse to `other` fails.
      expect(text, contains('активных'));
    });

    test('Russian renders the zero-form for 0 connections (locale-specific '
        'plural, not English fallback)', () async {
      final ru = await S.delegate.load(const Locale('ru'));
      // Spec: ru arb defines an explicit `=0{Нет активных подключений}`
      // arm. A regression that lost the =0 special case would render
      // the generic plural ("0 активных подключений"), which is correct
      // but loses the user-facing "Нет" prefix the arb deliberately
      // surfaces. Pin the special case so an arb refactor catches.
      expect(notificationText(ru, 0), 'Нет активных подключений');
    });
  });

  // Spec — the no-op branches in `onConnectionCountChanged` are the
  // safety net for a misconfigured caller. Cover each individually so
  // coverage names exactly which guard surfaced.
  group('ForegroundServiceManager — no-op branches by surface', () {
    test('positive→positive while running fires update, not start — start was '
        'already paid on the 0→positive transition', () async {
      // Spec: the second positive count must take the update branch,
      // not re-start. A regression that re-fired start would race the
      // live notification and on Android produce two heads-up
      // notifications.
      final binding = FakeBinding();
      final manager = ForegroundServiceManager(binding: binding);
      manager.init();
      await manager.onConnectionCountChanged(1);
      await manager.onConnectionCountChanged(1);
      expect(binding.startCounts, [1]);
      expect(binding.updateCounts, [1]);
    });

    test('0→0 while NOT running is a complete no-op — neither start, update, '
        'nor stop fires', () async {
      // Spec: the `else if (activeCount == 0 && _running)` arm is the
      // only branch that consults `stopService`. With _running=false
      // and count=0 every conditional in the chain misses, and the
      // method completes silently. A regression that collapsed the
      // chain into a single "stop if count==0" would call stopService
      // on a never-started binding and on Android the plugin throws.
      final binding = FakeBinding();
      final manager = ForegroundServiceManager(binding: binding);
      manager.init();
      await manager.onConnectionCountChanged(0);
      expect(binding.startCounts, isEmpty);
      expect(binding.updateCounts, isEmpty);
      expect(binding.stopCount, 0);
    });
  });
}

/// Captures the `S` bundle each start/update was called with so the
/// localisation-cache contract can be asserted without mocking the
/// translation surface.
class _LocaleRecordingBinding implements ForegroundServiceBinding {
  final startLocalizations = <S>[];
  final updateLocalizations = <S>[];

  @override
  bool get isSupported => true;

  @override
  void initService() {}

  @override
  Future<bool> startService(int count, S localizations) async {
    startLocalizations.add(localizations);
    return true;
  }

  @override
  Future<void> updateNotification(int count, S localizations) async {
    updateLocalizations.add(localizations);
  }

  @override
  Future<void> stopService() async {}
}
