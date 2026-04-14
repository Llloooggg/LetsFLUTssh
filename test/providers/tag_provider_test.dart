import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/core/tags/tag_store.dart';
import 'package:letsflutssh/providers/tag_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('tagStoreProvider', () {
    test('returns TagStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider);
      expect(store, isA<TagStore>());
    });
  });

  group('tagsProvider', () {
    test('returns empty list when no tags stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(tagStoreProvider).setDatabase(db);
      final tags = await container.read(tagsProvider.future);
      expect(tags, isEmpty);
    });

    test('returns tags sorted by name', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider)..setDatabase(db);

      await store.add(Tag(name: 'Zzz'));
      await store.add(Tag(name: 'Alpha'));

      container.invalidate(tagsProvider);
      final tags = await container.read(tagsProvider.future);

      expect(tags, hasLength(2));
      expect(tags[0].name, 'Alpha');
      expect(tags[1].name, 'Zzz');
    });

    test('reloads after invalidation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider)..setDatabase(db);

      var tags = await container.read(tagsProvider.future);
      expect(tags, isEmpty);

      await store.add(Tag(name: 'New'));

      // Still cached
      tags = await container.read(tagsProvider.future);
      expect(tags, isEmpty);

      // Invalidate and reload
      container.invalidate(tagsProvider);
      tags = await container.read(tagsProvider.future);
      expect(tags, hasLength(1));
    });
  });

  group('sessionTagsProvider', () {
    test('returns tags for session', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider)..setDatabase(db);

      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'host',
          user: 'user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final tag = Tag(name: 'Prod');
      await store.add(tag);
      await store.tagSession('sess-1', tag.id);

      final tags = await container.read(sessionTagsProvider('sess-1').future);
      expect(tags, hasLength(1));
      expect(tags[0].name, 'Prod');
    });
  });

  group('folderTagsProvider', () {
    test('returns tags for folder', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(tagStoreProvider)..setDatabase(db);

      await db.folderDao.insert(
        FoldersCompanion.insert(
          id: 'fold-1',
          name: 'web',
          createdAt: DateTime.now(),
        ),
      );

      final tag = Tag(name: 'Critical');
      await store.add(tag);
      await store.tagFolder('fold-1', tag.id);

      final tags = await container.read(folderTagsProvider('fold-1').future);
      expect(tags, hasLength(1));
      expect(tags[0].name, 'Critical');
    });

    test('returns empty for folder with no tags', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(tagStoreProvider).setDatabase(db);

      final tags = await container.read(
        folderTagsProvider('nonexistent').future,
      );
      expect(tags, isEmpty);
    });
  });
}
