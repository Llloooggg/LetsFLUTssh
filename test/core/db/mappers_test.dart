import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/mappers.dart';

DbFolder _folder(String id, String name, String? parentId) => DbFolder(
  id: id,
  name: name,
  parentId: parentId,
  sortOrder: 0,
  collapsed: false,
  createdAt: DateTime(2025, 1, 1),
);

DbSession _session({required String? folderId}) => DbSession(
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
}
