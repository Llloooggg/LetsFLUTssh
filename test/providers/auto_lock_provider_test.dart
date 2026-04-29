import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/auto_lock_provider.dart';

// AutoLockMinutesNotifier reads/writes through FRB (`lfs_core.db`).
// flutter_test does not load the native bridge, so the persistence-
// asserting tests that round-tripped through drift's in-memory DB no
// longer apply — equivalent coverage moves to integration_test.

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

    test('load resolves to 0 when DB is unreachable', () async {
      // No FRB native lib in the unit-test runner → DB call throws →
      // notifier catches and surfaces 0 (auto-lock disabled). Same
      // behaviour fires before unlock at runtime.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(autoLockMinutesProvider.notifier).load();
      expect(container.read(autoLockMinutesProvider), 0);
    });

    test(
      'set is a no-op write but updates state when DB is unreachable',
      () async {
        // Saving without a DB must not throw — the setting survives in
        // the local Notifier state, at which point the next `set()` after
        // unlock persists it. Crashing here would turn a race between
        // unlock and `set` into a fatal exception.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(autoLockMinutesProvider.notifier).set(30);
        expect(container.read(autoLockMinutesProvider), 30);
      },
    );
  });
}
