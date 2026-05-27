/// Real-FRB integration tests for the production [SyncStatusNotifier].
///
/// The provider had no test at all. `build` / `refresh` read the
/// canonical sync state off the Rust orchestrator (`sync_status`), and
/// `push` / `pull` dispatch the orchestrator verbs. With sync neither
/// enabled nor configured (the default after a bare `dbInit`), the
/// orchestrator's `prepare` step rejects before any network I/O, so
/// these stay deterministic and offline: `build` reports the disabled
/// shape and `push` / `pull` surface the error envelope.
///
/// Tagged `frb_global_store`: the orchestrator hangs off the
/// process-global app state, so the file runs in its own `flutter test`
/// process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/sync_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/sync.dart' as rust_sync;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('SyncStatusSnapshot mapping', () {
    test('disabled() is the all-off shape', () {
      final s = SyncStatusSnapshot.disabled();
      expect(s.enabled, isFalse);
      expect(s.lastPushedAtMs, 0);
      expect(s.lastPulledAtMs, 0);
      expect(s.lastError, isNull);
    });

    test('copyWith sets lastError without disturbing the rest', () {
      const base = SyncStatusSnapshot(
        enabled: true,
        lastPushedAtMs: 100,
        lastPulledAtMs: 200,
      );
      final updated = base.copyWith(lastError: 'boom');
      expect(updated.enabled, isTrue);
      expect(updated.lastPushedAtMs, 100);
      expect(updated.lastPulledAtMs, 200);
      expect(updated.lastError, 'boom');
    });

    test('fromRust mirrors the FRB status field-for-field', () {
      final raw = rust_sync.syncStatus();
      final snap = SyncStatusSnapshot.fromRust(raw);
      expect(snap.enabled, raw.enabled);
      expect(snap.lastPushedAtMs, raw.lastPushedAtMs);
      expect(snap.lastPulledAtMs, raw.lastPulledAtMs);
      expect(snap.lastError, raw.lastError);
    });
  });

  group('SyncStatusNotifier against the real orchestrator', () {
    test('build reports the disabled shape by default', () {
      final c = makeContainer();
      final state = c.read(syncStatusProvider);
      expect(state.enabled, isFalse);
      expect(state.lastPushedAtMs, 0);
      expect(state.lastPulledAtMs, 0);
    });

    test('refresh re-reads without throwing', () {
      final c = makeContainer();
      final notifier = c.read(syncStatusProvider.notifier);
      notifier.refresh();
      expect(c.read(syncStatusProvider).enabled, isFalse);
    });

    test('push surfaces the orchestrator error when sync is off', () async {
      final c = makeContainer();
      await expectLater(
        c.read(syncStatusProvider.notifier).push(),
        throwsA(anything),
      );
    });

    test('pull surfaces the orchestrator error when sync is off', () async {
      final c = makeContainer();
      await expectLater(
        c.read(syncStatusProvider.notifier).pull(),
        throwsA(anything),
      );
    });
  });
}
