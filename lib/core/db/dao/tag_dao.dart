import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [Tags], [SessionTags], and [FolderTags] tables.
class TagDao {
  final AppDatabase _db;

  TagDao(this._db);

  Future<List<DbTag>> getAll() => _db.select(_db.tags).get();

  Future<DbTag?> getById(String id) =>
      (_db.select(_db.tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(TagsCompanion tag) async {
    await _db.into(_db.tags).insert(tag);
    AppLogger.instance.log('Inserted tag ${tag.id.value}', name: 'TagDao');
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.tags,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log('Deleted tag $id (rows: $count)', name: 'TagDao');
    return count;
  }

  // --- Session ↔ Tag ---

  Future<List<DbTag>> getForSession(String sessionId) async {
    final query = _db.select(_db.tags).join([
      innerJoin(_db.sessionTags, _db.sessionTags.tagId.equalsExp(_db.tags.id)),
    ]);
    query.where(_db.sessionTags.sessionId.equals(sessionId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.tags)).toList();
  }

  Future<void> tagSession(String sessionId, String tagId) async {
    await _db
        .into(_db.sessionTags)
        .insert(
          SessionTagsCompanion.insert(sessionId: sessionId, tagId: tagId),
        );
  }

  Future<void> untagSession(String sessionId, String tagId) async {
    await (_db.delete(_db.sessionTags)
          ..where((t) => t.sessionId.equals(sessionId) & t.tagId.equals(tagId)))
        .go();
  }

  // --- Folder ↔ Tag ---

  Future<List<DbTag>> getForFolder(String folderId) async {
    final query = _db.select(_db.tags).join([
      innerJoin(_db.folderTags, _db.folderTags.tagId.equalsExp(_db.tags.id)),
    ]);
    query.where(_db.folderTags.folderId.equals(folderId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.tags)).toList();
  }

  Future<void> tagFolder(String folderId, String tagId) async {
    await _db
        .into(_db.folderTags)
        .insert(FolderTagsCompanion.insert(folderId: folderId, tagId: tagId));
  }

  Future<void> untagFolder(String folderId, String tagId) async {
    await (_db.delete(
      _db.folderTags,
    )..where((t) => t.folderId.equals(folderId) & t.tagId.equals(tagId))).go();
  }
}
