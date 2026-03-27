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

  Future<void> load() async {
    try {
      state = await _store.load();
    } catch (e) {
      AppLogger.instance.log('Failed to load sessions', name: 'SessionProvider', error: e);
    }
  }

  Future<void> add(Session session) async {
    try {
      await _store.add(session);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to add session', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> update(Session session) async {
    try {
      await _store.update(session);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to update session', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _store.delete(id);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to delete session', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<Session> duplicate(String id) async {
    try {
      final copy = await _store.duplicateSession(id);
      state = _store.sessions;
      return copy;
    } catch (e) {
      AppLogger.instance.log('Failed to duplicate session', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> addEmptyGroup(String groupPath) async {
    try {
      await _store.addEmptyGroup(groupPath);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to add group', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> renameGroup(String oldPath, String newPath) async {
    try {
      await _store.renameGroup(oldPath, newPath);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to rename group', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> deleteGroup(String groupPath) async {
    try {
      await _store.deleteGroup(groupPath);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to delete group', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    try {
      await _store.deleteAll();
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to delete all sessions', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> moveSession(String sessionId, String newGroup) async {
    try {
      await _store.moveSession(sessionId, newGroup);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to move session', name: 'SessionProvider', error: e);
      rethrow;
    }
  }

  Future<void> moveGroup(String groupPath, String newParent) async {
    try {
      await _store.moveGroup(groupPath, newParent);
      state = _store.sessions;
    } catch (e) {
      AppLogger.instance.log('Failed to move group', name: 'SessionProvider', error: e);
      rethrow;
    }
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
