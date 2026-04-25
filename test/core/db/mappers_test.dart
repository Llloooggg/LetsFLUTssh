import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/dao/folder_dao.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/db/mappers.dart';

DbFolder _folder(String id, String name, String? parentId) => DbFolder(
  id: id,
  name: name,
  parentId: parentId,
  sortOrder: 0,
  collapsed: false,
  createdAt: DateTime(2025, 1, 1),
);

DbSession _session({required String? folderId, String extras = '{}'}) =>
    DbSession(
      id: 's1',
      label: 'web-prod',
      folderId: folderId,
      host: 'example.com',
      port: 22,
      user: 'root',
      authType: 'password',
      keyId: null,
      password: '',
      keyPath: '',
      keyData: '',
      passphrase: '',
      notes: '',
      sortOrder: 0,
      extras: extras,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );

void main() {
  group('dbSessionToSession folder path resolution', () {
    test('builds nested path from intact parent chain', () {
      final folders = {
        'a': _folder('a', 'Production', null),
        'b': _folder('b', 'EU', 'a'),
        'c': _folder('c', 'Web', 'b'),
      };
      final session = dbSessionToSession(_session(folderId: 'c'), folders);
      expect(session.folder, 'Production/EU/Web');
    });

    test('empty path for sessions at root', () {
      final session = dbSessionToSession(_session(folderId: null), const {});
      expect(session.folder, '');
    });

    test(
      'orphan parent_id surfaces as "(orphaned)/..." instead of silent truncation',
      () {
        // Folder "leaf" exists but its parent "missing" has been deleted.
        final folders = {'leaf': _folder('leaf', 'EU', 'missing')};
        final session = dbSessionToSession(_session(folderId: 'leaf'), folders);
        // Walk: leaf → missing (absent) → break with orphan marker.
        expect(session.folder, '(orphaned)/EU');
      },
    );

    test('orphan reference at the leaf itself shows just the marker', () {
      // The session points directly at a non-existent folder id.
      final session = dbSessionToSession(
        _session(folderId: 'never-existed'),
        const {},
      );
      expect(session.folder, '(orphaned)/');
    });
  });

  group('resolveFolderPath cache-first resolution', () {
    late AppDatabase db;
    late _CountingFolderDao dao;

    setUp(() {
      db = openTestDatabase();
      dao = _CountingFolderDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'walks an already-populated cache without any getChildren calls',
      () async {
        // Pre-seed a two-level tree directly on the DAO, then snapshot the
        // cache the way SessionStore.load() does. Subsequent lookups must
        // resolve entirely in-memory — the fix for the N+1 import cost.
        await dao.insert(
          FoldersCompanion.insert(
            id: 'a',
            name: 'Production',
            parentId: const Value(null),
            createdAt: DateTime(2026),
          ),
        );
        await dao.insert(
          FoldersCompanion.insert(
            id: 'b',
            name: 'EU',
            parentId: const Value('a'),
            createdAt: DateTime(2026),
          ),
        );
        final cache = buildFolderMap(await dao.getAll());
        dao.resetCounters();

        final resolved = await resolveFolderPath('Production/EU', dao, cache);

        expect(resolved, 'b');
        expect(
          dao.getChildrenCalls,
          0,
          reason: 'cache-first lookup must not fall back to the DAO',
        );
        expect(
          dao.insertCalls,
          0,
          reason: 'no new folders were needed so the DB must be untouched',
        );
      },
    );

    test('creates missing segments and registers them in the cache', () async {
      final cache = <String, DbFolder>{};
      final resolved = await resolveFolderPath('Production/EU/Web', dao, cache);

      // 3 segments created → 3 inserts, zero getChildren (we go straight
      // to "not in cache → insert" for each segment).
      expect(dao.insertCalls, 3);
      expect(dao.getChildrenCalls, 0);
      expect(cache.length, 3);
      // The leaf of the returned path must also be reachable through the
      // map, otherwise the next mutation would re-insert "Web" as a
      // sibling instead of updating the existing row.
      expect(cache[resolved]!.name, 'Web');
      expect(cache[resolved]!.parentId, isNotNull);
    });

    test(
      're-resolving the same path after a create finds the cached row (no duplicate inserts)',
      () async {
        final cache = <String, DbFolder>{};
        final first = await resolveFolderPath('a/b', dao, cache);
        dao.resetCounters();

        final second = await resolveFolderPath('a/b', dao, cache);

        expect(second, first, reason: 'should return the same folderId');
        expect(
          dao.insertCalls,
          0,
          reason: 'second call must hit cache, not the DB',
        );
      },
    );
  });
}

/// Test double over [FolderDao] that counts DAO entry points invoked by
/// [resolveFolderPath]. Delegates to the real DAO so inserts still hit
/// the drift in-memory DB and subsequent lookups return realistic data.
class _CountingFolderDao extends FolderDao {
  _CountingFolderDao(super.db);

  int getChildrenCalls = 0;
  int insertCalls = 0;

  void resetCounters() {
    getChildrenCalls = 0;
    insertCalls = 0;
  }

  @override
  Future<List<DbFolder>> getChildren(String? parentId) {
    getChildrenCalls++;
    return super.getChildren(parentId);
  }

  @override
  Future<void> insert(FoldersCompanion folder) {
    insertCalls++;
    return super.insert(folder);
  }
}
