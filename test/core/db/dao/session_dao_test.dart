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

  SessionsCompanion makeSession({
    required String id,
    String host = 'example.com',
    String user = 'root',
    String label = '',
    String? folderId,
  }) => SessionsCompanion.insert(
    id: id,
    host: host,
    user: user,
    label: Value(label),
    folderId: Value(folderId),
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );

  group('SessionDao', () {
    test('insert and getAll', () async {
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.insert(makeSession(id: 's2'));

      final all = await db.sessionDao.getAll();
      expect(all, hasLength(2));
    });

    test('getById returns null for missing', () async {
      expect(await db.sessionDao.getById('missing'), isNull);
    });

    test('getById returns inserted session', () async {
      await db.sessionDao.insert(makeSession(id: 's1', host: 'srv.io'));
      final s = await db.sessionDao.getById('s1');
      expect(s, isNotNull);
      expect(s!.host, 'srv.io');
    });

    test('update changes fields', () async {
      await db.sessionDao.insert(makeSession(id: 's1', label: 'old'));
      final ok = await db.sessionDao.update(
        SessionsCompanion(
          id: const Value('s1'),
          label: const Value('new'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      expect(ok, isTrue);
      expect((await db.sessionDao.getById('s1'))!.label, 'new');
    });

    test('deleteById removes session', () async {
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.deleteById('s1');
      expect(await db.sessionDao.getById('s1'), isNull);
    });

    test('deleteMultiple removes matching sessions', () async {
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.insert(makeSession(id: 's2'));
      await db.sessionDao.insert(makeSession(id: 's3'));
      await db.sessionDao.deleteMultiple({'s1', 's3'});
      expect(await db.sessionDao.getAll(), hasLength(1));
    });

    test('deleteAll clears table', () async {
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.insert(makeSession(id: 's2'));
      await db.sessionDao.deleteAll();
      expect(await db.sessionDao.getAll(), isEmpty);
    });

    test('search matches label, host, user', () async {
      await db.sessionDao.insert(
        makeSession(id: 's1', label: 'Production', host: 'a.io', user: 'admin'),
      );
      await db.sessionDao.insert(
        makeSession(id: 's2', label: 'Test', host: 'b.io', user: 'prod_user'),
      );

      expect(await db.sessionDao.search('prod'), hasLength(2));
      expect(await db.sessionDao.search('b.io'), hasLength(1));
    });

    test('getByFolder filters by folderId', () async {
      // Create a folder first
      await db.folderDao.insert(
        FoldersCompanion.insert(
          id: 'f1',
          name: 'web',
          createdAt: DateTime(2024),
        ),
      );
      await db.sessionDao.insert(makeSession(id: 's1', folderId: 'f1'));
      await db.sessionDao.insert(makeSession(id: 's2'));

      expect(await db.sessionDao.getByFolder('f1'), hasLength(1));
      expect(await db.sessionDao.getByFolder(null), hasLength(1));
    });

    test('moveToFolder updates folderId', () async {
      await db.folderDao.insert(
        FoldersCompanion.insert(
          id: 'f1',
          name: 'web',
          createdAt: DateTime(2024),
        ),
      );
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.moveToFolder('s1', 'f1');

      final s = await db.sessionDao.getById('s1');
      expect(s!.folderId, 'f1');
    });

    test('moveMultiple updates all', () async {
      await db.folderDao.insert(
        FoldersCompanion.insert(
          id: 'f1',
          name: 'web',
          createdAt: DateTime(2024),
        ),
      );
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.insert(makeSession(id: 's2'));
      await db.sessionDao.moveMultiple({'s1', 's2'}, 'f1');

      final all = await db.sessionDao.getByFolder('f1');
      expect(all, hasLength(2));
    });

    test('updateLastConnected sets timestamp', () async {
      await db.sessionDao.insert(makeSession(id: 's1'));
      await db.sessionDao.updateLastConnected('s1');

      final s = await db.sessionDao.getById('s1');
      expect(s!.lastConnectedAt, isNotNull);
    });

    test('watchAll emits updates', () async {
      final stream = db.sessionDao.watchAll();
      final future = stream.first;
      await db.sessionDao.insert(makeSession(id: 's1'));
      final result = await future;
      expect(result, hasLength(1));
    });
  });
}
