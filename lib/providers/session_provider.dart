import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session/session.dart';
import '../core/session/session_store.dart';
import '../core/session/session_tree.dart';

/// Global session store instance.
final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore();
});

/// Session list state — loaded async, notifies on changes.
final sessionProvider =
    StateNotifierProvider<SessionNotifier, List<Session>>((ref) {
  return SessionNotifier(ref.watch(sessionStoreProvider));
});

class SessionNotifier extends StateNotifier<List<Session>> {
  final SessionStore _store;

  SessionNotifier(this._store) : super([]);

  Future<void> load() async {
    state = await _store.load();
  }

  Future<void> add(Session session) async {
    await _store.add(session);
    state = _store.sessions;
  }

  Future<void> update(Session session) async {
    await _store.update(session);
    state = _store.sessions;
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    state = _store.sessions;
  }

  Future<Session> duplicate(String id) async {
    final copy = await _store.duplicateSession(id);
    state = _store.sessions;
    return copy;
  }

  Future<void> addEmptyGroup(String groupPath) async {
    await _store.addEmptyGroup(groupPath);
    // Trigger rebuild by re-assigning state.
    state = _store.sessions;
  }
}

/// Tree built from current session list (includes empty groups).
final sessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final store = ref.watch(sessionStoreProvider);
  return SessionTree.build(sessions, emptyGroups: store.emptyGroups);
});

/// Search query state.
final sessionSearchProvider = StateProvider<String>((ref) => '');

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
