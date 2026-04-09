import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_level.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

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
    String folder = '',
    String host = 'example.com',
    String user = 'root',
    String password = '',
    String keyData = '',
    String passphrase = '',
  }) {
    return Session(
      id: id ?? 'test-${DateTime.now().microsecondsSinceEpoch}',
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

      final updated = session.copyWith(
        label: 'updated',
        server: session.server.copyWith(host: 'new.host'),
      );
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
        server: const ServerAddress(host: '', user: 'root'),
      );
      expect(() => store.add(invalid), throwsA(isA<ArgumentError>()));
    });
  });

  group('SessionStore — plaintext credentials', () {
    test('credentials are stored in sessions.json in plaintext mode', () async {
      final store = SessionStore(directory: tempDir.path);
      await store.load();
      final session = makeSession(
        id: 'cred-1',
        label: 'with-creds',
        password: 'secret123',
        keyData: 'PEM-KEY-DATA',
        passphrase: 'mypass',
      );
      await store.add(session);

      // In plaintext mode, sessions.json includes credentials
      final sessionsFile = File('${tempDir.path}/sessions.json');
      final rawJson = await sessionsFile.readAsString();
      expect(rawJson.contains('secret123'), isTrue);
      expect(rawJson.contains('PEM-KEY-DATA'), isTrue);

      // Reload — credentials should load from plaintext JSON
      final store2 = SessionStore(directory: tempDir.path);
      final loaded = await store2.load();
      expect(loaded.first.password, 'secret123');
      expect(loaded.first.keyData, 'PEM-KEY-DATA');
      expect(loaded.first.passphrase, 'mypass');
    });

    test('session without credentials loads cleanly', () async {
      final store = SessionStore(directory: tempDir.path);
      await store.load();
      final session = makeSession(id: 'no-cred', label: 'nocred');
      await store.add(session);

      final store2 = SessionStore(directory: tempDir.path);
      final loaded = await store2.load();
      expect(loaded.first.password, '');
      expect(loaded.first.keyData, '');
      expect(loaded.first.passphrase, '');
    });
  });

  group('SessionStore — encrypted mode', () {
    test('sessions are encrypted when key is set', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final store = SessionStore(directory: tempDir.path);
      store.setEncryptionKey(key, SecurityLevel.keychain);
      await store.load();

      final session = makeSession(
        id: 'enc-1',
        label: 'encrypted',
        password: 'secret',
      );
      await store.add(session);

      // sessions.enc should exist, sessions.json should not
      expect(await File('${tempDir.path}/sessions.enc').exists(), isTrue);
      expect(await File('${tempDir.path}/sessions.json').exists(), isFalse);

      // Reload with same key — credentials should be available
      final store2 = SessionStore(directory: tempDir.path);
      store2.setEncryptionKey(key, SecurityLevel.keychain);
      final loaded = await store2.load();
      expect(loaded.first.password, 'secret');
      expect(loaded.first.label, 'encrypted');
    });

    test('encrypted file is not readable as plaintext', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final store = SessionStore(directory: tempDir.path);
      store.setEncryptionKey(key, SecurityLevel.keychain);
      await store.load();
      await store.add(makeSession(id: 'enc-2', password: 'hidden'));

      final raw = await File('${tempDir.path}/sessions.enc').readAsBytes();
      // The word 'hidden' as UTF-8 bytes should not appear in encrypted data.
      final hiddenBytes = 'hidden'.codeUnits;
      var found = false;
      for (var i = 0; i <= raw.length - hiddenBytes.length; i++) {
        if (raw[i] == hiddenBytes[0]) {
          var match = true;
          for (var j = 1; j < hiddenBytes.length; j++) {
            if (raw[i + j] != hiddenBytes[j]) {
              match = false;
              break;
            }
          }
          if (match) {
            found = true;
            break;
          }
        }
      }
      expect(found, isFalse);
    });
  });

  group('SessionStore — reEncrypt', () {
    test('reEncrypt from plaintext to encrypted', () async {
      final store = SessionStore(directory: tempDir.path);
      await store.load();
      await store.add(makeSession(id: 're-1', password: 'pw1'));

      // Re-encrypt to keychain mode
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      await store.reEncrypt(key, SecurityLevel.keychain);

      // Plaintext file should be deleted
      expect(await File('${tempDir.path}/sessions.json').exists(), isFalse);
      expect(await File('${tempDir.path}/sessions.enc').exists(), isTrue);

      // Load with key — data intact
      final store2 = SessionStore(directory: tempDir.path);
      store2.setEncryptionKey(key, SecurityLevel.keychain);
      final loaded = await store2.load();
      expect(loaded.first.password, 'pw1');
    });

    test('reEncrypt from encrypted to plaintext', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final store = SessionStore(directory: tempDir.path);
      store.setEncryptionKey(key, SecurityLevel.keychain);
      await store.load();
      await store.add(makeSession(id: 're-2', password: 'pw2'));

      // Re-encrypt to plaintext
      await store.reEncrypt(null, SecurityLevel.plaintext);

      // Encrypted file should be deleted
      expect(await File('${tempDir.path}/sessions.enc').exists(), isFalse);
      expect(await File('${tempDir.path}/sessions.json').exists(), isTrue);

      // Load without key — data intact
      final store2 = SessionStore(directory: tempDir.path);
      final loaded = await store2.load();
      expect(loaded.first.password, 'pw2');
    });
  });

  group('SessionStore — empty folders', () {
    test('empty folders persist in memory', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyFolder('Production/Cache');
      await store.addEmptyFolder('Archive');

      expect(store.emptyFolders, contains('Production/Cache'));
      expect(store.emptyFolders, contains('Archive'));
    });

    test('remove empty folder from memory', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyFolder('ToRemove');
      await store.addEmptyFolder('ToKeep');
      await store.removeEmptyFolder('ToRemove');

      expect(store.emptyFolders, isNot(contains('ToRemove')));
      expect(store.emptyFolders, contains('ToKeep'));
    });

    test('empty folders file is written to disk', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyFolder('TestFolder');

      final file = File('${tempDir.path}/empty_groups.json');
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('TestFolder'));
    });

    test('addEmptyFolder with empty string is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.addEmptyFolder('');
      expect(store.emptyFolders, isEmpty);
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
    test('moveSession changes folder', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'mv-1', label: 'movable', folder: 'A');
      await store.add(session);
      await store.moveSession('mv-1', 'B');

      expect(store.sessions.first.folder, 'B');
    });

    test('moveFolder moves folder to new parent', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'mg-1', label: 's1', folder: 'Prod/Web');
      await store.add(session);
      await store.moveFolder('Prod/Web', 'Staging');

      expect(store.sessions.first.folder, 'Staging/Web');
    });
  });

  group('SessionStore — bulk operations', () {
    test('deleteMultiple removes selected sessions', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'bm-1', label: 's1', folder: 'A'));
      await store.add(makeSession(id: 'bm-2', label: 's2', folder: 'A'));
      await store.add(makeSession(id: 'bm-3', label: 's3', folder: 'B'));
      await store.deleteMultiple({'bm-1', 'bm-3'});

      expect(store.sessions, hasLength(1));
      expect(store.sessions.first.id, 'bm-2');
    });

    test('deleteMultiple with empty set is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'bm-4', label: 's4'));
      await store.deleteMultiple({});

      expect(store.sessions, hasLength(1));
    });

    test('moveMultiple moves selected sessions to new folder', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'mm-1', label: 's1', folder: 'A'));
      await store.add(makeSession(id: 'mm-2', label: 's2', folder: 'A'));
      await store.add(makeSession(id: 'mm-3', label: 's3', folder: 'B'));
      await store.moveMultiple({'mm-1', 'mm-3'}, 'C');

      final moved = store.sessions.where((s) => s.folder == 'C').toList();
      expect(moved, hasLength(2));
      expect(moved.map((s) => s.id).toSet(), {'mm-1', 'mm-3'});
      expect(store.sessions.firstWhere((s) => s.id == 'mm-2').folder, 'A');
    });

    test('moveMultiple with empty set is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'mm-4', label: 's4', folder: 'X'));
      await store.moveMultiple({}, 'Y');

      expect(store.sessions.first.folder, 'X');
    });
  });

  group('SessionStore — deleteFolder and deleteAll', () {
    test('deleteFolder removes sessions in folder', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'dg-1', label: 's1', folder: 'Prod'));
      await store.add(makeSession(id: 'dg-2', label: 's2', folder: 'Prod/Web'));
      await store.add(makeSession(id: 'dg-3', label: 's3', folder: 'Dev'));
      await store.deleteFolder('Prod');

      expect(store.sessions, hasLength(1));
      expect(store.sessions.first.folder, 'Dev');
    });

    test('deleteAll clears everything', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'da-1', label: 's1'));
      await store.add(makeSession(id: 'da-2', label: 's2'));
      await store.addEmptyFolder('G1');
      await store.deleteAll();

      expect(store.sessions, isEmpty);
      expect(store.emptyFolders, isEmpty);
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
      await store.add(
        makeSession(id: 'sr-2', label: 'postgres', host: 'b.com'),
      );

      final results = store.search('nginx');
      expect(results, hasLength(1));
      expect(results.first.label, 'nginx');
    });

    test('folders returns sorted unique folders', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'g-1', label: 's1', folder: 'B'));
      await store.add(makeSession(id: 'g-2', label: 's2', folder: 'A'));
      await store.add(makeSession(id: 'g-3', label: 's3', folder: 'B'));

      expect(store.folders(), ['A', 'B']);
    });

    test('byFolder returns sessions in specific folder', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'bg-1', label: 's1', folder: 'X'));
      await store.add(makeSession(id: 'bg-2', label: 's2', folder: 'Y'));

      final result = store.byFolder('X');
      expect(result, hasLength(1));
      expect(result.first.folder, 'X');
    });

    test('countSessionsInFolder counts folder and subfolders', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'cnt-1', label: 's1', folder: 'P'));
      await store.add(makeSession(id: 'cnt-2', label: 's2', folder: 'P/Web'));

      expect(store.countSessionsInFolder('P'), 2);
      expect(store.countSessionsInFolder('P/Web'), 1);
      expect(store.countSessionsInFolder('None'), 0);
    });
  });

  group('SessionStore — renameFolder', () {
    test('renameFolder updates sessions and empty folders', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'rn-1', label: 's1', folder: 'Old'));
      await store.add(makeSession(id: 'rn-2', label: 's2', folder: 'Old/Sub'));
      await store.addEmptyFolder('Old/Empty');
      await store.renameFolder('Old', 'New');

      expect(store.sessions[0].folder, 'New');
      expect(store.sessions[1].folder, 'New/Sub');
      expect(store.emptyFolders, contains('New/Empty'));
      expect(store.emptyFolders, isNot(contains('Old/Empty')));
    });
  });

  group('SessionStore — update validation', () {
    test('update with invalid session throws ArgumentError', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'upd-1', label: 'valid', host: 'h.com');
      await store.add(session);

      // Update with invalid data (empty host)
      final invalid = Session(
        id: 'upd-1',
        label: 'bad',
        server: const ServerAddress(host: '', user: 'root'),
      );
      expect(() => store.update(invalid), throwsA(isA<ArgumentError>()));
    });

    test('update session not found throws ArgumentError', () async {
      final store = SessionStore();
      await store.load();
      final session = makeSession(id: 'upd-2', label: 'exists', host: 'h.com');
      await store.add(session);

      final notFound = Session(
        id: 'nonexistent',
        label: 'x',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(() => store.update(notFound), throwsA(isA<ArgumentError>()));
    });
  });

  group('SessionStore — renameFolder with empty folders exact match', () {
    test('renameFolder renames exact empty folder match', () async {
      final store = SessionStore();
      await store.load();
      // Add an empty folder that exactly matches the old path
      await store.addEmptyFolder('Old');
      await store.addEmptyFolder('Old/Sub');
      await store.renameFolder('Old', 'New');

      expect(store.emptyFolders, contains('New'));
      expect(store.emptyFolders, contains('New/Sub'));
      expect(store.emptyFolders, isNot(contains('Old')));
      expect(store.emptyFolders, isNot(contains('Old/Sub')));
    });
  });

  group('SessionStore — loadEmptyFolders with valid data', () {
    test('empty folders file loads correctly', () async {
      // Write both sessions.json (so load() doesn't return early) and empty_groups.json
      final sessFile = File('${tempDir.path}/sessions.json');
      await sessFile.parent.create(recursive: true);
      await sessFile.writeAsString('[]');

      final file = File('${tempDir.path}/empty_groups.json');
      await file.writeAsString('["GroupA","GroupB"]');

      final store = SessionStore();
      await store.load();
      expect(store.emptyFolders, contains('GroupA'));
      expect(store.emptyFolders, contains('GroupB'));
    });
  });

  group('SessionStore — moveFolder edge cases', () {
    test('moveFolder to own subtree is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'mg-2', label: 's1', folder: 'A/B'));
      await store.moveFolder('A', 'A/B');

      // Should not move into own subtree
      expect(store.sessions.first.folder, 'A/B');
    });

    test('moveFolder with empty folderPath is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'mg-3', label: 's1', folder: 'X'));
      await store.moveFolder('', 'Y');

      expect(store.sessions.first.folder, 'X');
    });

    test('moveFolder when already at target is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(
        makeSession(id: 'mg-4', label: 's1', folder: 'Parent/Child'),
      );
      await store.moveFolder('Parent/Child', 'Parent');

      // Child under Parent => same path, no-op
      expect(store.sessions.first.folder, 'Parent/Child');
    });

    test('moveFolder to root', () async {
      final store = SessionStore();
      await store.load();
      await store.add(
        makeSession(id: 'mg-5', label: 's1', folder: 'Parent/Sub'),
      );
      await store.moveFolder('Parent/Sub', '');

      expect(store.sessions.first.folder, 'Sub');
    });
  });

  group('SessionStore — deleteFolder removes empty folders under path', () {
    test(
      'deleteFolder also removes empty folders under deleted path',
      () async {
        final store = SessionStore();
        await store.load();
        await store.addEmptyFolder('Prod');
        await store.addEmptyFolder('Prod/Cache');
        await store.add(makeSession(id: 'dg-e1', label: 's', folder: 'Prod'));
        await store.deleteFolder('Prod');

        expect(store.emptyFolders, isNot(contains('Prod')));
        expect(store.emptyFolders, isNot(contains('Prod/Cache')));
        expect(store.sessions, isEmpty);
      },
    );
  });

  group('SessionStore — renameFolder edge cases', () {
    test('renameFolder with empty oldPath is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'rn-e1', label: 's1', folder: 'A'));
      await store.renameFolder('', 'B');

      expect(store.sessions.first.folder, 'A');
    });

    test('renameFolder same old and new is no-op', () async {
      final store = SessionStore();
      await store.load();
      await store.add(makeSession(id: 'rn-e2', label: 's1', folder: 'A'));
      await store.renameFolder('A', 'A');

      expect(store.sessions.first.folder, 'A');
    });
  });

  group('SessionStore — edge cases', () {
    test('corrupted empty_groups.json loads gracefully', () async {
      // Write valid sessions.json so load() doesn't return early
      final sessFile = File('${tempDir.path}/sessions.json');
      await sessFile.parent.create(recursive: true);
      await sessFile.writeAsString('[]');

      // Write garbage to empty_groups.json
      final file = File('${tempDir.path}/empty_groups.json');
      await file.writeAsString('not json');

      final store = SessionStore();
      await store.load();
      expect(store.emptyFolders, isEmpty);
    });

    test('corrupted sessions.json loads gracefully', () async {
      final file = File('${tempDir.path}/sessions.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('corrupted');

      final store = SessionStore();
      final sessions = await store.load();
      expect(sessions, isEmpty);
    });

    test('get returns null for unknown id', () async {
      final store = SessionStore();
      await store.load();
      expect(store.get('nonexistent'), isNull);
    });
  });

  group('SessionStore — concurrent load guard', () {
    test('concurrent load calls do not lose credentials', () async {
      // Setup: create a session with credentials
      final setupStore = SessionStore();
      await setupStore.load();
      final session = makeSession(
        id: 'concurrent-1',
        label: 'concurrent',
        password: 'secret',
        keyData: 'PEM-DATA',
      );
      await setupStore.add(session);

      // Now simulate concurrent loads (like double onResume in WSL)
      final store = SessionStore();
      final load1 = store.load();
      final load2 = store.load();
      final results = await Future.wait([load1, load2]);

      // Both should return the same list with credentials intact
      expect(results[0], hasLength(1));
      expect(results[1], hasLength(1));
      expect(results[0].first.password, 'secret');
      expect(results[0].first.keyData, 'PEM-DATA');
      expect(results[1].first.password, 'secret');
      expect(results[1].first.keyData, 'PEM-DATA');
    });

    test('second load after first completes works normally', () async {
      final setupStore = SessionStore();
      await setupStore.load();
      await setupStore.add(
        makeSession(id: 'seq-1', label: 'seq', password: 'pw'),
      );

      final store = SessionStore();
      final first = await store.load();
      expect(first, hasLength(1));
      expect(first.first.password, 'pw');

      // Second load should also work (not blocked by stale guard)
      final second = await store.load();
      expect(second, hasLength(1));
      expect(second.first.password, 'pw');
    });
  });

  // ---------------------------------------------------------------------------
  // Session JSON serialization (covers toJson, toJsonWithCredentials, fromJson)
  // ---------------------------------------------------------------------------
  group('Session JSON serialization', () {
    test('toJson does not include password, keyData, passphrase', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'host', user: 'user'),
        auth: const SessionAuth(
          password: 'secret',
          keyData: 'PEM-DATA',
          passphrase: 'pass',
        ),
      );
      final json = s.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('key_data'), isFalse);
      expect(json.containsKey('passphrase'), isFalse);
    });

    test('toJsonWithCredentials includes secrets', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'host', user: 'user'),
        auth: const SessionAuth(
          password: 'secret',
          keyData: 'PEM-DATA',
          passphrase: 'pass',
        ),
      );
      final json = s.toJsonWithCredentials();
      expect(json['password'], 'secret');
      expect(json['key_data'], 'PEM-DATA');
      expect(json['passphrase'], 'pass');
    });

    test('fromJson reads password from JSON (legacy format)', () {
      final s = Session.fromJson({
        'id': 'test-id',
        'host': 'h',
        'user': 'u',
        'password': 'pw',
        'key_data': 'kd',
        'passphrase': 'pp',
      });
      expect(s.password, 'pw');
      expect(s.keyData, 'kd');
      expect(s.passphrase, 'pp');
    });

    test('fromJson defaults missing credentials to empty', () {
      final s = Session.fromJson({'id': 'test-id', 'host': 'h', 'user': 'u'});
      expect(s.password, '');
      expect(s.keyData, '');
      expect(s.passphrase, '');
    });
  });

  group('SessionStore — restoreSnapshot', () {
    test('replaces sessions and empty groups', () async {
      final store = SessionStore();
      await store.load();

      // Add initial data
      final s1 = Session(
        id: 'a',
        label: 'A',
        folder: '',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final s2 = Session(
        id: 'b',
        label: 'B',
        folder: 'G',
        server: const ServerAddress(host: 'h2', user: 'u'),
      );
      await store.add(s1);
      await store.add(s2);
      await store.addEmptyFolder('EmptyFolder');
      expect(store.sessions.length, 2);

      // Snapshot state
      final snapSessions = List.of(store.sessions);
      final snapFolders = Set.of(store.emptyFolders);

      // Delete everything
      await store.deleteAll();
      expect(store.sessions, isEmpty);
      expect(store.emptyFolders, isEmpty);

      // Restore from snapshot
      await store.restoreSnapshot(snapSessions, snapFolders);
      expect(store.sessions.length, 2);
      expect(store.sessions.map((s) => s.id).toSet(), {'a', 'b'});
      expect(store.emptyFolders, contains('EmptyFolder'));
    });

    test('restored state persists to disk', () async {
      final store = SessionStore();
      await store.load();

      final s1 = Session(
        id: 'x',
        label: 'X',
        folder: '',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      await store.add(s1);
      final snap = List.of(store.sessions);
      final snapFolders = Set.of(store.emptyFolders);

      await store.deleteAll();
      await store.restoreSnapshot(snap, snapFolders);

      // Reload from disk
      final store2 = SessionStore();
      final loaded = await store2.load();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'x');
    });
  });

  group('SessionStore — corrupt JSON backup', () {
    test('corrupt sessions.json is backed up to .corrupt file', () async {
      final file = File('${tempDir.path}/sessions.json');
      await file.parent.create(recursive: true);
      await file.writeAsString('not valid json {{');

      final store = SessionStore();
      final sessions = await store.load();
      expect(sessions, isEmpty);

      final backup = File('${tempDir.path}/sessions.json.corrupt');
      expect(await backup.exists(), isTrue);
      expect(await backup.readAsString(), 'not valid json {{');
    });

    test('corrupt backup overwrites previous .corrupt file', () async {
      // Create initial corrupt backup
      final backup = File('${tempDir.path}/sessions.json.corrupt');
      await backup.writeAsString('old corrupt data');

      // Write new corrupt sessions.json
      final file = File('${tempDir.path}/sessions.json');
      await file.writeAsString('new corrupt data');

      final store = SessionStore();
      await store.load();

      expect(await backup.readAsString(), 'new corrupt data');
    });
  });
}
