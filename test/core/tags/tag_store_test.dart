import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';

void main() {
  late AppDatabase db;
  late TagStore store;

  setUp(() {
    db = openTestDatabase();
    store = TagStore()..setDatabase(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('TagStore', () {
    test('loadAll returns empty when no tags', () async {
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('add and loadAll roundtrip', () async {
      await store.add(Tag(name: 'Production', color: '#EF5350'));

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].name, 'Production');
      expect(loaded[0].color, '#EF5350');
    });

    test('loadAll returns sorted by name', () async {
      await store.add(Tag(name: 'Zzz'));
      await store.add(Tag(name: 'Alpha'));
      await store.add(Tag(name: 'Middle'));

      final loaded = await store.loadAll();
      expect(loaded.map((t) => t.name).toList(), ['Alpha', 'Middle', 'Zzz']);
    });

    test('delete removes tag', () async {
      final tag = Tag(name: 'ToDelete');
      await store.add(tag);
      await store.delete(tag.id);

      final loaded = await store.loadAll();
      expect(loaded, isEmpty);
    });

    test('loadAll returns empty without database', () async {
      final emptyStore = TagStore();
      final result = await emptyStore.loadAll();
      expect(result, isEmpty);
    });
  });

  group('TagStore — session tagging', () {
    setUp(() async {
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'example.com',
          user: 'root',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    test('tagSession and getForSession', () async {
      final tag = Tag(name: 'Prod', color: '#EF5350');
      await store.add(tag);
      await store.tagSession('sess-1', tag.id);

      final tags = await store.getForSession('sess-1');
      expect(tags, hasLength(1));
      expect(tags[0].name, 'Prod');
    });

    test('untagSession removes tag', () async {
      final tag = Tag(name: 'Prod');
      await store.add(tag);
      await store.tagSession('sess-1', tag.id);
      await store.untagSession('sess-1', tag.id);

      final tags = await store.getForSession('sess-1');
      expect(tags, isEmpty);
    });

    test('multiple tags on session', () async {
      final t1 = Tag(name: 'Alpha');
      final t2 = Tag(name: 'Beta');
      await store.add(t1);
      await store.add(t2);
      await store.tagSession('sess-1', t1.id);
      await store.tagSession('sess-1', t2.id);

      final tags = await store.getForSession('sess-1');
      expect(tags, hasLength(2));
      expect(tags.map((t) => t.name), containsAll(['Alpha', 'Beta']));
    });

    test('getForSession returns empty for unknown session', () async {
      final tags = await store.getForSession('nonexistent');
      expect(tags, isEmpty);
    });

    test('deleting tag cascades to session links', () async {
      final tag = Tag(name: 'Temp');
      await store.add(tag);
      await store.tagSession('sess-1', tag.id);
      await store.delete(tag.id);

      final tags = await store.getForSession('sess-1');
      expect(tags, isEmpty);
    });
  });

  group('TagStore — folder tagging', () {
    setUp(() async {
      await db.folderDao.insert(
        FoldersCompanion.insert(
          id: 'fold-1',
          name: 'Production',
          createdAt: DateTime.now(),
        ),
      );
    });

    test('tagFolder and getForFolder', () async {
      final tag = Tag(name: 'Critical', color: '#EF5350');
      await store.add(tag);
      await store.tagFolder('fold-1', tag.id);

      final tags = await store.getForFolder('fold-1');
      expect(tags, hasLength(1));
      expect(tags[0].name, 'Critical');
    });

    test('untagFolder removes tag', () async {
      final tag = Tag(name: 'Critical');
      await store.add(tag);
      await store.tagFolder('fold-1', tag.id);
      await store.untagFolder('fold-1', tag.id);

      final tags = await store.getForFolder('fold-1');
      expect(tags, isEmpty);
    });

    test('getForFolder returns empty for unknown folder', () async {
      final tags = await store.getForFolder('nonexistent');
      expect(tags, isEmpty);
    });
  });
}
