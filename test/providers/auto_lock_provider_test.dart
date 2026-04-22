import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/security/auto_lock_store.dart';
import 'package:letsflutssh/providers/auto_lock_provider.dart';

void main() {
  group('AutoLockMinutesNotifier', () {
    test('build() seeds the state with 0 (auto-lock disabled)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Reading the provider triggers build(); the default has to stay
      // 0 so a locked DB (no value readable yet) does not auto-lock on
      // the first frame after unlock.
      expect(container.read(autoLockMinutesProvider), 0);
    });

    test('load() pulls the persisted value from the store', () async {
      final store = AutoLockStore();
      final db = openTestDatabase();
      addTearDown(db.close);
      store.setDatabase(db);
      await db.configDao.setAutoLockMinutes(15);

      final container = ProviderContainer(
        overrides: [autoLockStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(autoLockMinutesProvider.notifier).load();
      expect(container.read(autoLockMinutesProvider), 15);
    });

    test('set() persists + updates the in-memory state', () async {
      final store = AutoLockStore();
      final db = openTestDatabase();
      addTearDown(db.close);
      store.setDatabase(db);

      final container = ProviderContainer(
        overrides: [autoLockStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(autoLockMinutesProvider.notifier).set(10);
      expect(container.read(autoLockMinutesProvider), 10);
      expect(await db.configDao.getAutoLockMinutes(), 10);

      // Re-loading picks up the same value.
      await container.read(autoLockMinutesProvider.notifier).load();
      expect(container.read(autoLockMinutesProvider), 10);
    });

    test('set(0) round-trips the "disabled" sentinel', () async {
      final store = AutoLockStore();
      final db = openTestDatabase();
      addTearDown(db.close);
      store.setDatabase(db);
      final container = ProviderContainer(
        overrides: [autoLockStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(autoLockMinutesProvider.notifier).set(5);
      await container.read(autoLockMinutesProvider.notifier).set(0);
      expect(container.read(autoLockMinutesProvider), 0);
      expect(await db.configDao.getAutoLockMinutes(), 0);
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
    test('load returns 0 before any DB is attached (locked state)', () async {
      final store = AutoLockStore();
      expect(await store.load(), 0);
    });

    test('save is a no-op before any DB is attached', () async {
      // Saving without a DB must not throw — the setting survives until
      // the DB is available, at which point the next `set()` persists
      // it. Crashing here would turn a race between unlock and setting
      // save into a fatal exception.
      final store = AutoLockStore();
      await store.save(30);
    });

    test('save + load round-trips through the ConfigDao', () async {
      final store = AutoLockStore();
      final db = openTestDatabase();
      addTearDown(db.close);
      store.setDatabase(db);

      await store.save(20);
      expect(await store.load(), 20);
      await store.save(0);
      expect(await store.load(), 0);
    });
  });
}
