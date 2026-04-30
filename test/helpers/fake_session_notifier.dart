import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';

/// In-memory [SessionNotifier] that bypasses the FRB native lib so
/// tests can exercise the controller surface without bootstrapping
/// `lfs_core.db`. All CRUD lands in two private collections; the
/// public API matches the production notifier.
class FakeSessionNotifier extends SessionNotifier {
  FakeSessionNotifier({List<Session>? sessions, Set<String>? emptyFolders})
    : _initial = List.of(sessions ?? const <Session>[]),
      _fakeEmptyFolders = Set.of(emptyFolders ?? const <String>{});

  final List<Session> _initial;
  final Set<String> _fakeEmptyFolders;

  @override
  List<Session> build() {
    state = List.of(_initial);
    return state;
  }

  @override
  Set<String> get emptyFolders => Set.unmodifiable(_fakeEmptyFolders);

  @override
  Future<void> load() async {
    state = List.of(_initial);
  }

  @override
  List<String> folders() {
    final g = state
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInFolder(String folderPath) {
    if (folderPath.isEmpty) return state.where((s) => s.folder.isEmpty).length;
    final prefix = '$folderPath/';
    return state
        .where((s) => s.folder == folderPath || s.folder.startsWith(prefix))
        .length;
  }

  @override
  List<Session> byFolder(String folder) {
    return state.where((s) => s.folder == folder).toList();
  }

  @override
  Future<Session> duplicate(String id, {String? targetFolder}) async {
    final original = state.firstWhere((s) => s.id == id);
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
    state = [...state, copy];
    return copy;
  }

  @override
  Future<void> add(Session session) async {
    state = [...state, session];
  }

  @override
  Future<void> update(Session session) async {
    final idx = state.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      final next = [...state];
      next[idx] = session;
      state = next;
    }
  }

  @override
  Future<void> updatePartial(
    Session session, {
    bool passwordDirty = false,
    bool keyDataDirty = false,
    bool passphraseDirty = false,
  }) async {
    final idx = state.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      final next = [...state];
      next[idx] = session;
      state = next;
    }
  }

  @override
  Future<void> delete(String id) async {
    state = state.where((s) => s.id != id).toList();
  }

  @override
  Future<void> deleteAll() async {
    state = const [];
    _fakeEmptyFolders.clear();
  }

  @override
  Future<void> deleteFolder(String folderPath) async {
    state = state
        .where(
          (s) => s.folder != folderPath && !s.folder.startsWith('$folderPath/'),
        )
        .toList();
    _fakeEmptyFolders.remove(folderPath);
  }

  @override
  Future<void> addEmptyFolder(String folderPath) async {
    _fakeEmptyFolders.add(folderPath);
  }

  @override
  Future<void> renameFolder(String oldPath, String newPath) async {
    final next = <Session>[];
    for (final s in state) {
      if (s.folder == oldPath) {
        next.add(s.copyWith(folder: newPath));
      } else if (s.folder.startsWith('$oldPath/')) {
        next.add(s.copyWith(folder: s.folder.replaceFirst(oldPath, newPath)));
      } else {
        next.add(s);
      }
    }
    state = next;
    if (_fakeEmptyFolders.remove(oldPath)) {
      _fakeEmptyFolders.add(newPath);
    }
  }

  @override
  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = state.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      final next = [...state];
      next[idx] = next[idx].copyWith(folder: newFolder);
      state = next;
    }
  }

  @override
  Future<void> moveFolder(String folderPath, String newParent) async {
    final name = folderPath.split('/').last;
    final newPath = newParent.isEmpty ? name : '$newParent/$name';
    await renameFolder(folderPath, newPath);
  }

  @override
  Future<void> deleteMultiple(Set<String> ids) async {
    state = state.where((s) => !ids.contains(s.id)).toList();
  }

  // Undo/redo no-ops so widget tests can fire `Ctrl+Z` / `Ctrl+Y`
  // shortcuts without dragging in the Rust-side `SessionHistory`
  // actor. The production `SessionNotifier.undo` / `redo` route
  // through `lfs_core::session_history` (FRB sync); test seams
  // bypass that surface entirely.
  @override
  Future<bool> undo() async => false;

  @override
  Future<bool> redo() async => false;

  @override
  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    final next = <Session>[];
    for (final s in state) {
      next.add(ids.contains(s.id) ? s.copyWith(folder: newFolder) : s);
    }
    state = next;
  }
}

/// Empty test seam: an instance of [SessionNotifier] that ships with
/// no sessions and no FRB hookup. Equivalent to `FakeSessionNotifier()`
/// with explicit empty defaults — used by widget tests that just need
/// the provider wired but don't care about contents.
class StaticSessionNotifier extends FakeSessionNotifier {
  StaticSessionNotifier() : super();
}

/// A [FakeSessionNotifier] that can throw on specific operations.
class ThrowingSessionNotifier extends FakeSessionNotifier {
  bool shouldThrowOnLoad = false;
  bool shouldThrowOnAdd = false;

  @override
  Future<void> load() async {
    if (shouldThrowOnLoad) throw Exception('load failed');
    return super.load();
  }

  @override
  Future<void> add(Session session) async {
    if (shouldThrowOnAdd) throw Exception('add failed');
    return super.add(session);
  }
}
