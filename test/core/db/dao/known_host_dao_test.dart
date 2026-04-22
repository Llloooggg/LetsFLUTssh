import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  KnownHostsCompanion makeEntry({
    String host = 'srv.io',
    int port = 22,
    String keyType = 'ssh-ed25519',
    String keyBase64 = 'AAAA',
  }) => KnownHostsCompanion.insert(
    host: host,
    port: Value(port),
    keyType: keyType,
    keyBase64: keyBase64,
    addedAt: DateTime(2024),
  );

  group('KnownHostDao', () {
    test('insert and lookup', () async {
      await db.knownHostDao.insert(makeEntry(host: 'a.io', port: 22));
      final e = await db.knownHostDao.lookup('a.io', 22);
      expect(e, isNotNull);
      expect(e!.keyType, 'ssh-ed25519');
    });

    test('lookup returns null for missing', () async {
      expect(await db.knownHostDao.lookup('missing', 22), isNull);
    });

    test('deleteByHostPort removes entry', () async {
      await db.knownHostDao.insert(makeEntry(host: 'a.io'));
      await db.knownHostDao.deleteByHostPort('a.io', 22);
      expect(await db.knownHostDao.lookup('a.io', 22), isNull);
    });

    test('clearAll removes everything', () async {
      await db.knownHostDao.insert(makeEntry(host: 'a.io'));
      await db.knownHostDao.insert(makeEntry(host: 'b.io'));
      await db.knownHostDao.clearAll();
      expect(await db.knownHostDao.getAll(), isEmpty);
    });

    test('exportToString produces OpenSSH format', () async {
      await db.knownHostDao.insert(
        makeEntry(
          host: 'a.io',
          port: 22,
          keyType: 'ssh-rsa',
          keyBase64: 'KEY1',
        ),
      );
      await db.knownHostDao.insert(
        makeEntry(
          host: 'b.io',
          port: 2222,
          keyType: 'ssh-ed25519',
          keyBase64: 'KEY2',
        ),
      );
      final out = await db.knownHostDao.exportToString();
      expect(out, contains('a.io:22 ssh-rsa KEY1'));
      expect(out, contains('b.io:2222 ssh-ed25519 KEY2'));
    });

    test('importFromString adds new entries', () async {
      const content = '''
a.io:22 ssh-rsa KEY1
b.io:2222 ssh-ed25519 KEY2
''';
      final added = await db.knownHostDao.importFromString(content);
      expect(added, 2);
      expect(await db.knownHostDao.getAll(), hasLength(2));
    });

    test('importFromString skips existing', () async {
      await db.knownHostDao.insert(makeEntry(host: 'a.io'));
      const content = 'a.io:22 ssh-ed25519 AAAA\nb.io:22 ssh-rsa KEY2\n';
      final added = await db.knownHostDao.importFromString(content);
      expect(added, 1);
      expect(await db.knownHostDao.getAll(), hasLength(2));
    });

    test('importFromString ignores blank lines and comments', () async {
      const content = '''
# comment
a.io:22 ssh-rsa KEY1


b.io:22 ssh-ed25519 KEY2
''';
      final added = await db.knownHostDao.importFromString(content);
      expect(added, 2);
    });

    test('deleteById returns 1 on hit and 0 on miss', () async {
      // The dao method is used by the Settings known-hosts manager
      // to action individual row deletes; it must report whether the
      // row actually went away so the UI can refresh instead of
      // assuming success.
      await db.knownHostDao.insert(makeEntry(host: 'hit.io'));
      final row = await db.knownHostDao.lookup('hit.io', 22);
      final hit = await db.knownHostDao.deleteById(row!.id);
      expect(hit, 1);
      expect(await db.knownHostDao.lookup('hit.io', 22), isNull);

      final miss = await db.knownHostDao.deleteById(99999);
      expect(miss, 0);
    });

    test('deleteMultiple removes every id in the set', () async {
      await db.knownHostDao.insert(makeEntry(host: 'a.io'));
      await db.knownHostDao.insert(makeEntry(host: 'b.io'));
      await db.knownHostDao.insert(makeEntry(host: 'c.io'));

      final all = await db.knownHostDao.getAll();
      final ids = {all[0].id, all[2].id};
      final removed = await db.knownHostDao.deleteMultiple(ids);

      expect(removed, 2);
      final remaining = await db.knownHostDao.getAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.host, 'b.io');
    });

    test(
      'importFromString skips rows with fewer than 3 whitespace-separated tokens',
      () async {
        // A malformed entry (missing key data) must not count against
        // the `added` total or insert a half-row. Pairs with the
        // blank-line test above.
        const content = '''
valid.io:22 ssh-rsa KEY1
busted
''';
        final added = await db.knownHostDao.importFromString(content);
        expect(added, 1);
        expect(await db.knownHostDao.lookup('valid.io', 22), isNotNull);
      },
    );

    test('importFromString with a non-numeric port defaults to 22', () async {
      // The helper is defensive — a typo'd port shouldn't orphan
      // the entry, just fall back to the default so the row lands
      // under the conventional ssh host/port pair.
      const content = 'oops.io:abc ssh-rsa KEY1\n';
      final added = await db.knownHostDao.importFromString(content);
      expect(added, 1);
      expect(await db.knownHostDao.lookup('oops.io', 22), isNotNull);
    });
  });
}
