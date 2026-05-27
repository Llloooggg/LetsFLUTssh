/// Real-DB integration tests for the production [AutoLockMinutesNotifier].
///
/// The unit layer (`test/providers/auto_lock_provider_test.dart`) runs
/// without the native bridge, so its `load` / `set` calls hit the
/// degraded "DB unreachable → 0 / no-op" branch and never exercise the
/// real `db_app_configs_get` / `db_app_configs_upsert` round-trip. These
/// boot an unlocked in-memory DB and drive the real persistence path,
/// including the read-before-write that preserves the JSON `data` blob.
///
/// Tagged `frb_global_store`: the auto-lock value lives in the
/// process-global encrypted DB, so the file runs in its own
/// `flutter test` process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/auto_lock_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

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

  test('build starts at 0 before any load', () {
    final c = makeContainer();
    expect(c.read(autoLockMinutesProvider), 0);
  });

  test('set persists the value and load reads it back', () async {
    final c = makeContainer();
    final notifier = c.read(autoLockMinutesProvider.notifier);
    await notifier.set(15);
    expect(c.read(autoLockMinutesProvider), 15);

    // A fresh container proves the value came from the DB, not the
    // in-memory notifier state.
    final c2 = makeContainer();
    await c2.read(autoLockMinutesProvider.notifier).load();
    expect(c2.read(autoLockMinutesProvider), 15);
  });

  test('set(0) disables auto-lock and persists', () async {
    final c = makeContainer();
    final notifier = c.read(autoLockMinutesProvider.notifier);
    await notifier.set(30);
    await notifier.set(0);
    expect(c.read(autoLockMinutesProvider), 0);

    final c2 = makeContainer();
    await c2.read(autoLockMinutesProvider.notifier).load();
    expect(c2.read(autoLockMinutesProvider), 0);
  });

  test('set preserves the existing JSON data blob', () async {
    // Park a non-default `data` payload (a ConfigStore-style write) so
    // we can prove `set` round-trips it rather than clobbering with
    // the default '{}'.
    await rust_db.dbAppConfigsUpsert(
      row: const rust_db.DbAppConfig(
        data: '{"theme":"oneDark"}',
        updatedAtMs: 1,
        autoLockMinutes: 5,
      ),
    );
    final c = makeContainer();
    await c.read(autoLockMinutesProvider.notifier).set(45);

    final row = await rust_db.dbAppConfigsGet();
    expect(row, isNotNull);
    expect(row!.autoLockMinutes, 45);
    expect(row.data, '{"theme":"oneDark"}');
  });
}
