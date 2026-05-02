import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/mappers.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../../helpers/frb_bootstrap.dart';

// Mappers operate on FRB DTO types instead of drift's row classes.
// The folder-path resolution helpers route through `lfs_core::
// folder_path` — bootstrap FRB so the canonical Rust path is what
// the unit tests exercise. The cache-first `resolveFolderPath` does
// call FRB when it has to insert, which moves to integration_test.

rust_db.DbFolder _folder(String id, String name, String? parentId) =>
    rust_db.DbFolder(
      id: id,
      name: name,
      parentId: parentId,
      sortOrder: 0,
      collapsed: false,
      createdAtMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
    );

rust_db.DbSession _session({required String? folderId, String extras = '{}'}) =>
    rust_db.DbSession(
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
      lastConnectedAtMs: null,
      viaSessionId: null,
      viaHost: null,
      viaPort: null,
      viaUser: null,
      createdAtMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      updatedAtMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

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
        final folders = {'leaf': _folder('leaf', 'EU', 'missing')};
        final session = dbSessionToSession(_session(folderId: 'leaf'), folders);
        expect(session.folder, '(orphaned)/EU');
      },
    );

    test('orphan reference at the leaf itself shows just the marker', () {
      final session = dbSessionToSession(
        _session(folderId: 'never-existed'),
        const {},
      );
      expect(session.folder, '(orphaned)/');
    });
  });

  group('findFolderIdByPath', () {
    test('matches an existing nested path', () {
      final folders = {
        'a': _folder('a', 'Production', null),
        'b': _folder('b', 'EU', 'a'),
      };
      expect(findFolderIdByPath('Production/EU', folders), 'b');
    });

    test('returns null for an empty path or missing match', () {
      final folders = {'a': _folder('a', 'Production', null)};
      expect(findFolderIdByPath('', folders), isNull);
      expect(findFolderIdByPath('Nope', folders), isNull);
    });
  });

  // Regression: `sessionToRustRow` used to hard-code
  // `sortOrder: 0`, `notes: ''`, `lastConnectedAtMs: null`, so
  // every save through `add` / `update` clobbered any non-zero
  // value previously stored Rust-side. `notes` is user-authored
  // content; the bug was destructive on every edit. Round-trip is
  // now total and the round-trip test pins it.
  group('Session ↔ DbSession round-trip preserves metadata', () {
    test('sortOrder, notes, lastConnectedAtMs survive sessionToRustRow → '
        'dbSessionToSession', () {
      final original = Session(
        id: 's1',
        label: 'web-prod',
        server: const ServerAddress(host: 'h', port: 22, user: 'u'),
        notes: 'capacity-tuning notes from the user',
        sortOrder: 42,
        lastConnectedAtMs: 1714579200000,
      );
      final dbRow = sessionToRustRow(original, folderId: null);
      expect(dbRow.notes, original.notes);
      expect(dbRow.sortOrder, original.sortOrder);
      expect(dbRow.lastConnectedAtMs, original.lastConnectedAtMs);
      final restored = dbSessionToSession(dbRow, const {});
      expect(restored.notes, original.notes);
      expect(restored.sortOrder, original.sortOrder);
      expect(restored.lastConnectedAtMs, original.lastConnectedAtMs);
    });
  });
}
