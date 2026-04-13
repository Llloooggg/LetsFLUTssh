import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  FoldersCompanion makeFolder({
    required String id,
    required String name,
    String? parentId,
  }) => FoldersCompanion.insert(
    id: id,
    name: name,
    parentId: Value(parentId),
    createdAt: DateTime(2024),
  );

  group('FolderDao', () {
    test('insert and getAll', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'web'));
      await db.folderDao.insert(makeFolder(id: 'f2', name: 'db'));
      expect(await db.folderDao.getAll(), hasLength(2));
    });

    test('getById', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'web'));
      final f = await db.folderDao.getById('f1');
      expect(f!.name, 'web');
    });

    test('getChildren returns root folders', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'root'));
      await db.folderDao.insert(
        makeFolder(id: 'f2', name: 'child', parentId: 'f1'),
      );
      final roots = await db.folderDao.getChildren(null);
      expect(roots, hasLength(1));
      expect(roots.first.name, 'root');
    });

    test('getChildren returns children of parent', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'root'));
      await db.folderDao.insert(
        makeFolder(id: 'f2', name: 'child', parentId: 'f1'),
      );
      final children = await db.folderDao.getChildren('f1');
      expect(children, hasLength(1));
      expect(children.first.name, 'child');
    });

    test('update changes name', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'old'));
      await db.folderDao.update(
        const FoldersCompanion(id: Value('f1'), name: Value('new')),
      );
      expect((await db.folderDao.getById('f1'))!.name, 'new');
    });

    test('deleteById removes folder', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'web'));
      await db.folderDao.deleteById('f1');
      expect(await db.folderDao.getById('f1'), isNull);
    });

    test('deleteRecursive removes subtree', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'root'));
      await db.folderDao.insert(
        makeFolder(id: 'f2', name: 'child', parentId: 'f1'),
      );
      await db.folderDao.insert(
        makeFolder(id: 'f3', name: 'grandchild', parentId: 'f2'),
      );

      await db.folderDao.deleteRecursive('f1');
      expect(await db.folderDao.getAll(), isEmpty);
    });

    test('deleteRecursive sets session folderId to null', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'web'));
      await db.sessionDao.insert(
        SessionsCompanion.insert(
          id: 's1',
          host: 'h',
          user: 'u',
          folderId: const Value('f1'),
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );

      await db.folderDao.deleteRecursive('f1');
      final s = await db.sessionDao.getById('s1');
      expect(s!.folderId, isNull);
    });

    test('toggleCollapsed flips state', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'web'));
      expect((await db.folderDao.getById('f1'))!.collapsed, isFalse);

      await db.folderDao.toggleCollapsed('f1');
      expect((await db.folderDao.getById('f1'))!.collapsed, isTrue);

      await db.folderDao.toggleCollapsed('f1');
      expect((await db.folderDao.getById('f1'))!.collapsed, isFalse);
    });

    test('moveToParent updates parentId', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'a'));
      await db.folderDao.insert(makeFolder(id: 'f2', name: 'b'));
      await db.folderDao.moveToParent('f2', 'f1');

      final f = await db.folderDao.getById('f2');
      expect(f!.parentId, 'f1');
    });

    test('getDescendantIds returns full subtree', () async {
      await db.folderDao.insert(makeFolder(id: 'f1', name: 'root'));
      await db.folderDao.insert(makeFolder(id: 'f2', name: 'a', parentId: 'f1'));
      await db.folderDao.insert(makeFolder(id: 'f3', name: 'b', parentId: 'f2'));

      final ids = await db.folderDao.getDescendantIds('f1');
      expect(ids, containsAll(['f1', 'f2', 'f3']));
    });
  });
}
