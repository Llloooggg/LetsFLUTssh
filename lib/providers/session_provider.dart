import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session/session.dart';
import '../core/session/session_history.dart';
import '../core/session/session_store.dart';
import '../core/session/session_tree.dart';
import '../utils/logger.dart';

/// Global session store instance.
final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore();
});

/// Session list state — loaded async, notifies on changes.
final sessionProvider = NotifierProvider<SessionNotifier, List<Session>>(
  SessionNotifier.new,
);

/// True while the very first [SessionNotifier.load] is in flight and
/// has not completed yet. The sidebar treats this as "render a blank
/// placeholder instead of the empty-state" so cold-start doesn't
/// flash "No sessions" for ~1 s before the rows paint.
///
/// Default is `true` (loading) so the very first frame shows the
/// blank placeholder even before [_bootstrap] reaches `load()` on its
/// post-frame callback. [SessionNotifier.load] flips the flag back to
/// `false` in its `finally` block (success or failure — the empty
/// state is more honest than a permanent placeholder).
///
/// Tests that pre-populate sessions via [PrePopulatedSessionNotifier]
/// must include
/// `sessionsLoadingProvider.overrideWith(IdleSessionsLoadingNotifier.new)`
/// in their `ProviderScope` overrides — otherwise the sidebar stays on
/// the placeholder because no `load()` ever runs.
final sessionsLoadingProvider = NotifierProvider<SessionsLoadingNotifier, bool>(
  SessionsLoadingNotifier.new,
);

class SessionsLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void markLoading() => state = true;
  void markIdle() => state = false;
}

class SessionNotifier extends Notifier<List<Session>> {
  final SessionHistory _history = SessionHistory();

  @override
  List<Session> build() => [];

  SessionStore get _store => ref.read(sessionStoreProvider);

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  SessionSnapshot _snapshot(String description) => SessionSnapshot(
    sessions: List.of(_store.sessions),
    emptyFolders: Set.of(_store.emptyFolders),
    description: description,
  );

  /// Run an undoable store operation: snapshot state, execute, sync.
  Future<T> _runUndoable<T>(String op, Future<T> Function() fn) async {
    _history.pushUndo(_snapshot(op));
    return _run(op, fn);
  }

  /// Run a store operation, sync state, and log on failure.
  Future<T> _run<T>(String op, Future<T> Function() fn) async {
    try {
      final result = await fn();
      state = _store.sessions;
      return result;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to $op',
        name: 'SessionProvider',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> load() async {
    try {
      state = await _store.load();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load sessions',
        name: 'SessionProvider',
        error: e,
      );
    } finally {
      // Clear the loading flag even on failure so the sidebar doesn't
      // stay blank forever if the DB never opens — the empty state is
      // still more honest than a permanent placeholder.
      ref.read(sessionsLoadingProvider.notifier).markIdle();
    }
  }

  Future<void> add(Session session) =>
      _run('add session', () => _store.add(session));
  Future<void> update(Session session) =>
      _run('update session', () => _store.update(session));
  Future<void> delete(String id) =>
      _runUndoable('delete session', () => _store.delete(id));
  Future<Session> duplicate(String id, {String? targetFolder}) => _run(
    'duplicate session',
    () => _store.duplicateSession(id, targetFolder: targetFolder),
  );
  Future<void> addEmptyFolder(String folderPath) =>
      _run('add folder', () => _store.addEmptyFolder(folderPath));
  Future<void> renameFolder(String oldPath, String newPath) => _runUndoable(
    'rename folder',
    () => _store.renameFolder(oldPath, newPath),
  );
  Future<void> deleteFolder(String folderPath) =>
      _runUndoable('delete folder', () => _store.deleteFolder(folderPath));

  Future<void> deleteAll() =>
      _runUndoable('delete all', () => _store.deleteAll());

  Future<void> moveSession(String sessionId, String newFolder) => _runUndoable(
    'move session',
    () => _store.moveSession(sessionId, newFolder),
  );
  Future<void> moveFolder(String folderPath, String newParent) => _runUndoable(
    'move folder',
    () => _store.moveFolder(folderPath, newParent),
  );
  Future<void> deleteMultiple(Set<String> ids) =>
      _runUndoable('delete multiple', () => _store.deleteMultiple(ids));
  Future<void> moveMultiple(Set<String> ids, String newFolder) =>
      _runUndoable('move multiple', () => _store.moveMultiple(ids, newFolder));

  Future<bool> undo() async {
    final current = _snapshot('current');
    final restored = _history.undo(current);
    if (restored == null) return false;
    await _store.restoreSnapshot(restored.sessions, restored.emptyFolders);
    state = _store.sessions;
    return true;
  }

  Future<bool> redo() async {
    final current = _snapshot('current');
    final restored = _history.redo(current);
    if (restored == null) return false;
    await _store.restoreSnapshot(restored.sessions, restored.emptyFolders);
    state = _store.sessions;
    return true;
  }
}

/// Tree built from current session list (includes empty groups).
final sessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyFolders: store.emptyFolders);
});

/// Search query state.
final sessionSearchProvider = NotifierProvider<SessionSearchNotifier, String>(
  SessionSearchNotifier.new,
);

class SessionSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// Filtered sessions based on search query.
final filteredSessionsProvider = Provider<List<Session>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final query = ref.watch(sessionSearchProvider);
  return SessionStore.filterSessions(sessions, query);
});

/// Filtered tree based on search.
final filteredSessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(filteredSessionsProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyFolders: store.emptyFolders);
});
