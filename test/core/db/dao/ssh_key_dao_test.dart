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

  SshKeysCompanion makeKey({required String id, String label = 'mykey'}) =>
      SshKeysCompanion.insert(
        id: id,
        label: label,
        privateKey: 'priv-pem',
        publicKey: 'pub-openssh',
        keyType: 'ssh-ed25519',
        createdAt: DateTime(2024),
      );

  group('SshKeyDao', () {
    test('insert and getAll', () async {
      await db.sshKeyDao.insert(makeKey(id: 'k1'));
      await db.sshKeyDao.insert(makeKey(id: 'k2'));
      expect(await db.sshKeyDao.getAll(), hasLength(2));
    });

    test('getById', () async {
      await db.sshKeyDao.insert(makeKey(id: 'k1', label: 'server'));
      final k = await db.sshKeyDao.getById('k1');
      expect(k!.label, 'server');
    });

    test('update changes label', () async {
      await db.sshKeyDao.insert(makeKey(id: 'k1', label: 'old'));
      await db.sshKeyDao.update(
        const SshKeysCompanion(id: Value('k1'), label: Value('new')),
      );
      expect((await db.sshKeyDao.getById('k1'))!.label, 'new');
    });

    test('deleteById removes key', () async {
      await db.sshKeyDao.insert(makeKey(id: 'k1'));
      await db.sshKeyDao.deleteById('k1');
      expect(await db.sshKeyDao.getById('k1'), isNull);
    });

    test('deleting key sets session keyId to null', () async {
      await db.sshKeyDao.insert(makeKey(id: 'k1'));
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 's1',
          host: 'h',
          user: 'u',
          keyId: const Value('k1'),
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );

      await db.sshKeyDao.deleteById('k1');
      final s = await db.sessionDao.getById('s1');
      expect(s!.keyId, isNull);
    });
  });
}
