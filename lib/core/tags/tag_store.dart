import 'package:drift/drift.dart';

import '../db/database.dart';
import '../../utils/logger.dart';
import 'tag.dart';

/// Manages tag persistence via drift DAO.
class TagStore {
  AppDatabase? _db;

  void setDatabase(AppDatabase db) {
    _db = db;
  }

  /// Load all tags, sorted by name.
  Future<List<Tag>> loadAll() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.tagDao.getAll();
    return rows
        .map(
          (r) => Tag(
            id: r.id,
            name: r.name,
            color: r.color,
            createdAt: r.createdAt,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Create a new tag.
  Future<void> add(Tag tag) async {
    final db = _db;
    if (db == null) return;
    await db.tagDao.insert(
      TagsCompanion.insert(
        id: tag.id,
        name: tag.name,
        color: Value(tag.color),
        createdAt: tag.createdAt,
      ),
    );
  }

  /// Delete a tag. Cascades to all session/folder links.
  Future<void> delete(String id) async {
    final db = _db;
    if (db == null) return;
    await db.tagDao.deleteById(id);
  }

  // --- Session tagging ---

  /// Get tags for a session.
  Future<List<Tag>> getForSession(String sessionId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.tagDao.getForSession(sessionId);
    return rows
        .map(
          (r) => Tag(
            id: r.id,
            name: r.name,
            color: r.color,
            createdAt: r.createdAt,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Tag a session.
  Future<void> tagSession(String sessionId, String tagId) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.tagDao.tagSession(sessionId, tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag session $sessionId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }

  /// Untag a session.
  Future<void> untagSession(String sessionId, String tagId) async {
    final db = _db;
    if (db == null) return;
    await db.tagDao.untagSession(sessionId, tagId);
  }

  // --- Folder tagging ---

  /// Get tags for a folder by folder ID.
  Future<List<Tag>> getForFolder(String folderId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.tagDao.getForFolder(folderId);
    return rows
        .map(
          (r) => Tag(
            id: r.id,
            name: r.name,
            color: r.color,
            createdAt: r.createdAt,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Tag a folder.
  Future<void> tagFolder(String folderId, String tagId) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.tagDao.tagFolder(folderId, tagId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to tag folder $folderId with $tagId: $e',
        name: 'TagStore',
      );
    }
  }

  /// Untag a folder.
  Future<void> untagFolder(String folderId, String tagId) async {
    final db = _db;
    if (db == null) return;
    await db.tagDao.untagFolder(folderId, tagId);
  }
}
