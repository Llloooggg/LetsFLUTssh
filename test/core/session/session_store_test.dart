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
    test('credentials persist through add/load', () async {
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
      expect(loaded.first.password, 'secret');
      expect(loaded.first.keyData, 'PEM-DATA');
      expect(loaded.first.passphrase, 'pass');
    });
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
  });
}
