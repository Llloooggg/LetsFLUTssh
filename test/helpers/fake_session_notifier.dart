import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';

/// In-memory session-workspace fake. Wraps the
/// [SessionWorkspaceSnapshot] data flow so widget tests can mount
/// SessionPanel-style consumers without bootstrapping `lfs_core.db`.
///
/// Provides the same CRUD surface the production [SessionMutator]
/// exposes, but mutates the in-memory list directly + re-emits the
/// snapshot stream. The Riverpod scope wires both
/// [sessionsWorkspaceStreamProvider] and [sessionMutatorProvider]
/// off the same instance so reads + writes stay in sync.
class FakeSessionNotifier {
  FakeSessionNotifier({List<Session>? sessions, Set<String>? emptyFolders})
    : _sessions = List.of(sessions ?? const <Session>[]),
      _emptyFolders = Set.of(emptyFolders ?? const <String>{});

  final List<Session> _sessions;
  final Set<String> _emptyFolders;
  final _controller = StreamController<SessionWorkspaceSnapshot>.broadcast();

  /// Read-only synchronous mirror of the in-memory state. Production
  /// notifier exposed `state` for tests; the new shape keeps the same
  /// surface so existing assertions (`expect(notifier.state, ...)`)
  /// don't have to be rewritten.
  List<Session> get state => List.of(_sessions);

  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);

  SessionWorkspaceSnapshot snapshot() => SessionWorkspaceSnapshot(
    sessions: List.of(_sessions),
    emptyFolders: Set.of(_emptyFolders),
    collapsedFolders: const {},
    folderMap: const {},
  );

  /// Builds a fresh stream that emits the current snapshot first
  /// (so Riverpod's `StreamProviderRef.future` resolves on the next
  /// microtask) and then forwards every subsequent mutation tick
  /// from [_controller]. Constructed via [Stream.multi] so the
  /// initial emit lands synchronously inside the listener's first
  /// pull.
  Stream<SessionWorkspaceSnapshot> watchSnapshots() {
    return Stream.multi((controller) {
      controller.add(snapshot());
      final sub = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(snapshot());
  }

  /// Build the override list to drop into a [ProviderContainer] or
  /// `ProviderScope`. Three providers route through this fake:
  /// - [sessionWorkspaceProvider] returns the current synchronous
  ///   snapshot (no async gap — widget tests render the right
  ///   sessions on the first frame without pumpAndSettle).
  /// - [sessionsWorkspaceStreamProvider] forwards subsequent
  ///   mutation ticks so anything that listens to the stream
  ///   directly (StreamProviderRef.future / .when) still works.
  /// - [sessionMutatorProvider] adapts to the in-memory fake so
  ///   `ref.read(sessionMutatorProvider).add(...)` mutates the same
  ///   data the workspace Provider exposes.
  List<Override> overrides() {
    return [
      sessionsWorkspaceStreamProvider.overrideWith((ref) => watchSnapshots()),
      sessionWorkspaceProvider.overrideWith((ref) {
        // Re-read the latest snapshot whenever the stream emits — the
        // sub on the broadcast controller doubles as a "dirty" signal,
        // bumping the listener so a `ref.watch(sessionProvider)` sees
        // the updated count without a microtask hop.
        final sub = _controller.stream.listen((_) {
          ref.invalidateSelf();
        });
        ref.onDispose(sub.cancel);
        return snapshot();
      }),
      sessionMutatorProvider.overrideWith(
        (ref) => _FakeSessionMutator(this, ref),
      ),
    ];
  }

  // ── CRUD ─────────────────────────────────────────────────────────

  Future<void> load() async {
    _emit();
  }

  Future<void> add(Session session) async {
    _sessions.add(session);
    _emit();
  }

  Future<void> update(Session session) async {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _sessions[idx] = session;
      _emit();
    }
  }

  Future<void> updatePartial(
    Session session, {
    bool passwordDirty = false,
    bool keyDataDirty = false,
    bool passphraseDirty = false,
  }) async {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _sessions[idx] = session;
      _emit();
    }
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    _emit();
  }

  Future<void> deleteAll() async {
    _sessions.clear();
    _emptyFolders.clear();
    _emit();
  }

  Future<void> deleteFolder(String folderPath) async {
    _sessions.removeWhere(
      (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
    );
    _emptyFolders.remove(folderPath);
    _emit();
  }

  Future<void> addEmptyFolder(String folderPath) async {
    _emptyFolders.add(folderPath);
    _emit();
  }

  Future<void> renameFolder(String oldPath, String newPath) async {
    for (var i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.folder == oldPath) {
        _sessions[i] = s.copyWith(folder: newPath);
      } else if (s.folder.startsWith('$oldPath/')) {
        _sessions[i] = s.copyWith(
          folder: s.folder.replaceFirst(oldPath, newPath),
        );
      }
    }
    if (_emptyFolders.remove(oldPath)) {
      _emptyFolders.add(newPath);
    }
    _emit();
  }

  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx >= 0) {
      _sessions[idx] = _sessions[idx].copyWith(folder: newFolder);
      _emit();
    }
  }

  Future<void> moveFolder(String folderPath, String newParent) async {
    final name = folderPath.split('/').last;
    final newPath = newParent.isEmpty ? name : '$newParent/$name';
    await renameFolder(folderPath, newPath);
  }

  Future<void> deleteMultiple(Set<String> ids) async {
    _sessions.removeWhere((s) => ids.contains(s.id));
    _emit();
  }

  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    for (var i = 0; i < _sessions.length; i++) {
      if (ids.contains(_sessions[i].id)) {
        _sessions[i] = _sessions[i].copyWith(folder: newFolder);
      }
    }
    _emit();
  }

  Future<Session> duplicate(String id, {String? targetFolder}) async {
    final original = _sessions.firstWhere((s) => s.id == id);
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
    _sessions.add(copy);
    _emit();
    return copy;
  }

  Future<void> duplicateFolder(String sourcePath, String targetParent) async {
    if (sourcePath.isEmpty) return;
    if (targetParent == sourcePath || targetParent.startsWith('$sourcePath/')) {
      return;
    }
    final sourceName = sourcePath.split('/').last;
    final newRoot = targetParent.isEmpty
        ? sourceName
        : '$targetParent/$sourceName';
    // Snapshot before mutation so the loop doesn't pick up the new
    // rows it creates.
    final sourceSessions = List.of(
      _sessions.where(
        (s) => s.folder == sourcePath || s.folder.startsWith('$sourcePath/'),
      ),
    );
    final sourceEmpty = List.of(
      _emptyFolders.where(
        (f) => f == sourcePath || f.startsWith('$sourcePath/'),
      ),
    );
    _emptyFolders.add(newRoot);
    for (final empty in sourceEmpty) {
      if (empty == sourcePath) continue;
      final rel = empty.substring(sourcePath.length);
      _emptyFolders.add('$newRoot$rel');
    }
    for (final s in sourceSessions) {
      final rel = s.folder.substring(sourcePath.length);
      final destFolder = rel.isEmpty ? newRoot : '$newRoot$rel';
      _sessions.add(
        Session(
          id: '${s.id}-copy',
          label: '${s.label} (copy)',
          folder: destFolder,
          server: ServerAddress(host: s.host, port: s.port, user: s.user),
          auth: SessionAuth(authType: s.authType),
        ),
      );
    }
    _emit();
  }

  Future<bool> undo() async => false;
  Future<bool> redo() async => false;

  /// Dispose the underlying broadcast controller. Tests that own a
  /// long-lived ProviderContainer call this in `tearDown`.
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// Adapter wiring the fake's mutation methods into the
/// [SessionMutator] surface the production code reads from. The
/// fake's in-memory list IS the source of truth, so the mutator
/// is a thin pass-through.
class _FakeSessionMutator extends SessionMutator {
  _FakeSessionMutator(this._fake, super.ref);

