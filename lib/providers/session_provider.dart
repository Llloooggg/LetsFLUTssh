import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session/session.dart';
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
  @override
  List<Session> build() => [];

  SessionStore get _store => ref.read(sessionStoreProvider);

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
  Future<void> delete(String id) => _run('delete session', () => _store.delete(id));
  Future<Session> duplicate(String id) => _run('duplicate session', () => _store.duplicateSession(id));
  Future<void> addEmptyGroup(String groupPath) => _run('add group', () => _store.addEmptyGroup(groupPath));
  Future<void> renameGroup(String oldPath, String newPath) => _run('rename group', () => _store.renameGroup(oldPath, newPath));
  Future<void> deleteGroup(String groupPath) => _run('delete group', () => _store.deleteGroup(groupPath));
  Future<void> deleteAll() => _run('delete all sessions', () => _store.deleteAll());
  Future<void> moveSession(String sessionId, String newGroup) => _run('move session', () => _store.moveSession(sessionId, newGroup));
  Future<void> moveGroup(String groupPath, String newParent) => _run('move group', () => _store.moveGroup(groupPath, newParent));
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
final filteredSessionsProvider = Provider<List<Session>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final query = ref.watch(sessionSearchProvider);
  if (query.isEmpty) return sessions;
  final q = query.toLowerCase();
  return sessions.where((s) {
    return s.label.toLowerCase().contains(q) ||
        s.group.toLowerCase().contains(q) ||
        s.host.toLowerCase().contains(q) ||
        s.user.toLowerCase().contains(q);
  }).toList();
});

/// Filtered tree based on search.
final filteredSessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(filteredSessionsProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyGroups: store.emptyGroups);
});
