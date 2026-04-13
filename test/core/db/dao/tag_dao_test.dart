import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    // Seed a folder and session for junction tests
    await db.folderDao.insert(
      FoldersCompanion.insert(id: 'f1', name: 'web', createdAt: DateTime(2024)),
    );
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

  TagsCompanion makeTag({required String id, required String name}) =>
      TagsCompanion.insert(id: id, name: name, createdAt: DateTime(2024));

  group('TagDao', () {
    test('insert and getAll', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.insert(makeTag(id: 't2', name: 'dev'));
      expect(await db.tagDao.getAll(), hasLength(2));
    });

    test('unique name constraint', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      expect(
        () => db.tagDao.insert(makeTag(id: 't2', name: 'prod')),
        throwsA(isA<Exception>()),
      );
    });

    test('deleteById removes tag', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.deleteById('t1');
      expect(await db.tagDao.getAll(), isEmpty);
    });

    test('tag and untag session', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.tagSession('s1', 't1');

      final tags = await db.tagDao.getForSession('s1');
      expect(tags, hasLength(1));
      expect(tags.first.name, 'prod');

      await db.tagDao.untagSession('s1', 't1');
      expect(await db.tagDao.getForSession('s1'), isEmpty);
    });

    test('tag and untag folder', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.tagFolder('f1', 't1');

      final tags = await db.tagDao.getForFolder('f1');
      expect(tags, hasLength(1));

      await db.tagDao.untagFolder('f1', 't1');
      expect(await db.tagDao.getForFolder('f1'), isEmpty);
    });

    test('deleting tag cascades to junctions', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.tagSession('s1', 't1');
      await db.tagDao.tagFolder('f1', 't1');

      await db.tagDao.deleteById('t1');
      expect(await db.tagDao.getForSession('s1'), isEmpty);
      expect(await db.tagDao.getForFolder('f1'), isEmpty);
    });

    test('deleting session cascades to session_tags', () async {
      await db.tagDao.insert(makeTag(id: 't1', name: 'prod'));
      await db.tagDao.tagSession('s1', 't1');

      await db.sessionDao.deleteById('s1');
      // Tag still exists but junction is gone
      expect(await db.tagDao.getAll(), hasLength(1));
      // No error querying for deleted session
      expect(await db.tagDao.getForSession('s1'), isEmpty);
    });
  });
}
