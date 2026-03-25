import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';

/// Integration tests for SessionStore with real file I/O.
///
/// Uses a temporary directory and mocked path_provider to exercise
/// the refactored methods: _mergeAndMigrateCredentials, _mergeCredential,
/// _hasPlaintextCredentials.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_store_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await tempDir.delete(recursive: true);
  });

  Session makeSession({
    String? id,
    String label = 'test',
    String group = '',
    String host = 'example.com',
    String user = 'root',
    String password = '',
    String keyData = '',
    String passphrase = '',
  }) {
    return Session(
      id: id ?? 'test-${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      group: group,
      host: host,
      user: user,
      password: password,
      keyData: keyData,
      passphrase: passphrase,
    );
  }

  group('SessionStore — load with no data', () {
    test('load returns empty list when no file exists', () async {
      final store = SessionStore();
      final sessions = await store.load();
      expect(sessions, isEmpty);
    });
  });

  group('SessionStore — CRUD operations', () {
    test('add and load session roundtrip', () async {
      final store = SessionStore();
      await store.load();

      final session = makeSession(id: 'sess-1', label: 'server1');
      await store.add(session);

      // Create a new store instance to verify persistence
      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'sess-1');
      expect(loaded.first.label, 'server1');
    });

    test('add session with credentials persists and loads correctly', () async {
      final store = SessionStore();
      await store.load();

      final session = makeSession(
        id: 'sess-cred',
        label: 'with-creds',
        password: 'secret123',
        keyData: 'PEM-KEY-DATA',
        passphrase: 'mypass',
      );
      await store.add(session);

      // Reload in new store — credentials should be restored from encrypted store
      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.password, 'secret123');
      expect(loaded.first.keyData, 'PEM-KEY-DATA');
      expect(loaded.first.passphrase, 'mypass');
    });

    test('update session persists changes', () async {
      final store = SessionStore();
      await store.load();

      final session = makeSession(id: 'sess-upd', label: 'original');
      await store.add(session);

      final updated = session.copyWith(label: 'updated', host: 'new.host');
      await store.update(updated);

      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.label, 'updated');
      expect(loaded.first.host, 'new.host');
    });

    test('delete session removes it', () async {
      final store = SessionStore();
      await store.load();

      final s1 = makeSession(id: 'del-1', label: 'keep');
      final s2 = makeSession(id: 'del-2', label: 'remove');
      await store.add(s1);
      await store.add(s2);
      await store.delete('del-2');

      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'del-1');
    });

    test('add session with invalid data throws', () async {
      final store = SessionStore();
      await store.load();

      final invalid = Session(
        id: 'bad',
        label: 'bad',
        host: '', // invalid: empty host
        user: 'root',
      );
      expect(() => store.add(invalid), throwsA(isA<ArgumentError>()));
    });
  });

  group('SessionStore — credential migration', () {
    test('plaintext credentials in JSON are migrated to encrypted store', () async {
      // Write sessions.json directly with plaintext credentials (legacy format)
      final sessionsFile = File('${tempDir.path}/sessions.json');
      final legacyData = [
        {
          'id': 'legacy-1',
          'label': 'legacy',
          'host': 'host.com',
          'user': 'admin',
          'port': 22,
          'auth_type': 'password',
          'password': 'legacy-password',
          'key_data': 'legacy-pem',
          'passphrase': 'legacy-pass',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
      ];
      await sessionsFile.writeAsString(jsonEncode(legacyData));

      // Load — should trigger migration
      final store = SessionStore();
      final sessions = await store.load();
      expect(sessions, hasLength(1));
      expect(sessions.first.password, 'legacy-password');
      expect(sessions.first.keyData, 'legacy-pem');
      expect(sessions.first.passphrase, 'legacy-pass');

      // After migration, sessions.json should NOT contain secrets
      final rawJson = await sessionsFile.readAsString();
      final list = jsonDecode(rawJson) as List;
      final firstSession = list.first as Map<String, dynamic>;
      // toJson() excludes password, key_data, passphrase
      expect(firstSession.containsKey('password'), isFalse);
      expect(firstSession.containsKey('key_data'), isFalse);
      expect(firstSession.containsKey('passphrase'), isFalse);
    });
  });

  group('SessionStore — credential merge', () {
    test('encrypted credentials are merged into session on load', () async {
      // First: add a session with credentials
      final store = SessionStore();
      await store.load();
      final session = makeSession(
        id: 'merge-1',
        label: 'merge-test',
        password: 'encrypted-pw',
      );
      await store.add(session);

      // Verify sessions.json does NOT have password
      final sessionsFile = File('${tempDir.path}/sessions.json');
      final rawJson = await sessionsFile.readAsString();
      expect(rawJson.contains('encrypted-pw'), isFalse);

      // Reload — credentials should come from encrypted store
      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded.first.password, 'encrypted-pw');
    });

    test('session without credentials loads cleanly', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'no-cred', label: 'nocred');
      await store.add(session);

      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded.first.password, '');
      expect(loaded.first.keyData, '');
      expect(loaded.first.passphrase, '');
    });
  });

  group('SessionStore — empty groups', () {
    test('empty groups persist in memory', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyGroup('Production/Cache');
      await store.addEmptyGroup('Archive');

      expect(store.emptyGroups, contains('Production/Cache'));
      expect(store.emptyGroups, contains('Archive'));
    });

    test('remove empty group from memory', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyGroup('ToRemove');
      await store.addEmptyGroup('ToKeep');
      await store.removeEmptyGroup('ToRemove');

      expect(store.emptyGroups, isNot(contains('ToRemove')));
      expect(store.emptyGroups, contains('ToKeep'));
    });

    test('empty groups file is written to disk', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyGroup('TestGroup');

      final file = File('${tempDir.path}/empty_groups.json');
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('TestGroup'));
    });

    test('addEmptyGroup with empty string is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyGroup('');
      expect(store.emptyGroups, isEmpty);
    });
  });

  group('SessionStore — duplicate', () {
    test('duplicateSession creates copy with new id', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'dup-orig', label: 'original');
      await store.add(session);

      final copy = await store.duplicateSession('dup-orig');
      expect(copy.id, isNot('dup-orig'));
      expect(copy.label, 'original (copy)');
      expect(store.sessions, hasLength(2));
    });

    test('duplicateSession for nonexistent throws', () async {
      final store = SessionStore();
      await store.load();
      expect(
        () => store.duplicateSession('nonexistent'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SessionStore — move operations', () {
    test('moveSession changes group', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'mv-1', label: 'movable', group: 'A');
      await store.add(session);
      await store.moveSession('mv-1', 'B');

      expect(store.sessions.first.group, 'B');
    });

    test('moveGroup moves folder to new parent', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'mg-1', label: 's1', group: 'Prod/Web');
      await store.add(session);
      await store.moveGroup('Prod/Web', 'Staging');

      expect(store.sessions.first.group, 'Staging/Web');
    });
  });

  group('SessionStore — deleteGroup and deleteAll', () {
    test('deleteGroup removes sessions in group', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'dg-1', label: 's1', group: 'Prod'));
      await store.add(makeSession(id: 'dg-2', label: 's2', group: 'Prod/Web'));
      await store.add(makeSession(id: 'dg-3', label: 's3', group: 'Dev'));
      await store.deleteGroup('Prod');

      expect(store.sessions, hasLength(1));
      expect(store.sessions.first.group, 'Dev');
    });

    test('deleteAll clears everything', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'da-1', label: 's1'));
      await store.add(makeSession(id: 'da-2', label: 's2'));
      await store.addEmptyGroup('G1');
      await store.deleteAll();

      expect(store.sessions, isEmpty);
      expect(store.emptyGroups, isEmpty);
    });
  });

  group('SessionStore — query methods', () {
    test('get returns session by id', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'get-1', label: 'found'));

      expect(store.get('get-1')?.label, 'found');
      expect(store.get('nonexistent'), isNull);
    });

    test('search by label', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'sr-1', label: 'nginx', host: 'a.com'));
      await store.add(makeSession(id: 'sr-2', label: 'postgres', host: 'b.com'));

      final results = store.search('nginx');
      expect(results, hasLength(1));
      expect(results.first.label, 'nginx');
    });

    test('groups returns sorted unique groups', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'g-1', label: 's1', group: 'B'));
      await store.add(makeSession(id: 'g-2', label: 's2', group: 'A'));
      await store.add(makeSession(id: 'g-3', label: 's3', group: 'B'));

      expect(store.groups(), ['A', 'B']);
    });

    test('byGroup returns sessions in specific group', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'bg-1', label: 's1', group: 'X'));
      await store.add(makeSession(id: 'bg-2', label: 's2', group: 'Y'));

      final result = store.byGroup('X');
      expect(result, hasLength(1));
      expect(result.first.group, 'X');
    });

    test('countSessionsInGroup counts group and subgroups', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'cnt-1', label: 's1', group: 'P'));
      await store.add(makeSession(id: 'cnt-2', label: 's2', group: 'P/Web'));

      expect(store.countSessionsInGroup('P'), 2);
      expect(store.countSessionsInGroup('P/Web'), 1);
      expect(store.countSessionsInGroup('None'), 0);
    });
  });

  group('SessionStore — renameGroup', () {
    test('renameGroup updates sessions and empty groups', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'rn-1', label: 's1', group: 'Old'));
      await store.add(makeSession(id: 'rn-2', label: 's2', group: 'Old/Sub'));
      await store.addEmptyGroup('Old/Empty');
      await store.renameGroup('Old', 'New');

      expect(store.sessions[0].group, 'New');
      expect(store.sessions[1].group, 'New/Sub');
      expect(store.emptyGroups, contains('New/Empty'));
      expect(store.emptyGroups, isNot(contains('Old/Empty')));
    });
  });
}
