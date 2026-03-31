import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/credential_store.dart';
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
final sessionProvider =
    NotifierProvider<SessionNotifier, List<Session>>(SessionNotifier.new);

class SessionNotifier extends Notifier<List<Session>> {
  final SessionHistory _history = SessionHistory();

  @override
  List<Session> build() => [];

  SessionStore get _store => ref.read(sessionStoreProvider);

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  SessionSnapshot _snapshot(String description, {
    Map<String, CredentialData> credentials = const {},
  }) => SessionSnapshot(
    sessions: List.of(_store.sessions),
    emptyGroups: Set.of(_store.emptyGroups),
    description: description,
    credentials: credentials,
  );

  /// Run an undoable store operation: snapshot state, execute, sync.
  Future<T> _runUndoable<T>(String op, Future<T> Function() fn) async {
    _history.pushUndo(_snapshot(op));
    return _run(op, fn);
  }

  /// Run an undoable delete: save credentials before deleting.
  Future<T> _runUndoableDelete<T>(String op, Set<String> ids, Future<T> Function() fn) async {
    final creds = await _store.loadCredentials(ids);
    _history.pushUndo(_snapshot(op, credentials: creds));
    return _run(op, fn);
  }

  /// Run a store operation, sync state, and log on failure.
  Future<T> _run<T>(String op, Future<T> Function() fn) async {
    try {
      final result = await fn();
      state = _store.sessions;
      return result;
    } catch (e) {
      AppLogger.instance.log('Failed to $op', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> load() async {
    try {
      state = await _store.load();
    } catch (e) {
      AppLogger.instance.log('Failed to load sessions', name: 'SessionProvider', error: e);
    }
  }

  Future<void> add(Session session) => _run('add session', () => _store.add(session));
  Future<void> update(Session session) => _run('update session', () => _store.update(session));
  Future<void> delete(String id) => _runUndoableDelete('delete session', {id}, () => _store.delete(id));
  Future<Session> duplicate(String id) => _run('duplicate session', () => _store.duplicateSession(id));
  Future<void> addEmptyGroup(String groupPath) => _run('add group', () => _store.addEmptyGroup(groupPath));
  Future<void> renameGroup(String oldPath, String newPath) => _runUndoable('rename group', () => _store.renameGroup(oldPath, newPath));
  Future<void> deleteGroup(String groupPath) {
    final ids = _store.sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .map((s) => s.id).toSet();
    return _runUndoableDelete('delete group', ids, () => _store.deleteGroup(groupPath));
  }
  Future<void> deleteAll() {
    final ids = _store.sessions.map((s) => s.id).toSet();
    return _runUndoableDelete('delete all', ids, () => _store.deleteAll());
  }
  Future<void> moveSession(String sessionId, String newGroup) => _runUndoable('move session', () => _store.moveSession(sessionId, newGroup));
  Future<void> moveGroup(String groupPath, String newParent) => _runUndoable('move group', () => _store.moveGroup(groupPath, newParent));
  Future<void> deleteMultiple(Set<String> ids) => _runUndoableDelete('delete multiple', ids, () => _store.deleteMultiple(ids));
  Future<void> moveMultiple(Set<String> ids, String newGroup) => _runUndoable('move multiple', () => _store.moveMultiple(ids, newGroup));

  Future<SessionSnapshot> _snapshotWithCreds(String description) async {
    final ids = _store.sessions.map((s) => s.id).toSet();
    final creds = await _store.loadCredentials(ids);
    return _snapshot(description, credentials: creds);
  }

  Future<bool> undo() async {
    final current = await _snapshotWithCreds('current');
    final restored = _history.undo(current);
    if (restored == null) return false;
    await _store.restoreSnapshot(restored.sessions, restored.emptyGroups, restored.credentials);
    state = _store.sessions;
    return true;
  }

  Future<bool> redo() async {
    final current = await _snapshotWithCreds('current');
    final restored = _history.redo(current);
    if (restored == null) return false;
    await _store.restoreSnapshot(restored.sessions, restored.emptyGroups, restored.credentials);
    state = _store.sessions;
    return true;
  }
}

/// Tree built from current session list (includes empty groups).
final sessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyGroups: store.emptyGroups);
});

/// Search query state.
final sessionSearchProvider =
    NotifierProvider<SessionSearchNotifier, String>(SessionSearchNotifier.new);

class SessionSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// Filtered sessions based on search query.
/// Uses [SessionStore.filterSessions] to avoid duplicated filter logic.
final filteredSessionsProvider = Provider<List<Session>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final query = ref.watch(sessionSearchProvider);
  return SessionStore.filterSessions(sessions, query);
});

/// Filtered tree based on search.
final filteredSessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(filteredSessionsProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyGroups: store.emptyGroups);
});
