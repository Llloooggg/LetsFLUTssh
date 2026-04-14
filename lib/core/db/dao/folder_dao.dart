import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [Folders] table (tree structure via parentId).
class FolderDao {
  final AppDatabase _db;

  FolderDao(this._db);

  Future<List<DbFolder>> getAll() => _db.select(_db.folders).get();

  Stream<List<DbFolder>> watchAll() => _db.select(_db.folders).watch();

  Future<DbFolder?> getById(String id) => (_db.select(
    _db.folders,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<DbFolder>> getChildren(String? parentId) {
    final q = _db.select(_db.folders);
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    return q.get();
  }

  Future<void> insert(FoldersCompanion folder) async {
    await _db.into(_db.folders).insert(folder);
    AppLogger.instance.log(
      'Inserted folder ${folder.id.value}',
      name: 'FolderDao',
    );
  }

  Future<bool> update(FoldersCompanion folder) async {
    final count = await (_db.update(
      _db.folders,
    )..where((t) => t.id.equals(folder.id.value))).write(folder);
    return count > 0;
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.folders,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log(
      'Deleted folder $id (rows: $count)',
      name: 'FolderDao',
    );
    return count;
  }

  /// Recursively collect a folder and all its descendants.
  Future<List<String>> getDescendantIds(String folderId) async {
    final ids = <String>[folderId];
    final children = await getChildren(folderId);
    for (final child in children) {
      ids.addAll(await getDescendantIds(child.id));
    }
    return ids;
  }

  /// Delete a folder and all its descendants.
  ///
  /// Sessions in deleted folders get folderId set to null (FK onDelete=setNull).
  Future<int> deleteRecursive(String folderId) async {
    final ids = await getDescendantIds(folderId);
    final count = await (_db.delete(
      _db.folders,
    )..where((t) => t.id.isIn(ids))).go();
    AppLogger.instance.log(
      'Deleted folder $folderId + ${ids.length - 1} descendants (rows: $count)',
      name: 'FolderDao',
    );
    return count;
  }

  Future<bool> toggleCollapsed(String id) async {
    final folder = await getById(id);
    if (folder == null) return false;
    final count = await (_db.update(_db.folders)..where((t) => t.id.equals(id)))
        .write(FoldersCompanion(collapsed: Value(!folder.collapsed)));
    return count > 0;
  }

  Future<bool> moveToParent(String folderId, String? newParentId) async {
    final count =
        await (_db.update(_db.folders)..where((t) => t.id.equals(folderId)))
            .write(FoldersCompanion(parentId: Value(newParentId)));
    return count > 0;
  }
}
