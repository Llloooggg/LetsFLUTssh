import 'package:drift/drift.dart';

import '../db/database.dart';
import '../../utils/logger.dart';
import 'snippet.dart';

/// Manages snippet persistence via drift DAO.
///
/// Follows the same `setDatabase()` pattern as KeyStore and SessionStore.
class SnippetStore {
  AppDatabase? _db;

  /// Inject the opened database.
  void setDatabase(AppDatabase db) {
    _db = db;
  }

  /// Load all snippets, sorted by title.
  Future<List<Snippet>> loadAll() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.snippetDao.getAll();
    return rows
        .map(
          (r) => Snippet(
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          ),
        )
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  /// Load snippets pinned to a specific session.
  Future<List<Snippet>> loadForSession(String sessionId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.snippetDao.getForSession(sessionId);
    return rows
        .map(
          (r) => Snippet(
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
          ),
        )
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  /// Save a new snippet.
  Future<void> add(Snippet snippet) async {
    final db = _db;
    if (db == null) return;
    await db.snippetDao.insert(
      SnippetsCompanion.insert(
        id: snippet.id,
        title: snippet.title,
        command: snippet.command,
        description: Value(snippet.description),
        createdAt: snippet.createdAt,
        updatedAt: snippet.updatedAt,
      ),
    );
  }

  /// Update an existing snippet.
  Future<void> update(Snippet snippet) async {
    final db = _db;
    if (db == null) return;
    await db.snippetDao.update(
      SnippetsCompanion(
        id: Value(snippet.id),
        title: Value(snippet.title),
        command: Value(snippet.command),
        description: Value(snippet.description),
        updatedAt: Value(snippet.updatedAt),
      ),
    );
  }

  /// Delete a snippet by ID.
  Future<void> delete(String id) async {
    final db = _db;
    if (db == null) return;
    await db.snippetDao.deleteById(id);
  }

  /// Pin a snippet to a session.
  Future<void> linkToSession(String snippetId, String sessionId) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.snippetDao.linkToSession(snippetId, sessionId);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to link snippet $snippetId to session $sessionId: $e',
        name: 'SnippetStore',
      );
    }
  }

  /// Unpin a snippet from a session.
  Future<void> unlinkFromSession(String snippetId, String sessionId) async {
    final db = _db;
    if (db == null) return;
    await db.snippetDao.unlinkFromSession(snippetId, sessionId);
  }

  /// Get IDs of snippets pinned to a session.
  Future<Set<String>> linkedSnippetIds(String sessionId) async {
    final snippets = await loadForSession(sessionId);
    return snippets.map((s) => s.id).toSet();
  }
}
