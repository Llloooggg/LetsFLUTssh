import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await db.sessionDao.insert(
      SessionsCompanion.insert(
        id: 's1',
        host: 'h',
        user: 'u',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  SnippetsCompanion makeSnippet({required String id, String title = 'ls'}) =>
      SnippetsCompanion.insert(
        id: id,
        title: title,
        command: 'ls -la',
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );

  group('SnippetDao', () {
    test('insert and getAll', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1'));
      await db.snippetDao.insert(makeSnippet(id: 'sn2'));
      expect(await db.snippetDao.getAll(), hasLength(2));
    });

    test('getById', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1', title: 'deploy'));
      final s = await db.snippetDao.getById('sn1');
      expect(s!.title, 'deploy');
    });

    test('update changes title', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1', title: 'old'));
      await db.snippetDao.update(
        SnippetsCompanion(
          id: const Value('sn1'),
          title: const Value('new'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      expect((await db.snippetDao.getById('sn1'))!.title, 'new');
    });

    test('deleteById removes snippet', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1'));
      await db.snippetDao.deleteById('sn1');
      expect(await db.snippetDao.getById('sn1'), isNull);
    });

    test('link and unlink to session', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1'));
      await db.snippetDao.linkToSession('sn1', 's1');

      final snippets = await db.snippetDao.getForSession('s1');
      expect(snippets, hasLength(1));
      expect(snippets.first.id, 'sn1');

      await db.snippetDao.unlinkFromSession('sn1', 's1');
      expect(await db.snippetDao.getForSession('s1'), isEmpty);
    });

    test('deleting snippet cascades to junction', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1'));
      await db.snippetDao.linkToSession('sn1', 's1');
      await db.snippetDao.deleteById('sn1');
      expect(await db.snippetDao.getForSession('s1'), isEmpty);
    });

    test('deleting session cascades to junction', () async {
      await db.snippetDao.insert(makeSnippet(id: 'sn1'));
      await db.snippetDao.linkToSession('sn1', 's1');
      await db.sessionDao.deleteById('s1');
      // Snippet still exists but junction is gone
      expect(await db.snippetDao.getAll(), hasLength(1));
    });
  });
}
