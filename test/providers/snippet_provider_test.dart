import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('snippetStoreProvider', () {
    test('returns SnippetStore instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(snippetStoreProvider);
      expect(store, isA<SnippetStore>());
    });
  });

  group('snippetsProvider', () {
    test('returns empty list when no snippets stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(snippetStoreProvider).setDatabase(db);
      final snippets = await container.read(snippetsProvider.future);
      expect(snippets, isEmpty);
    });

    test('returns snippets sorted by title', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(snippetStoreProvider)..setDatabase(db);

      await store.add(Snippet(title: 'Zzz', command: 'z'));
      await store.add(Snippet(title: 'Alpha', command: 'a'));

      container.invalidate(snippetsProvider);
      final snippets = await container.read(snippetsProvider.future);

      expect(snippets, hasLength(2));
      expect(snippets[0].title, 'Alpha');
      expect(snippets[1].title, 'Zzz');
    });

    test('reloads after invalidation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(snippetStoreProvider)..setDatabase(db);

      var snippets = await container.read(snippetsProvider.future);
      expect(snippets, isEmpty);

      await store.add(Snippet(title: 'New', command: 'new'));

      // Still cached
      snippets = await container.read(snippetsProvider.future);
      expect(snippets, isEmpty);

      // Invalidate and reload
      container.invalidate(snippetsProvider);
      snippets = await container.read(snippetsProvider.future);
      expect(snippets, hasLength(1));
    });
  });

  group('sessionSnippetsProvider', () {
    test('returns pinned snippets for session', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(snippetStoreProvider)..setDatabase(db);

      // Create a session
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'host',
          user: 'user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final snippet = Snippet(title: 'Test', command: 'test');
      await store.add(snippet);
      await store.linkToSession(snippet.id, 'sess-1');

      final pinned = await container.read(
        sessionSnippetsProvider('sess-1').future,
      );
      expect(pinned, hasLength(1));
      expect(pinned[0].title, 'Test');
    });

    test('returns empty for session with no pinned snippets', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(snippetStoreProvider).setDatabase(db);

      final pinned = await container.read(
        sessionSnippetsProvider('nonexistent').future,
      );
      expect(pinned, isEmpty);
    });
  });
}
