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
        makeEntry(host: 'a.io', port: 22, keyType: 'ssh-rsa', keyBase64: 'KEY1'),
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
  });
}
