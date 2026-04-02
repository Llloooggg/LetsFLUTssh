import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/credential_store.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

class ThrowingSessionStore extends FakeSessionStore {
  bool shouldThrowOnLoad = false;
  bool shouldThrowOnAdd = false;

  @override
  Future<List<Session>> load() async {
    if (shouldThrowOnLoad) throw Exception('load failed');
    return super.load();
  }

  @override
  Future<void> add(Session session) async {
    if (shouldThrowOnAdd) throw Exception('add failed');
    return super.add(session);
  }
}

/// Fake SessionStore that works in-memory without path_provider.
class FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions = [];
  final Set<String> _fakeEmptyFolders = {};

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyFolders => Set.unmodifiable(_fakeEmptyFolders);

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
    final copy = Session(id: '${original.id}-copy', label: '${original.label} (Copy)', folder: original.folder, server: ServerAddress(host: original.host, port: original.port, user: original.user));
    _fakeSessions.add(copy);
    return copy;
  }

  @override
  Future<void> addEmptyFolder(String groupPath) async {
    _fakeEmptyFolders.add(groupPath);
  }

  @override
  Future<void> renameFolder(String oldPath, String newPath) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      final s = _fakeSessions[i];
      if (s.folder == oldPath || s.folder.startsWith('$oldPath/')) {
        _fakeSessions[i] = s.copyWith(
          folder: s.folder.replaceFirst(oldPath, newPath),
        );
      }
    }
    if (_fakeEmptyFolders.remove(oldPath)) {
      _fakeEmptyFolders.add(newPath);
    }
  }

  @override
  Future<void> deleteFolder(String groupPath) async {
    _fakeSessions.removeWhere(
      (s) => s.folder == groupPath || s.folder.startsWith('$groupPath/'),
    );
    _fakeEmptyFolders.remove(groupPath);
  }

  @override
  Future<void> deleteAll() async {
    _fakeSessions.clear();
    _fakeEmptyFolders.clear();
  }

  @override
  Future<void> moveSession(String sessionId, String newGroup) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _fakeSessions[idx] = _fakeSessions[idx].copyWith(folder: newGroup);
    }
  }

  @override
  Future<void> moveFolder(String groupPath, String newParent) async {
    final name = groupPath.split('/').last;
    final newPath = newParent.isEmpty ? name : '$newParent/$name';
    await renameFolder(groupPath, newPath);
  }

  @override
  Future<Map<String, CredentialData>> loadCredentials(Set<String> ids) async => {};

  @override
  Future<void> restoreSnapshot(List<Session> sessions, Set<String> emptyFolders, [Map<String, CredentialData> credentials = const {}]) async {
    _fakeSessions
      ..clear()
      ..addAll(sessions);
    _fakeEmptyFolders
      ..clear()
      ..addAll(emptyFolders);
  }

}

void main() {
  Session makeSession({
    String id = 's1',
    String label = 'Test',
    String folder = '',
    String host = '10.0.0.1',
    String user = 'root',
  }) {
    return Session(id: id, label: label, folder: folder, server: ServerAddress(host: host, user: user));
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

    test('addEmptyFolder adds folder', () async {
      await notifier.addEmptyFolder('Production/Web');
      expect(store.emptyFolders, contains('Production/Web'));
    });

    test('renameFolder renames sessions in folder', () async {
      await notifier.add(makeSession(id: 's1', folder: 'Old'));
      await notifier.renameFolder('Old', 'New');
      expect(notifier.state.first.folder, 'New');
    });

    test('deleteFolder removes folder and sessions', () async {
      await notifier.add(makeSession(id: 's1', folder: 'ToDelete'));
      await notifier.add(makeSession(id: 's2', folder: 'Keep'));
      await notifier.deleteFolder('ToDelete');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.folder, 'Keep');
    });

    test('deleteAll clears everything', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.add(makeSession(id: 's2'));
      await notifier.addEmptyFolder('Group');
      await notifier.deleteAll();
      expect(notifier.state, isEmpty);
      expect(store.emptyFolders, isEmpty);
    });

    test('moveSession changes folder', () async {
      await notifier.add(makeSession(id: 's1', folder: 'Old'));
      await notifier.moveSession('s1', 'New');
      expect(notifier.state.first.folder, 'New');
    });

    test('moveFolder changes folder path', () async {
      await notifier.add(makeSession(id: 's1', folder: 'A'));
      await notifier.moveFolder('A', 'Parent');
      expect(notifier.state.first.folder, 'Parent/A');
    });

    test('canUndo is false initially', () {
      expect(notifier.canUndo, isFalse);
    });

    test('canRedo is false initially', () {
      expect(notifier.canRedo, isFalse);
    });

    test('canUndo is true after delete', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.delete('s1');
      expect(notifier.canUndo, isTrue);
    });

    test('canRedo is true after undo', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.delete('s1');
      await notifier.undo();
      expect(notifier.canRedo, isTrue);
    });

    test('undo restores deleted session', () async {
      await notifier.add(makeSession(id: 's1', label: 'ToRestore'));
      await notifier.delete('s1');
      expect(notifier.state, isEmpty);
      final result = await notifier.undo();
      expect(result, isTrue);
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, 's1');
    });

    test('undo returns false when nothing to undo', () async {
      final result = await notifier.undo();
      expect(result, isFalse);
    });

    test('redo restores after undo', () async {
      await notifier.add(makeSession(id: 's1'));
      await notifier.delete('s1');
      await notifier.undo();
      expect(notifier.state.length, 1);
      final result = await notifier.redo();
      expect(result, isTrue);
      expect(notifier.state, isEmpty);
    });

    test('redo returns false when nothing to redo', () async {
      final result = await notifier.redo();
      expect(result, isFalse);
    });
  });

  group('SessionNotifier error paths', () {
    late ThrowingSessionStore store;
    late ProviderContainer container;
    late SessionNotifier notifier;

    setUp(() {
      store = ThrowingSessionStore();
      container = ProviderContainer(overrides: [
        sessionStoreProvider.overrideWithValue(store),
      ]);
      notifier = container.read(sessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('_run rethrows on operation failure', () async {
      store.shouldThrowOnAdd = true;
      expect(
        () => notifier.add(makeSession(id: 's1')),
        throwsA(isA<Exception>()),
      );
    });

    test('load catches error and keeps state unchanged', () async {
      store.shouldThrowOnLoad = true;
      await notifier.load();
      expect(notifier.state, isEmpty);
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
      await notifier.add(makeSession(id: 's1', folder: 'Web'));
      final tree = container.read(sessionTreeProvider);
      expect(tree, isNotEmpty);
    });
  });
}
