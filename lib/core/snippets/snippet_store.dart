import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import 'snippet.dart';

/// Manages snippet persistence through `lfs_core.db`. The engine
/// behind the DAO is Rust + rusqlite; the on-disk row layout is
/// the same the drift-era schema laid down.
///
/// Pre-unlock the FRB calls raise "db not initialized" *and the FRB
/// generated wrapper can throw synchronously when the native lib is
/// not loaded* (unit-test runner). Every entry point therefore wraps
/// the FRB call inside its own try/catch and degrades to empty /
/// no-op — same contract drift's `_db == null` branch used to honour.
class SnippetStore {
  Snippet _toSnippet(rust_db.DbSnippet r) => Snippet(
    id: r.id,
    title: r.title,
    command: r.command,
    description: r.description,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAtMs),
  );

  /// Load all snippets, sorted by title.
  Future<List<Snippet>> loadAll() async {
    try {
      final rows = await rust_db.dbSnippetsListAll();
      final list = rows.map(_toSnippet).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      return list;
    } catch (e) {
      AppLogger.instance.log(
        'SnippetStore.loadAll failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  /// Snippets pinned to a specific session, sorted by title.
  Future<List<Snippet>> loadForSession(String sessionId) async {
    try {
      final rows = await rust_db.dbSnippetsListForSession(sessionId: sessionId);
      final list = rows.map(_toSnippet).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      return list;
    } catch (e) {
      AppLogger.instance.log(
        'SnippetStore.loadForSession failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  /// Save a new snippet. Idempotent — Rust uses ON CONFLICT(id).
  Future<void> add(Snippet snippet) => _upsert(snippet);

  /// Update an existing snippet — same backing call as [add].
  Future<void> update(Snippet snippet) => _upsert(snippet);

  Future<void> _upsert(Snippet snippet) async {
    try {
      await rust_db.dbSnippetsUpsert(
        row: rust_db.DbSnippet(
          id: snippet.id,
          title: snippet.title,
          command: snippet.command,
          description: snippet.description,
          createdAtMs: snippet.createdAt.millisecondsSinceEpoch,
          updatedAtMs: snippet.updatedAt.millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'Snippet upsert failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> delete(String id) async {
    try {
      await rust_db.dbSnippetsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'Snippet delete failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop every snippet. Cascades to `session_snippets` via FK.
  Future<void> deleteAll() async {
    try {
      await rust_db.dbSnippetsDeleteAll();
    } catch (e) {
      AppLogger.instance.log(
        'Snippet deleteAll failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> linkToSession(String snippetId, String sessionId) async {
    try {
      await rust_db.dbSessionSnippetsLink(
        sessionId: sessionId,
        snippetId: snippetId,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to link snippet $snippetId to session $sessionId: $e',
        name: 'SnippetStore',
      );
    }
  }

  Future<void> unlinkFromSession(String snippetId, String sessionId) async {
    try {
      await rust_db.dbSessionSnippetsUnlink(
        sessionId: sessionId,
        snippetId: snippetId,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to unlink snippet $snippetId from session $sessionId: $e',
        name: 'SnippetStore',
      );
    }
  }

  /// IDs of snippets pinned to a session.
  Future<Set<String>> linkedSnippetIds(String sessionId) async {
    try {
      final ids = await rust_db.dbSessionSnippetsListIds(sessionId: sessionId);
      return ids.toSet();
    } catch (e) {
      AppLogger.instance.log(
        'linkedSnippetIds failed: $e',
        name: 'SnippetStore',
        level: LogLevel.warn,
      );
      return const <String>{};
    }
  }
}
