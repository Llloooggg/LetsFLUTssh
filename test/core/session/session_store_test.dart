import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

Session makeSession({
  String id = 'test-id',
  String label = 'Test',
  String host = 'example.com',
  String user = 'root',
  String folder = '',
  String password = '',
  String keyData = '',
  String passphrase = '',
}) {
  return Session(
    id: id,
    label: label,
    folder: folder,
    server: ServerAddress(host: host, user: user),
    auth: SessionAuth(
      password: password,
      keyData: keyData,
      passphrase: passphrase,
    ),
  );
}

void main() {
  late AppDatabase db;
  late SessionStore store;

  setUp(() {
    db = openTestDatabase();
    store = SessionStore()..setDatabase(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SessionStore — basic CRUD', () {
    test('load returns empty list initially', () async {
      final sessions = await store.load();
      expect(sessions, isEmpty);
    });

    test('add and load roundtrips session', () async {
      await store.load();
      await store.add(makeSession(id: 's1', label: 'Web'));

      // Reload from DB
      final store2 = SessionStore()..setDatabase(db);
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.label, 'Web');
    });

    test('update modifies session', () async {
      await store.load();
      await store.add(makeSession(id: 's1', label: 'Old'));
      await store.update(makeSession(id: 's1', label: 'New'));

      expect(store.get('s1')!.label, 'New');
    });

    test('delete removes session', () async {
      await store.load();
      await store.add(makeSession(id: 's1'));
      await store.add(makeSession(id: 's2'));
      await store.delete('s1');

      expect(store.sessions, hasLength(1));
      expect(store.get('s1'), isNull);
    });

    test('deleteMultiple removes matching sessions', () async {
      await store.load();
      await store.add(makeSession(id: 's1'));
      await store.add(makeSession(id: 's2'));
      await store.add(makeSession(id: 's3'));
      await store.deleteMultiple({'s1', 's3'});

      expect(store.sessions, hasLength(1));
    });

    test('deleteAll clears everything', () async {
      await store.load();
      await store.add(makeSession(id: 's1'));
      await store.add(makeSession(id: 's2'));
      await store.deleteAll();

      expect(store.sessions, isEmpty);
    });

    test('add session with invalid data throws', () async {
      await store.load();
      final invalid = Session(
        id: 'bad',
        label: 'bad',
        server: const ServerAddress(host: '', user: 'root'),
      );
      expect(() => store.add(invalid), throwsA(isA<ArgumentError>()));
    });

    test('duplicateSession creates copy', () async {
      await store.load();
      await store.add(makeSession(id: 's1', label: 'Original'));
      final copy = await store.duplicateSession('s1');

      expect(copy.id, isNot('s1'));
      expect(copy.label, 'Original (copy)');
      expect(store.sessions, hasLength(2));
    });
  });

  group('SessionStore — credentials roundtrip', () {
    test('credentials persist in DB but not in bulk-loaded cache', () async {
      // Lazy-load contract: [load] strips credentials from cached Sessions
      // to minimize their RAM footprint. A separate [loadWithCredentials]
      // call re-hydrates them from the DB row.
      await store.load();
      await store.add(
        makeSession(
          id: 's1',
          password: 'secret',
          keyData: 'PEM-DATA',
          passphrase: 'pass',
        ),
      );

      final store2 = SessionStore()..setDatabase(db);
      final loaded = await store2.load();
      expect(loaded.first.password, '');
      expect(loaded.first.keyData, '');
      expect(loaded.first.passphrase, '');

      final full = await store2.loadWithCredentials('s1');
      expect(full!.password, 'secret');
      expect(full.keyData, 'PEM-DATA');
      expect(full.passphrase, 'pass');
    });

    test(
      'bulk-loaded cache carries hasStoredSecret so the tree view does '
      'not flag embedded-key sessions as incomplete after a restart',
      () async {
        await store.load();
        await store.add(makeSession(id: 'with', keyData: 'PEM', password: ''));
        await store.add(makeSession(id: 'without', password: '', keyData: ''));

        final store2 = SessionStore()..setDatabase(db);
        final loaded = await store2.load();
        final withSecret = loaded.firstWhere((s) => s.id == 'with');
        final withoutSecret = loaded.firstWhere((s) => s.id == 'without');

        expect(withSecret.auth.hasStoredSecret, isTrue);
        expect(withSecret.hasCredentials, isTrue);
        expect(withSecret.isValid, isTrue);

        expect(withoutSecret.auth.hasStoredSecret, isFalse);
        expect(withoutSecret.hasCredentials, isFalse);
      },
    );
  });

  group('SessionStore — folders', () {
    test('sessions with folders create folder tree', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Production/Web'));
      await store.add(makeSession(id: 's2', folder: 'Production/DB'));

      expect(store.folders(), containsAll(['Production/DB', 'Production/Web']));
    });

    test('moveSession changes folder', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'A'));
      await store.moveSession('s1', 'B');

      expect(store.get('s1')!.folder, 'B');
    });

    test('moveMultiple changes folder for all', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'A'));
      await store.add(makeSession(id: 's2', folder: 'A'));
      await store.moveMultiple({'s1', 's2'}, 'B');

      expect(store.sessions.every((s) => s.folder == 'B'), isTrue);
    });

    test('renameFolder updates session paths', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Old'));
      await store.add(makeSession(id: 's2', folder: 'Old/Sub'));
      await store.renameFolder('Old', 'New');

      expect(store.get('s1')!.folder, 'New');
      expect(store.get('s2')!.folder, 'New/Sub');
    });

    test('renameFolder updates empty and collapsed folders', () async {
      await store.load();
      await store.addEmptyFolder('Old');
      await store.addEmptyFolder('Old/Sub');
      await store.toggleFolderCollapsed('Old');
      await store.toggleFolderCollapsed('Old/Sub');

      await store.renameFolder('Old', 'New');

      expect(store.emptyFolders, containsAll(['New', 'New/Sub']));
      expect(store.emptyFolders, isNot(contains('Old')));
      expect(store.collapsedFolders, containsAll(['New', 'New/Sub']));
      expect(store.collapsedFolders, isNot(contains('Old')));
    });

    test('deleteFolder removes sessions in folder', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Del'));
      await store.add(makeSession(id: 's2', folder: 'Del/Sub'));
      await store.add(makeSession(id: 's3', folder: 'Keep'));
      await store.deleteFolder('Del');

      expect(store.sessions, hasLength(1));
      expect(store.sessions.first.id, 's3');
    });

    test('countSessionsInFolder includes subfolders', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'A'));
      await store.add(makeSession(id: 's2', folder: 'A/B'));
      await store.add(makeSession(id: 's3', folder: 'C'));

      expect(store.countSessionsInFolder('A'), 2);
    });
  });

  group('SessionStore — empty folders', () {
    test('empty folders persist in memory', () async {
      await store.load();
      await store.addEmptyFolder('Production/Cache');
      await store.addEmptyFolder('Archive');

      expect(store.emptyFolders, contains('Production/Cache'));
      expect(store.emptyFolders, contains('Archive'));
    });
  });

  group('SessionStore — collapsed folders', () {
    test('toggle collapsed state', () async {
      await store.load();
      await store.addEmptyFolder('Prod');
      await store.toggleFolderCollapsed('Prod');

      expect(store.collapsedFolders, contains('Prod'));

      await store.toggleFolderCollapsed('Prod');
      expect(store.collapsedFolders, isNot(contains('Prod')));
    });
  });

  group('SessionStore — search', () {
    test('search matches label, host, user', () async {
      await store.load();
      await store.add(makeSession(id: 's1', label: 'Production', host: 'a.io'));
      await store.add(makeSession(id: 's2', label: 'Test', user: 'prod_admin'));

      expect(store.search('prod'), hasLength(2));
      expect(store.search('a.io'), hasLength(1));
    });

    test('filterSessions static method works', () {
      final sessions = [
        makeSession(id: 's1', label: 'Web'),
        makeSession(id: 's2', label: 'DB'),
      ];
      expect(SessionStore.filterSessions(sessions, 'web'), hasLength(1));
      expect(SessionStore.filterSessions(sessions, ''), hasLength(2));
    });
  });

  group('SessionStore — snapshot restore', () {
    test('restoreSnapshot replaces all data', () async {
      await store.load();
      await store.add(makeSession(id: 's1', label: 'Before'));

      final snapshot = [makeSession(id: 's2', label: 'After')];
      await store.restoreSnapshot(snapshot, {'EmptyFolder'});

      expect(store.sessions, hasLength(1));
      expect(store.sessions.first.id, 's2');
      expect(store.emptyFolders, contains('EmptyFolder'));
    });

    test('restoreSnapshot wipes previous empty + collapsed folders', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Old'));
      await store.toggleFolderCollapsed('Old');

      await store.restoreSnapshot(
        [makeSession(id: 's2', folder: 'New')],
        {'NewEmpty'},
      );

      // Old sessions gone, new snapshot in place.
      expect(store.sessions.map((s) => s.id), ['s2']);
      expect(store.emptyFolders, {'NewEmpty'});
    });

    test('restoreSnapshot recreates empty folders via folder DAO', () async {
      await store.load();
      await store.restoreSnapshot([], {'a/b/c'});

      // Reload a fresh store — empty folder path should survive the DB
      // roundtrip through resolveFolderPath.
      final store2 = SessionStore()..setDatabase(db);
      await store2.load();
      expect(store2.emptyFolders, contains('a/b/c'));
    });
  });

  group('SessionStore — queries', () {
    test('byFolder returns only sessions in the given folder', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Prod'));
      await store.add(makeSession(id: 's2', folder: 'Prod'));
      await store.add(makeSession(id: 's3', folder: 'Dev'));
      await store.add(makeSession(id: 's4'));

      final prod = store.byFolder('Prod');
      expect(prod.map((s) => s.id), unorderedEquals(['s1', 's2']));
      expect(store.byFolder('Dev').map((s) => s.id), ['s3']);
      expect(store.byFolder(''), hasLength(1));
      expect(store.byFolder('Missing'), isEmpty);
    });

    test('folders() returns sorted unique non-empty folder names', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'zebra'));
      await store.add(makeSession(id: 's2', folder: 'alpha'));
      await store.add(makeSession(id: 's3', folder: 'alpha'));
      await store.add(makeSession(id: 's4'));

      expect(store.folders(), ['alpha', 'zebra']);
    });

    test('search is case-insensitive across label/host/user/folder', () async {
      await store.load();
      await store.add(
        makeSession(id: 's1', label: 'Web', host: 'HOST1', user: 'root'),
      );
      await store.add(
        makeSession(id: 's2', label: 'DB', host: 'host2', user: 'ADMIN'),
      );
      await store.add(makeSession(id: 's3', folder: 'Backup', label: 'x'));

      expect(store.search('web').map((s) => s.id), ['s1']);
      expect(store.search('HOST2').map((s) => s.id), ['s2']);
      expect(store.search('admin').map((s) => s.id), ['s2']);
      expect(store.search('backup').map((s) => s.id), ['s3']);
      expect(store.search(''), hasLength(3));
    });
  });

  group('SessionStore — folder operations', () {
    test('moveFolder updates session paths under new parent', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'Team/Web'));
      await store.add(makeSession(id: 's2', folder: 'Team/Web/prod'));

      await store.moveFolder('Team/Web', 'Archive');

      expect(store.get('s1')!.folder, 'Archive/Web');
      expect(store.get('s2')!.folder, 'Archive/Web/prod');
    });

    test('moveFolder is a no-op when target equals source', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'A/B'));
      // Moving "A/B" under "A" resolves to "A/B" → skipped.
      await store.moveFolder('A/B', 'A');
      expect(store.get('s1')!.folder, 'A/B');
    });

    test(
      'moveFolder rejects moving a folder into its own descendant',
      () async {
        await store.load();
        await store.add(makeSession(id: 's1', folder: 'A/B'));
        // "A" under "A/B" would make "A/B/A" — would create a cycle. Skipped.
        await store.moveFolder('A', 'A/B');
        expect(store.get('s1')!.folder, 'A/B');
      },
    );

    test('moveFolder with empty source is a no-op', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'X'));
      await store.moveFolder('', 'Y');
      expect(store.get('s1')!.folder, 'X');
    });

    test(
      'deleteFolder removes nested sessions and empty sub-folders',
      () async {
        await store.load();
        await store.add(makeSession(id: 's1', folder: 'A'));
        await store.add(makeSession(id: 's2', folder: 'A/inner'));
        await store.add(makeSession(id: 's3', folder: 'B'));
        // Make A/empty an "empty folder" marker.
        await store.restoreSnapshot([...store.sessions], {'A/empty'});

        await store.deleteFolder('A');

        expect(store.sessions.map((s) => s.id), unorderedEquals(['s3']));
        expect(store.emptyFolders, isNot(contains('A/empty')));
      },
    );

    test('deleteFolder with empty path is a no-op', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'X'));
      await store.deleteFolder('');
      expect(store.sessions, hasLength(1));
    });
  });

  group('SessionStore — folder path reconstruction', () {
    test('nested folder paths round-trip through the DB', () async {
      await store.load();
      await store.add(makeSession(id: 's1', folder: 'level1/level2/level3'));

      // Reload from a fresh store — the path must survive the
      // folderId → path walk in _pathForId.
      final store2 = SessionStore()..setDatabase(db);
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.folder, 'level1/level2/level3');
    });

    test('empty folders persist through reload', () async {
      await store.load();
      await store.restoreSnapshot([], {'keep/me'});

      final store2 = SessionStore()..setDatabase(db);
      await store2.load();
      expect(store2.emptyFolders, contains('keep/me'));
    });
  });
}
