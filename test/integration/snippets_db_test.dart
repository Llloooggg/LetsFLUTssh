/// Real-DB integration tests for the production [SnippetsNotifier] and
/// the per-session snippet family provider.
///
/// The unit layer can't reach these: `SnippetsNotifier` reads and
/// writes the encrypted `letsflutssh.db` through FRB, and the
/// `session_snippets` link table enforces a foreign key to `sessions`,
/// so a link only persists when the referenced session row exists.
/// These boot an unlocked in-memory DB, seed a real session, drive the
/// real notifier, and assert against the real rows the providers
/// re-fetch after each invalidation.
///
/// Tagged `frb_global_store`: they wipe and assert the exact contents
/// of the process-global DB, so they run in their own `flutter test`
/// process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/snippet_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);
  });

  tearDownAll(() async {
    await rust_app.dbClose();
  });

  setUp(() async {
    await rust_db.dbSnippetsDeleteAll();
    await rust_db.dbSessionsDeleteAll();
    await rust_db.dbFoldersDeleteAll();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> seedSession(ProviderContainer c, String id) {
    return c
        .read(sessionMutatorProvider)
        .add(
          Session(
            id: id,
            label: 'Box',
            server: const ServerAddress(host: '10.0.0.1', user: 'root'),
          ),
        );
  }

  group('SnippetsNotifier CRUD against a real DB', () {
    test('add persists a snippet and the provider re-fetches it', () async {
      final c = makeContainer();
      await c
          .read(snippetsProvider.notifier)
          .add(Snippet(id: 's1', title: 'List', command: 'ls -la'));
      final snippets = await c.read(snippetsProvider.future);
      expect(snippets.map((s) => s.id), ['s1']);
      expect(snippets.single.command, 'ls -la');
    });

    test('list is sorted by title', () async {
      final c = makeContainer();
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 'z', title: 'zeta', command: 'z'));
      await notifier.add(Snippet(id: 'a', title: 'alpha', command: 'a'));
      final snippets = await c.read(snippetsProvider.future);
      expect(snippets.map((s) => s.title).toList(), ['alpha', 'zeta']);
    });

    test('save upserts an existing snippet rather than duplicating', () async {
      final c = makeContainer();
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 's1', title: 'T', command: 'old'));
      await notifier.save(Snippet(id: 's1', title: 'T', command: 'new'));
      final snippets = await c.read(snippetsProvider.future);
      expect(snippets, hasLength(1));
      expect(snippets.single.command, 'new');
    });

    test('delete removes one snippet, leaving the rest', () async {
      final c = makeContainer();
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 'keep', title: 'keep', command: 'k'));
      await notifier.add(Snippet(id: 'drop', title: 'drop', command: 'd'));
      await notifier.delete('drop');
      final snippets = await c.read(snippetsProvider.future);
      expect(snippets.map((s) => s.id), ['keep']);
    });

    test('deleteAll empties the table', () async {
      final c = makeContainer();
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 's1', title: 'a', command: 'a'));
      await notifier.deleteAll();
      expect(await c.read(snippetsProvider.future), isEmpty);
    });
  });

  group('SnippetsNotifier session linking against a real DB', () {
    test('linkToSession surfaces via the family provider and id set', () async {
      final c = makeContainer();
      await seedSession(c, 's1');
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 'sn1', title: 'List', command: 'ls'));

      await notifier.linkToSession('sn1', 's1');
      final linked = await c.read(sessionSnippetsProvider('s1').future);
      expect(linked.map((s) => s.id), ['sn1']);
      expect(await notifier.linkedSnippetIds('s1'), {'sn1'});

      await notifier.unlinkFromSession('sn1', 's1');
      expect(await c.read(sessionSnippetsProvider('s1').future), isEmpty);
      expect(await notifier.linkedSnippetIds('s1'), isEmpty);
    });

    test('a deleted snippet drops out of the per-session listing', () async {
      final c = makeContainer();
      await seedSession(c, 's1');
      final notifier = c.read(snippetsProvider.notifier);
      await notifier.add(Snippet(id: 'sn1', title: 'List', command: 'ls'));
      await notifier.linkToSession('sn1', 's1');
      final linked = await c.read(sessionSnippetsProvider('s1').future);
      expect(linked.map((s) => s.id), ['sn1']);

      // `delete` soft-tombstones the snippet (sets deleted_at for the
      // sync LWW rule); it fires no FK cascade, so the raw
      // session_snippets link row survives. The INNER JOIN in
      // dbSnippetsListForSession filters deleted_at rows out, so the
      // user-facing listing drops it.
      await notifier.delete('sn1');
      expect(await c.read(sessionSnippetsProvider('s1').future), isEmpty);
    });
  });
}
