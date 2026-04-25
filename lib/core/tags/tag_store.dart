import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import 'tag.dart';

/// Manages tag persistence through `lfs_core.db`. Engine behind
/// the DAO is Rust + rusqlite; on-disk row layout matches the
/// schema drift used to own.
///
/// Pre-unlock and in-the-unit-test-runner the FRB wrappers raise
/// synchronously (no native lib). Each entry point wraps its single
/// FRB call in try/catch and degrades to empty / no-op — same
/// contract drift's `_db == null` branch used to honour.
class TagStore {
  Tag _toTag(rust_db.DbTag r) => Tag(
    id: r.id,
    name: r.name,
    color: r.color,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
  );

  /// Load all tags, sorted by name.
  Future<List<Tag>> loadAll() async {
    try {
      final rows = await rust_db.dbTagsListAll();
      return rows.map(_toTag).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      AppLogger.instance.log(
        'TagStore.loadAll failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  /// Create a new tag (or update an existing one — Rust uses
  /// ON CONFLICT(id) so repeat inserts upsert).
  Future<void> add(Tag tag) async {
    try {
      await rust_db.dbTagsUpsert(
        row: rust_db.DbTag(
          id: tag.id,
          name: tag.name,
          color: tag.color,
          createdAtMs: tag.createdAt.millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Tag upsert failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Delete a tag. Cascades to all session/folder links via FK.
  Future<void> delete(String id) async {
    try {
      await rust_db.dbTagsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'Tag delete failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop every tag. Cascades through `session_tags` / `folder_tags`.
  Future<void> deleteAll() async {
    try {
      await rust_db.dbTagsDeleteAll();
    } catch (e) {
      AppLogger.instance.log(
        'Tag deleteAll failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
    }
  }

  // --- Session tagging ---

  Future<List<Tag>> getForSession(String sessionId) async {
    try {
      final rows = await rust_db.dbTagsListForSession(sessionId: sessionId);
      return rows.map(_toTag).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      AppLogger.instance.log(
        'TagStore.getForSession failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  Future<void> tagSession(String sessionId, String tagId) async {
    try {
      await rust_db.dbSessionTagsLink(sessionId: sessionId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag session $sessionId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }

  Future<void> untagSession(String sessionId, String tagId) async {
    try {
      await rust_db.dbSessionTagsUnlink(sessionId: sessionId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to untag session $sessionId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }

  // --- Folder tagging ---

  Future<List<Tag>> getForFolder(String folderId) async {
    try {
      final rows = await rust_db.dbTagsListForFolder(folderId: folderId);
      return rows.map(_toTag).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      AppLogger.instance.log(
        'TagStore.getForFolder failed: $e',
        name: 'TagStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  Future<void> tagFolder(String folderId, String tagId) async {
    try {
      await rust_db.dbFolderTagsLink(folderId: folderId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag folder $folderId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }

  Future<void> untagFolder(String folderId, String tagId) async {
    try {
      await rust_db.dbFolderTagsUnlink(folderId: folderId, tagId: tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to untag folder $folderId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }
}
