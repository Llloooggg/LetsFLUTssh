import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('ConfigDao', () {
    test('get returns null when no config saved', () async {
      expect(await db.configDao.get(), isNull);
    });

    test('save and get round-trips JSON', () async {
      final json = jsonEncode({
        'terminal': {'fontSize': 16},
      });
      await db.configDao.save(json);
      expect(await db.configDao.get(), json);
    });

    test('save overwrites previous config', () async {
      await db.configDao.save('{"a":1}');
      await db.configDao.save('{"a":2}');
      expect(await db.configDao.get(), '{"a":2}');
    });

    test('getAutoLockMinutes returns 0 on a fresh DB', () async {
      // The setter has never run, so the companion row is absent.
      // Defaulting to 0 lets callers skip null-handling — a regression
      // to `null` here would force every caller to add `?? 0`.
      expect(await db.configDao.getAutoLockMinutes(), 0);
    });

    test(
      'setAutoLockMinutes persists the value independent of config',
      () async {
        // The setter has to synthesize an empty `{}` blob when the row
        // is fresh because the `data` column is NOT NULL. Saving after
        // that must NOT wipe the auto-lock we just wrote.
        await db.configDao.setAutoLockMinutes(5);
        expect(await db.configDao.getAutoLockMinutes(), 5);
        expect(await db.configDao.get(), '{}');

        // A later save() through the JSON path must preserve the
        // previously-set auto-lock value — they share the same row.
        await db.configDao.save('{"ui":{"theme":"dark"}}');
        expect(
          await db.configDao.getAutoLockMinutes(),
          5,
          reason: 'save() must not clobber autoLockMinutes on the same row',
        );
      },
    );

    test('setAutoLockMinutes updates the value on a subsequent call', () async {
      await db.configDao.setAutoLockMinutes(5);
      await db.configDao.setAutoLockMinutes(15);
      expect(await db.configDao.getAutoLockMinutes(), 15);
    });

    test(
      'setAutoLockMinutes keeps an existing JSON blob intact on upsert',
      () async {
        await db.configDao.save('{"first":true}');
        await db.configDao.setAutoLockMinutes(10);
        expect(await db.configDao.get(), '{"first":true}');
        expect(await db.configDao.getAutoLockMinutes(), 10);
      },
    );

    test('setAutoLockMinutes(0) persists the disabled value', () async {
      // 0 is the "disabled" marker — the DAO treats it like any other
      // int, but the UI toggles on it, so a refactor that special-cased
      // 0 to skip the write would silently drop the disable action.
      await db.configDao.setAutoLockMinutes(20);
      await db.configDao.setAutoLockMinutes(0);
      expect(await db.configDao.getAutoLockMinutes(), 0);
    });
  });
}
