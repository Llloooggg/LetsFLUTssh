import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/snippets/snippet.dart';
import '../src/rust/api/db.dart' as rust_db;
import '../utils/logger.dart';

/// All snippets — loaded from `letsflutssh.db` on first access. Mutations
/// route through the [SnippetsNotifier] CRUD methods which invalidate
/// local state + the per-session family provider below.
///
/// Replaces the prior two-tier `Provider<SnippetStore>` +
/// `FutureProvider<List<Snippet>>` split — the AsyncNotifier owns
/// the FRB read/write pipeline directly, so widgets that already
/// consume the AsyncValue surface keep their `.when()` blocks.
final snippetsProvider = AsyncNotifierProvider<SnippetsNotifier, List<Snippet>>(
  SnippetsNotifier.new,
);

/// Snippets pinned to a specific session.
final sessionSnippetsProvider = FutureProvider.family<List<Snippet>, String>((
  ref,
  sessionId,
) async {
  return _fetchAndSort(
    () => rust_db.dbSnippetsListForSession(sessionId: sessionId),
  );
});

class SnippetsNotifier extends AsyncNotifier<List<Snippet>> {
  @override
  Future<List<Snippet>> build() async =>
      _fetchAndSort(rust_db.dbSnippetsListAll);

  /// Save a new snippet. Idempotent — Rust uses ON CONFLICT(id).
  Future<void> add(Snippet snippet) => _upsert(snippet);

  /// Save edits to an existing snippet — same backing call as [add].
  /// Renamed from `update` to avoid clobbering [AsyncNotifier.update].
  Future<void> save(Snippet snippet) => _upsert(snippet);

  Future<void> _upsert(Snippet snippet) async {
    try {
      await rust_db.dbSnippetsUpsert(row: _toRow(snippet));
    } catch (e) {
      AppLogger.instance.log(
        'Snippet upsert failed: $e',
        name: 'SnippetsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    ref.invalidate(sessionSnippetsProvider);
  }

  Future<void> delete(String id) async {
    try {
      await rust_db.dbSnippetsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'Snippet delete failed: $e',
        name: 'SnippetsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    ref.invalidate(sessionSnippetsProvider);
  }

  /// Drop every snippet. Cascades to `session_snippets` via FK.
  Future<void> deleteAll() async {
    try {
      await rust_db.dbSnippetsDeleteAll();
    } catch (e) {
      AppLogger.instance.log(
        'Snippet deleteAll failed: $e',
        name: 'SnippetsNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
    ref.invalidate(sessionSnippetsProvider);
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
        name: 'SnippetsNotifier',
      );
    }
    ref.invalidate(sessionSnippetsProvider(sessionId));
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
        name: 'SnippetsNotifier',
      );
    }
    ref.invalidate(sessionSnippetsProvider(sessionId));
  }

  /// IDs of snippets pinned to a session.
  Future<Set<String>> linkedSnippetIds(String sessionId) async {
    try {
      final ids = await rust_db.dbSessionSnippetsListIds(sessionId: sessionId);
      return ids.toSet();
    } catch (e) {
      AppLogger.instance.log(
        'linkedSnippetIds failed: $e',
        name: 'SnippetsNotifier',
        level: LogLevel.warn,
      );
      return const <String>{};
    }
  }

  /// Force a re-pull from the DB. Used by post-import refresh paths
  /// where the Rust apply layer wrote rows directly.
  Future<List<Snippet>> loadAll() async {
    ref.invalidateSelf();
    return future;
  }

  static rust_db.DbSnippet _toRow(Snippet s) => rust_db.DbSnippet(
    id: s.id,
    title: s.title,
    command: s.command,
    description: s.description,
    createdAtMs: s.createdAt.millisecondsSinceEpoch,
    updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
  );
}

Snippet _toSnippet(rust_db.DbSnippet r) => Snippet(
  id: r.id,
  title: r.title,
  command: r.command,
  description: r.description,
  createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAtMs),
);

Future<List<Snippet>> _fetchAndSort(
  Future<List<rust_db.DbSnippet>> Function() fetch,
) async {
  try {
    final rows = await fetch();
    final list = rows.map(_toSnippet).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return list;
  } catch (e) {
    AppLogger.instance.log(
      'Snippet fetch failed: $e',
      name: 'SnippetsNotifier',
      level: LogLevel.warn,
    );
    return const [];
  }
}
