import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// Fake SessionStore that works in-memory without path_provider.
class FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions = [];
  final Set<String> _fakeEmptyGroups = {};

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyGroups => Set.unmodifiable(_fakeEmptyGroups);

  @override
  Future<List<Session>> load() async => _fakeSessions;

  @override
  Future<void> add(Session session) async {
    _fakeSessions.add(session);
  }

  @override
  Future<void> update(Session session) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) _fakeSessions[idx] = session;
  }

  @override
  Future<void> delete(String id) async {
    _fakeSessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<Session> duplicateSession(String id) async {
    final original = _fakeSessions.firstWhere((s) => s.id == id);
    final copy = Session(id: '${original.id}-copy', label: '${original.label} (Copy)', group: original.group, server: ServerAddress(host: original.host, port: original.port, user: original.user));
    _fakeSessions.add(copy);
    return copy;
  }

  @override
  Future<void> addEmptyGroup(String groupPath) async {
    _fakeEmptyGroups.add(groupPath);
  }

  @override
  Future<void> renameGroup(String oldPath, String newPath) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      final s = _fakeSessions[i];
      if (s.group == oldPath || s.group.startsWith('$oldPath/')) {
        _fakeSessions[i] = s.copyWith(
          group: s.group.replaceFirst(oldPath, newPath),
        );
      }
    }
    if (_fakeEmptyGroups.remove(oldPath)) {
      _fakeEmptyGroups.add(newPath);
    }
  }

  @override
  Future<void> deleteGroup(String groupPath) async {
    _fakeSessions.removeWhere(
      (s) => s.group == groupPath || s.group.startsWith('$groupPath/'),
    );
    _fakeEmptyGroups.remove(groupPath);
  }

  @override
  Future<void> deleteAll() async {
    _fakeSessions.clear();
    _fakeEmptyGroups.clear();
  }

  @override
  Future<void> moveSession(String sessionId, String newGroup) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _fakeSessions[idx] = _fakeSessions[idx].copyWith(group: newGroup);
    }
  }

  @override
  Future<void> moveGroup(String groupPath, String newParent) async {
    final name = groupPath.split('/').last;
    final newPath = newParent.isEmpty ? name : '$newParent/$name';
    await renameGroup(groupPath, newPath);
  }
}

void main() {
  Session makeSession({
    String id = 's1',
    String label = 'Test',
    String group = '',
    String host = '10.0.0.1',
    String user = 'root',
  }) {
    return Session(id: id, label: label, group: group, server: ServerAddress(host: host, user: user));
  }

  group('SessionNotifier', () {
    late FakeSessionStore store;
    late ProviderContainer container;
    late SessionNotifier notifier;

    setUp(() {
      store = FakeSessionStore();
      container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      notifier = container.read(sessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty list', () {
      expect(notifier.state, isEmpty);
    });

    test('load updates state', () async {
      await notifier.load();
      expect(notifier.state, isEmpty);
    });

    test('add inserts session', () async {
      final session = makeSession();
      await notifier.add(session);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 's1');
    });

    test('update modifies session', () async {
      await notifier.add(makeSession(id: 's1', label: 'Original'));
      await notifier.update(makeSession(id: 's1', label: 'Updated'));
      expect(notifier.state.first.label, 'Updated');
    });

    test('delete removes session', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.add(makeSession(id: 's2', label: 'Other'));
      await notifier.delete('s1');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 's2');
    });

    test('duplicate creates copy', () async {
      await notifier.add(makeSession(id: 's1', label: 'Original'));
      final copy = await notifier.duplicate('s1');
      expect(copy.id, 's1-copy');
      expect(copy.label, 'Original (Copy)');
      expect(notifier.state.length, 2);
    });

    test('addEmptyGroup adds group', () async {
      await notifier.addEmptyGroup('Production/Web');
      expect(store.emptyGroups, contains('Production/Web'));
    });

    test('renameGroup renames sessions in group', () async {
      await notifier.add(makeSession(id: 's1', group: 'Old'));
      await notifier.renameGroup('Old', 'New');
      expect(notifier.state.first.group, 'New');
    });

    test('deleteGroup removes group and sessions', () async {
      await notifier.add(makeSession(id: 's1', group: 'ToDelete'));
      await notifier.add(makeSession(id: 's2', group: 'Keep'));
      await notifier.deleteGroup('ToDelete');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.group, 'Keep');
    });

    test('deleteAll clears everything', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.add(makeSession(id: 's2'));
      await notifier.addEmptyGroup('Group');
      await notifier.deleteAll();
      expect(notifier.state, isEmpty);
      expect(store.emptyGroups, isEmpty);
    });

    test('moveSession changes group', () async {
      await notifier.add(makeSession(id: 's1', group: 'Old'));
      await notifier.moveSession('s1', 'New');
      expect(notifier.state.first.group, 'New');
    });

    test('moveGroup changes group path', () async {
      await notifier.add(makeSession(id: 's1', group: 'A'));
      await notifier.moveGroup('A', 'Parent');
      expect(notifier.state.first.group, 'Parent/A');
    });
  });

  group('session providers with ProviderContainer', () {
    test('sessionStoreProvider returns SessionStore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(sessionStoreProvider);
      expect(store, isA<SessionStore>());
    });

    test('sessionProvider starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sessions = container.read(sessionProvider);
      expect(sessions, isEmpty);
    });

    test('sessionSearchProvider starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final query = container.read(sessionSearchProvider);
      expect(query, isEmpty);
    });

    test('filteredSessionsProvider returns all when no search', () {
      final store = FakeSessionStore();
      final container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered, isEmpty);
    });

    test('filteredSessionsProvider filters by label', () async {
      final store = FakeSessionStore();
      final container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      // Add sessions via the notifier
      final notifier = container.read(sessionProvider.notifier);
      await notifier.add(makeSession(id: 's1', label: 'Production'));
      await notifier.add(makeSession(id: 's2', label: 'Staging'));

      // Set search query
      container.read(sessionSearchProvider.notifier).set('prod');
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.label, 'Production');
    });

    test('filteredSessionsProvider filters by host', () async {
      final store = FakeSessionStore();
      final container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      await notifier.add(makeSession(id: 's1', host: '10.0.0.1'));
      await notifier.add(makeSession(id: 's2', host: '192.168.1.1'));

      container.read(sessionSearchProvider.notifier).set('192');
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.host, '192.168.1.1');
    });

    test('sessionTreeProvider builds tree', () async {
      final store = FakeSessionStore();
      final container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(sessionProvider.notifier);
      await notifier.add(makeSession(id: 's1', group: 'Web'));
      final tree = container.read(sessionTreeProvider);
      expect(tree, isNotEmpty);
    });
  });
}
