import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/auto_lock_store.dart';
import 'package:letsflutssh/providers/auto_lock_provider.dart';

// Phase 4.2 stage 6: AutoLockStore now reads/writes through FRB
// (`lfs_core.db`). flutter_test does not load the native bridge, so
// the persistence-asserting tests that round-tripped through drift's
// in-memory DB no longer apply — see plan precedent at "Drop
// dartssh2 ... rewrite against MockSshTransport in a follow-up".
// Equivalent coverage moves to integration_test.

void main() {
  group('AutoLockMinutesNotifier', () {
    test('build() seeds the state with 0 (auto-lock disabled)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Reading the provider triggers build(); the default has to
      // stay 0 so a locked DB (no value readable yet) does not auto-
      // lock on the first frame after unlock.
      expect(container.read(autoLockMinutesProvider), 0);
    });
  });

  group('autoLockStoreProvider', () {
    test('returns an AutoLockStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(autoLockStoreProvider), isA<AutoLockStore>());
    });
  });

  group('AutoLockStore', () {
    test(
      'load returns 0 when DB is unreachable (locked / no native lib)',
      () async {
        final store = AutoLockStore();
        // No FRB native lib in the unit-test runner → DB call throws →
        // store catches and surfaces 0 (auto-lock disabled). The same
        // behaviour fires before unlock at runtime.
        expect(await store.load(), 0);
      },
    );

    test('save is a no-op when DB is unreachable', () async {
      // Saving without a DB must not throw — the setting survives
      // until the DB is available, at which point the next `set()`
      // persists it. Crashing here would turn a race between unlock
      // and setting save into a fatal exception.
      final store = AutoLockStore();
      await store.save(30);
    });
  });
}
