import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/snippets/snippet_store.dart';

void main() {
  late AppDatabase db;
  late SnippetStore store;

  setUp(() {
    db = openTestDatabase();
    store = SnippetStore()..setDatabase(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SnippetStore', () {
    test('loadAll returns empty when no snippets', () async {
      final result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('add and loadAll roundtrip', () async {
      final snippet = Snippet(title: 'Deploy', command: 'make deploy');
      await store.add(snippet);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].title, 'Deploy');
      expect(loaded[0].command, 'make deploy');
    });

    test('loadAll returns sorted by title', () async {
      await store.add(Snippet(title: 'Zzz', command: 'z'));
      await store.add(Snippet(title: 'Alpha', command: 'a'));
      await store.add(Snippet(title: 'Middle', command: 'm'));

      final loaded = await store.loadAll();
      expect(loaded.map((s) => s.title).toList(), ['Alpha', 'Middle', 'Zzz']);
    });

    test('update modifies snippet', () async {
      final snippet = Snippet(title: 'Old', command: 'old');
      await store.add(snippet);

      final updated = snippet.copyWith(title: 'New', command: 'new');
      await store.update(updated);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].title, 'New');
      expect(loaded[0].command, 'new');
    });

    test('delete removes snippet', () async {
      final s1 = Snippet(title: 'A', command: 'a');
      final s2 = Snippet(title: 'B', command: 'b');
      await store.add(s1);
      await store.add(s2);

      await store.delete(s1.id);

      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded[0].title, 'B');
    });

    test('description is preserved', () async {
      final snippet = Snippet(
        title: 'Test',
        command: 'echo test',
        description: 'Run a test',
      );
      await store.add(snippet);

      final loaded = await store.loadAll();
      expect(loaded[0].description, 'Run a test');
    });

    test('loadAll returns empty without database', () async {
      final emptyStore = SnippetStore();
      final result = await emptyStore.loadAll();
      expect(result, isEmpty);
    });
  });

  group('SnippetStore — session linking', () {
    test('linkToSession and loadForSession', () async {
      // Create a session in DB first (snippets FK to sessions)
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'example.com',
          user: 'root',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final snippet = Snippet(title: 'Restart', command: 'systemctl restart');
      await store.add(snippet);
      await store.linkToSession(snippet.id, 'sess-1');

      final pinned = await store.loadForSession('sess-1');
      expect(pinned, hasLength(1));
      expect(pinned[0].title, 'Restart');
    });

    test('unlinkFromSession removes pin', () async {
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'example.com',
          user: 'root',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final snippet = Snippet(title: 'Restart', command: 'systemctl restart');
      await store.add(snippet);
      await store.linkToSession(snippet.id, 'sess-1');
      await store.unlinkFromSession(snippet.id, 'sess-1');

      final pinned = await store.loadForSession('sess-1');
      expect(pinned, isEmpty);
    });

    test('linkedSnippetIds returns pinned IDs', () async {
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'example.com',
          user: 'root',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final s1 = Snippet(title: 'A', command: 'a');
      final s2 = Snippet(title: 'B', command: 'b');
      await store.add(s1);
      await store.add(s2);
      await store.linkToSession(s1.id, 'sess-1');

      final ids = await store.linkedSnippetIds('sess-1');
      expect(ids, contains(s1.id));
      expect(ids, isNot(contains(s2.id)));
    });

    test('loadForSession returns empty for unknown session', () async {
      final pinned = await store.loadForSession('nonexistent');
      expect(pinned, isEmpty);
    });

    test('deleting snippet cascades to session links', () async {
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 'sess-1',
          host: 'example.com',
          user: 'root',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final snippet = Snippet(title: 'Test', command: 'test');
      await store.add(snippet);
      await store.linkToSession(snippet.id, 'sess-1');
      await store.delete(snippet.id);

      final pinned = await store.loadForSession('sess-1');
      expect(pinned, isEmpty);
    });
  });
}
