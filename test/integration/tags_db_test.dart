/// Real-DB integration tests for the production [TagsNotifier] and the
/// per-session / per-folder tag family providers.
///
/// The unit layer can't reach these: `TagsNotifier` reads and writes
/// the encrypted `letsflutssh.db` through FRB, and the link tables
/// (`session_tags` / `folder_tags`) enforce foreign keys to `sessions`
/// / `folders`, so a link only persists when the referenced row really
/// exists. These boot an unlocked in-memory DB, seed real sessions /
/// folders, drive the real notifier, and assert against the real rows
/// the providers re-fetch after each `invalidateSelf` / family
/// invalidation.
///
/// Tagged `frb_global_store`: they wipe and assert the exact contents
/// of the process-global DB, so they run in their own `flutter test`
/// process. See dart_test.yaml.
@Tags(['frb_global_store'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/mappers.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/tag_provider.dart';
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

  // Each test starts from empty tags + sessions + folders — the DB is
  // process-global, so leftovers would skew the exact-set assertions.
  setUp(() async {
    await rust_db.dbTagsDeleteAll();
    await rust_db.dbSessionsDeleteAll();
    await rust_db.dbFoldersDeleteAll();
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('TagsNotifier CRUD against a real DB', () {
    test('add persists a tag and the provider re-fetches it', () async {
      final c = makeContainer();
      await c.read(tagsProvider.notifier).add(Tag(id: 't1', name: 'prod'));
      final tags = await c.read(tagsProvider.future);
      expect(tags.map((t) => t.id), ['t1']);
      expect(tags.single.name, 'prod');
    });

    test('list is sorted by name', () async {
      final c = makeContainer();
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 'z', name: 'zeta'));
      await notifier.add(Tag(id: 'a', name: 'alpha'));
      await notifier.add(Tag(id: 'm', name: 'mid'));
      final tags = await c.read(tagsProvider.future);
      expect(tags.map((t) => t.name).toList(), ['alpha', 'mid', 'zeta']);
    });

    test('add with an existing id upserts rather than duplicating', () async {
      final c = makeContainer();
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 't1', name: 'old', color: '#111111'));
      await notifier.add(Tag(id: 't1', name: 'new', color: '#222222'));
      final tags = await c.read(tagsProvider.future);
      expect(tags, hasLength(1));
      expect(tags.single.name, 'new');
      expect(tags.single.color, '#222222');
    });

    test('delete removes one tag, leaving the rest', () async {
      final c = makeContainer();
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 'keep', name: 'keep'));
      await notifier.add(Tag(id: 'drop', name: 'drop'));
      await notifier.delete('drop');
      final tags = await c.read(tagsProvider.future);
      expect(tags.map((t) => t.id), ['keep']);
    });

    test('deleteAll empties the table', () async {
      final c = makeContainer();
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 't1', name: 'a'));
      await notifier.add(Tag(id: 't2', name: 'b'));
      await notifier.deleteAll();
      expect(await c.read(tagsProvider.future), isEmpty);
    });
  });

  group('TagsNotifier session/folder linking against a real DB', () {
    test(
      'tagSession links a tag the session family provider returns',
      () async {
        final c = makeContainer();
        // The FK on session_tags requires a real session row.
        await c
            .read(sessionMutatorProvider)
            .add(
              Session(
                id: 's1',
                label: 'Box',
                server: const ServerAddress(host: '10.0.0.1', user: 'root'),
              ),
            );
        final notifier = c.read(tagsProvider.notifier);
        await notifier.add(Tag(id: 't1', name: 'prod'));

        await notifier.tagSession('s1', 't1');
        final tagged = await c.read(sessionTagsProvider('s1').future);
        expect(tagged.map((t) => t.id), ['t1']);

        await notifier.untagSession('s1', 't1');
        final after = await c.read(sessionTagsProvider('s1').future);
        expect(after, isEmpty);
      },
    );

    test('tagFolder links a tag the folder family provider returns', () async {
      final c = makeContainer();
      // The FK on folder_tags requires a real folder row; resolveFolderPath
      // materialises the folder and returns its DB id.
      final folderId = await resolveFolderPath('Production');
      expect(folderId, isNotNull);
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 't1', name: 'critical'));

      await notifier.tagFolder(folderId!, 't1');
      final tagged = await c.read(folderTagsProvider(folderId).future);
      expect(tagged.map((t) => t.id), ['t1']);

      await notifier.untagFolder(folderId, 't1');
      final after = await c.read(folderTagsProvider(folderId).future);
      expect(after, isEmpty);
    });

    test('a deleted tag drops out of the per-session listing', () async {
      final c = makeContainer();
      await c
          .read(sessionMutatorProvider)
          .add(
            Session(
              id: 's1',
              label: 'Box',
              server: const ServerAddress(host: '10.0.0.1', user: 'root'),
            ),
          );
      final notifier = c.read(tagsProvider.notifier);
      await notifier.add(Tag(id: 't1', name: 'prod'));
      await notifier.tagSession('s1', 't1');
      expect(await c.read(sessionTagsProvider('s1').future), hasLength(1));

      // `delete` soft-tombstones the tag (sets deleted_at for the sync
      // LWW rule); it fires no FK cascade, so the raw session_tags link
      // row survives. The INNER JOIN in dbTagsListForSession filters
      // deleted_at rows out, so the per-session listing drops it.
      await notifier.delete('t1');
      final after = await c.read(sessionTagsProvider('s1').future);
      expect(after, isEmpty);
    });
  });
}