  final FakeSessionNotifier _fake;

  @override
  Session? get(String id) {
    for (final s in _fake._sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  List<String> folders() {
    final g = _fake._sessions
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInFolder(String folderPath) {
    if (folderPath.isEmpty) {
      return _fake._sessions.where((s) => s.folder.isEmpty).length;
    }
    final prefix = '$folderPath/';
    return _fake._sessions
        .where((s) => s.folder == folderPath || s.folder.startsWith(prefix))
        .length;
  }

  @override
  List<Session> byFolder(String folder) {
    return _fake._sessions.where((s) => s.folder == folder).toList();
  }

  @override
  String? folderIdByPath(String path) => null;

  @override
  Future<void> add(Session session) => _fake.add(session);

  @override
  Future<void> update(Session session) => _fake.update(session);

  @override
  Future<void> updatePartial(
    Session session, {
    bool passwordDirty = false,
    bool keyDataDirty = false,
    bool passphraseDirty = false,
  }) => _fake.updatePartial(
    session,
    passwordDirty: passwordDirty,
    keyDataDirty: keyDataDirty,
    passphraseDirty: passphraseDirty,
  );

  @override
  Future<void> delete(String id) => _fake.delete(id);

  @override
  Future<void> deleteAll() => _fake.deleteAll();

  @override
  Future<void> deleteFolder(String folderPath) =>
      _fake.deleteFolder(folderPath);

  @override
  Future<void> addEmptyFolder(String folderPath) =>
      _fake.addEmptyFolder(folderPath);

  @override
  Future<void> renameFolder(String oldPath, String newPath) =>
      _fake.renameFolder(oldPath, newPath);

  @override
  Future<void> moveSession(String sessionId, String newFolder) =>
      _fake.moveSession(sessionId, newFolder);

  @override
  Future<void> moveFolder(String folderPath, String newParent) =>
      _fake.moveFolder(folderPath, newParent);

  @override
  Future<void> deleteMultiple(Set<String> ids) => _fake.deleteMultiple(ids);

  @override
  Future<void> moveMultiple(Set<String> ids, String newFolder) =>
      _fake.moveMultiple(ids, newFolder);

  @override
  Future<Session> duplicate(String id, {String? targetFolder}) =>
      _fake.duplicate(id, targetFolder: targetFolder);

  @override
  Future<void> duplicateFolder(String sourcePath, String targetParent) =>
      _fake.duplicateFolder(sourcePath, targetParent);

  @override
  Future<bool> undo() => _fake.undo();

  @override
  Future<bool> redo() => _fake.redo();

  @override
  Future<void> toggleFolderCollapsed(String folderPath) async {}
}

/// Empty test seam — equivalent to `FakeSessionNotifier()` with
/// explicit empty defaults.
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
