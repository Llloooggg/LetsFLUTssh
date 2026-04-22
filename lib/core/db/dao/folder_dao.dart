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
  ///
  /// Resolved in a single SQL round-trip via a recursive CTE — a previous
  /// Dart-side traversal issued one `SELECT` per tree level (O(depth)
  /// queries), which dominated deletes and bulk-move flows on deep trees.
  /// The CTE fans out in the engine, backed by the `idx_folders_parent_id`
  /// index registered by [AppDatabase].
  Future<List<String>> getDescendantIds(String folderId) async {
    final rows = await _db
        .customSelect(
          'WITH RECURSIVE descendants(id) AS ( '
          '  SELECT id FROM folders WHERE id = ?1 '
          '  UNION ALL '
          '  SELECT f.id FROM folders f '
          '  INNER JOIN descendants d ON f.parent_id = d.id '
          ') '
          'SELECT id FROM descendants',
          variables: [Variable.withString(folderId)],
          readsFrom: {_db.folders},
        )
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
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
