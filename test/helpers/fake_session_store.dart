import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// In-memory SessionStore that works without path_provider.
class FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions;
  final Set<String> _fakeEmptyFolders;

  FakeSessionStore({List<Session>? sessions, Set<String>? emptyFolders})
    : _fakeSessions = sessions ?? [],
      _fakeEmptyFolders = emptyFolders ?? {};

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyFolders => Set.unmodifiable(_fakeEmptyFolders);

  @override
  Future<List<Session>> load() async => _fakeSessions;

  @override
  List<String> folders() {
    final g = _fakeSessions
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInFolder(String groupPath) {
    return _fakeSessions
        .where(
          (s) => s.folder == groupPath || s.folder.startsWith('$groupPath/'),
        )
        .length;
  }

  @override
  List<Session> byFolder(String folder) {
    return _fakeSessions.where((s) => s.folder == folder).toList();
  }

  @override
  Future<Session> duplicateSession(String id, {String? targetFolder}) async {
    final original = _fakeSessions.firstWhere((s) => s.id == id);
    final copy = Session(
      id: '${original.id}-copy',
      label: '${original.label} (copy)',
      folder: targetFolder ?? original.folder,
      server: ServerAddress(
        host: original.host,
        port: original.port,
        user: original.user,
      ),
      auth: SessionAuth(authType: original.authType),
    );
    _fakeSessions.add(copy);
    return copy;
  }

  @override
  Future<void> add(Session session) async {
    _fakeSessions.add(session);
  }

  @override
  Future<void> update(Session session) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _fakeSessions[idx] = session;
    }
  }

  @override
  Future<void> delete(String id) async {
    _fakeSessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> deleteAll() async {
    _fakeSessions.clear();
    _fakeEmptyFolders.clear();
  }

  @override
  Future<void> deleteFolder(String groupPath) async {
    _fakeSessions.removeWhere(
      (s) => s.folder == groupPath || s.folder.startsWith('$groupPath/'),
    );
    _fakeEmptyFolders.remove(groupPath);
  }

  @override
  Future<void> addEmptyFolder(String groupPath) async {
    _fakeEmptyFolders.add(groupPath);
  }

  @override
  Future<void> renameFolder(String oldPath, String newPath) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      final s = _fakeSessions[i];
      if (s.folder == oldPath) {
        _fakeSessions[i] = s.copyWith(folder: newPath);
      } else if (s.folder.startsWith('$oldPath/')) {
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
  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _fakeSessions[idx] = _fakeSessions[idx].copyWith(folder: newFolder);
    }
  }

  @override
  Future<void> moveFolder(String groupPath, String newParent) async {
    final name = groupPath.split('/').last;
    final newPath = newParent.isEmpty ? name : '$newParent/$name';
    await renameFolder(groupPath, newPath);
  }

  @override
  Future<void> deleteMultiple(Set<String> ids) async {
    _fakeSessions.removeWhere((s) => ids.contains(s.id));
  }

  @override
  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    for (var i = 0; i < _fakeSessions.length; i++) {
      if (ids.contains(_fakeSessions[i].id)) {
        _fakeSessions[i] = _fakeSessions[i].copyWith(folder: newFolder);
      }
    }
  }

  @override
  Future<void> restoreSnapshot(
    List<Session> sessions,
    Set<String> emptyFolders,
  ) async {
    _fakeSessions
      ..clear()
      ..addAll(sessions);
    _fakeEmptyFolders
      ..clear()
      ..addAll(emptyFolders);
  }
}

/// A FakeSessionStore that can throw on specific operations.
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
