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
  });
}
