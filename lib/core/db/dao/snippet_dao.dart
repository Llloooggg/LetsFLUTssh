import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [Snippets] and [SessionSnippets] tables.
class SnippetDao {
  final AppDatabase _db;

  SnippetDao(this._db);

  Future<List<DbSnippet>> getAll() => _db.select(_db.snippets).get();

  Future<DbSnippet?> getById(String id) => (_db.select(
    _db.snippets,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(SnippetsCompanion snippet) async {
    await _db.into(_db.snippets).insert(snippet);
    AppLogger.instance.log(
      'Inserted snippet ${snippet.id.value}',
      name: 'SnippetDao',
    );
  }

  Future<bool> update(SnippetsCompanion snippet) async {
    final count = await (_db.update(
      _db.snippets,
    )..where((t) => t.id.equals(snippet.id.value))).write(snippet);
    return count > 0;
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.snippets,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log(
      'Deleted snippet $id (rows: $count)',
      name: 'SnippetDao',
    );
    return count;
  }

  /// Delete every snippet. Cascades to session link table via FK.
  Future<int> deleteAll() async {
    final count = await _db.delete(_db.snippets).go();
    AppLogger.instance.log(
      'Deleted all snippets (rows: $count)',
      name: 'SnippetDao',
    );
    return count;
  }

  // --- Session ↔ Snippet ---

  Future<List<DbSnippet>> getForSession(String sessionId) async {
    final query = _db.select(_db.snippets).join([
      innerJoin(
        _db.sessionSnippets,
        _db.sessionSnippets.snippetId.equalsExp(_db.snippets.id),
      ),
    ]);
    query.where(_db.sessionSnippets.sessionId.equals(sessionId));
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.snippets)).toList();
  }

  Future<void> linkToSession(String snippetId, String sessionId) async {
    await _db
        .into(_db.sessionSnippets)
        .insert(
          SessionSnippetsCompanion.insert(
            sessionId: sessionId,
            snippetId: snippetId,
          ),
        );
  }

  Future<void> unlinkFromSession(String snippetId, String sessionId) async {
    await (_db.delete(_db.sessionSnippets)..where(
          (t) => t.sessionId.equals(sessionId) & t.snippetId.equals(snippetId),
        ))
        .go();
  }
}
