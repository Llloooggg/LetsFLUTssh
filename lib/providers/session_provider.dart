import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/db/_folder_path_compat.dart';
import '../core/db/mappers.dart';
import '../core/session/session.dart';
import '../core/session/session_history.dart';
import '../core/session/session_tree.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/db.dart' as rust_db;
import '../src/rust/api/sessions.dart' as rust_sess;
import '../src/rust/api/sessions_registry.dart' as rust_registry;
import '../utils/logger.dart';

/// Single source of truth for session state. Owns the in-memory cache
/// (sessions, emptyFolders, collapsedFolders, folder map), the FRB
/// `letsflutssh.db` write pipeline, the bus subscription that re-hydrates
/// the cache after Rust-side mutations (bulk import etc.), and the
/// undo/redo history.
///
/// Replaces the prior two-tier `Provider<SessionStore>` +
/// `NotifierProvider<SessionNotifier>` split. The data layer is FRB
/// (rusqlite + `sessions::Registry`); this Notifier is the thin Dart
/// cache + writeback adapter.
///
/// Failures from FRB calls (DB locked / native lib missing in unit
/// tests) are caught at every entry point and degrade to the same
/// empty-result / no-op semantics the legacy `_db == null` branch
/// used to expose. Live persistence coverage moves to integration_test.
final sessionProvider = NotifierProvider<SessionNotifier, List<Session>>(
  SessionNotifier.new,
);

/// Derived O(1)-by-id session map. Rebuilds whenever
/// [sessionProvider] mutates; consumers should use
/// `ref.watch(sessionsByIdProvider.select((m) => m[id]))` so the
/// dependent widget rebuilds only when *its specific* session
/// changes — instead of every list-mutation forcing every
/// `firstWhere`-scanning consumer to rebuild + re-scan O(N).
///
/// Replaces the O(N²) pattern where every per-row widget
/// (`SessionViaBadge`, anything resolving `via_session_id` →
/// label) ran a fresh `firstWhere` on every parent list
/// rebuild — at 1000 sessions that's 1 000 000 string compares
/// per refresh, visible as a sidebar lag.
final sessionsByIdProvider = Provider<Map<String, Session>>((ref) {
  final list = ref.watch(sessionProvider);
  return {for (final s in list) s.id: s};
});

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
  // Lazy — `SessionHistory()` constructor calls into the Rust
  // actor, which requires `RustLib` to be initialised. Test seams
  // (`FakeSessionNotifier`) override `build()` and never read the
  // history surface, so they avoid the FRB hop entirely. The
  // production path lazily mints the actor on first access via
  // [_historyOrInit].
  SessionHistory? _history;
  final Set<String> _emptyFolders = {};
  final Set<String> _collapsedFolders = {};
  Map<String, rust_db.DbFolder> _folderMap = {};
  Future<List<Session>>? _loadFuture;
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  @override
  List<Session> build() {
    // Subscribe to the global Sessions topic so any FRB-side
    // mutation (including bulk-import paths) refreshes the cache.
    // The subscribe call hits the FRB native lib at construction
    // time; flutter_test contexts that don't load the lib raise
    // synchronously. Catch + log so the notifier stays usable in
    // tests with mocked DAOs.
    try {
      _busSub = AppBus.instance.subscribe(rust_bus.BusTopic.sessions).listen((
        event,
      ) {
        if (event is rust_bus.BusEvent_SessionsChanged) {
          unawaited(reload());
        }
      });
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier bus subscribe failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
    ref.onDispose(() {
      unawaited(_busSub?.cancel());
      _busSub = null;
      _history?.dispose();
      _history = null;
    });
    return [];
  }

  /// Lazily mint the Rust-side history actor. First call hits the
  /// FRB boundary; subsequent calls reuse the handle. Test seams
  /// that override `build` without touching undo/redo never reach
  /// this getter, so they don't need FRB loaded.
  SessionHistory _historyOrInit() => _history ??= SessionHistory();

  // ── Public read accessors ────────────────────────────────────────

  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);
  Set<String> get collapsedFolders => Set.unmodifiable(_collapsedFolders);

  bool get canUndo => _history?.canUndo ?? false;
  bool get canRedo => _history?.canRedo ?? false;

  /// Resolve a folder path string to its DB folder ID.
  /// Returns null if the path is empty or not found.
  String? folderIdByPath(String path) => findFolderIdByPath(path, _folderMap);

  Session? get(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ── Cache lifecycle ──────────────────────────────────────────────

  /// Force a reload from the DB on the next [load] call. Used by the
  /// bus subscriber (above) to drop the cached future after a
  /// `SessionsChanged` event so the next read picks up the new state.
  Future<void> reload() async {
    invalidateCache();
    await load();
  }

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake.
  void invalidateCache() {
    state = const [];
    _emptyFolders.clear();
    _collapsedFolders.clear();
    _folderMap = {};
    _loadFuture = null;
  }

  Future<void> load() async {
    if (_loadFuture != null) {
      await _loadFuture;
      return;
    }
    final future = _doLoad();
    _loadFuture = future;
    try {
      await future;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load sessions',
        name: 'SessionNotifier',
        error: e,
      );
    } finally {
      _loadFuture = null;
      // Clear the loading flag even on failure so the sidebar doesn't
      // stay blank forever if the DB never opens — the empty state is
      // still more honest than a permanent placeholder.
      ref.read(sessionsLoadingProvider.notifier).markIdle();
    }
  }

  Future<List<Session>> _doLoad() async {
    final loaded = <Session>[];
    try {
      // Hydrate from the Rust-side `sessions::Registry` snapshot. The
      // registry is kept in sync by the FRB DAO write paths so the
      // snapshot reflects the latest committed state without an extra
      // DAO round-trip from Dart; `sessionsRegistryReload` forces an
      // initial pull from disk on first load (the registry starts
      // empty).
      await rust_registry.sessionsRegistryReload();
      final view = rust_registry.sessionsRegistrySnapshot();
      _folderMap = buildFolderMap(view.folders);
      loaded.addAll(
        view.sessions.map((s) => dbSessionToSession(s, _folderMap)),
      );
      _emptyFolders
        ..clear()
        ..addAll(view.emptyFolders);
      _collapsedFolders
        ..clear()
        ..addAll(view.collapsedFolders);

      AppLogger.instance.log(
        'Loaded ${loaded.length} sessions, ${_folderMap.length} folders',
        name: 'SessionNotifier',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load sessions',
        name: 'SessionNotifier',
        error: e,
      );
    }
    state = List.of(loaded);
    return loaded;
  }

  // ── CRUD ─────────────────────────────────────────────────────────

  Future<void> add(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    // Optimistic cache update — push a credential-cleared copy so
    // the list view never holds plaintext between this insert and
    // the `SessionsChanged` bus event re-hydrating from the
    // registry snapshot (which itself uses
    // `dbSessionToSession(.., withCredentials: false)`).
    state = [...state, session.withoutCredentials()];
    try {
      final folderId = await resolveFolderPath(session.folder, _folderMap);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier.add failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> update(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    final idx = state.indexWhere((s) => s.id == session.id);
    if (idx < 0) throw ArgumentError('Session not found: ${session.id}');
    // Same credential-clearing rule as `add` — the cache row never
    // carries plaintext.
    final next = [...state];
    next[idx] = session.withoutCredentials();
    state = next;
    try {
      final folderId = await resolveFolderPath(session.folder, _folderMap);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier.update failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  }

  /// Save metadata edits without round-tripping the secret columns
  /// through the Dart heap. Each `*Dirty` flag selects whether the
  /// corresponding credential column is part of the write. The
  /// session model already carries empty strings in
  /// `password` / `keyData` / `passphrase` (the cache view), so the
  /// metadata DAO is enough for the metadata side; secret slots that
  /// got dirty land via `db_sessions_set_secret`.
  Future<void> updatePartial(
    Session session, {
    bool passwordDirty = false,
    bool keyDataDirty = false,
    bool passphraseDirty = false,
  }) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    final idx = state.indexWhere((s) => s.id == session.id);
    if (idx < 0) throw ArgumentError('Session not found: ${session.id}');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final folderId = await resolveFolderPath(session.folder, _folderMap);
      await rust_db.dbSessionsUpdateMetadata(
        metadata: rust_db.DbSessionMetadata(
          id: session.id,
          label: session.label,
          folderId: folderId,
          host: session.host,
          port: session.port,
          user: session.user,
          authType: session.auth.authType.name,
          keyPath: session.auth.keyPath,
          keyId: session.keyId.isEmpty ? null : session.keyId,
          sortOrder: session.sortOrder,
          notes: session.notes,
          extras: jsonEncode(session.extras),
          viaSessionId: session.viaSessionId,
          viaHost: session.viaSessionId != null
              ? null
              : session.viaOverride?.host,
          viaPort: session.viaSessionId != null
              ? null
              : session.viaOverride?.port,
          viaUser: session.viaSessionId != null
              ? null
              : session.viaOverride?.user,
          updatedAtMs: nowMs,
        ),
      );
      if (passwordDirty) {
        await rust_db.dbSessionsSetSecret(
          id: session.id,
          slot: 'password',
          value: session.auth.password,
          updatedAtMs: nowMs,
        );
      }
      if (keyDataDirty) {
        await rust_db.dbSessionsSetSecret(
          id: session.id,
          slot: 'key_data',
          value: session.auth.keyData,
          updatedAtMs: nowMs,
        );
      }
      if (passphraseDirty) {
        await rust_db.dbSessionsSetSecret(
          id: session.id,
          slot: 'passphrase',
          value: session.auth.passphrase,
          updatedAtMs: nowMs,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier.updatePartial failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
      rethrow;
    }
    // Reload to refresh the per-slot `hasStoredX` flags + cached
    // metadata after a partial save (dirty-bit changes shift the
    // saved-or-not indicator state for the next dialog open).
    await load();
  }

  Future<void> delete(String id) => _runUndoable('delete session', () async {
    state = state.where((s) => s.id != id).toList();
    try {
      await rust_db.dbSessionsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier.delete failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  });

  Future<void> deleteMultiple(Set<String> ids) =>
      _runUndoable('delete multiple', () async {
        if (ids.isEmpty) return;
        state = state.where((s) => !ids.contains(s.id)).toList();
        try {
          await rust_db.dbSessionsDeleteMultiple(ids: ids.toList());
        } catch (e) {
          AppLogger.instance.log(
            'SessionNotifier.deleteMultiple failed: $e',
            name: 'SessionNotifier',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> deleteAll() => _runUndoable('delete all', () async {
    state = const [];
    _emptyFolders.clear();
    _collapsedFolders.clear();
    try {
      await rust_db.dbSessionsDeleteAll();
      await rust_db.dbFoldersDeleteAll();
      _folderMap.clear();
    } catch (e) {
      AppLogger.instance.log(
        'SessionNotifier.deleteAll failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  });

  Future<Session> duplicate(String id, {String? targetFolder}) async {
    final original = get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final folderForCopy = targetFolder ?? original.folder;
    // One Rust transaction now owns: source-row lookup, label dedup
    // against the live session list, folder-path ensure, fresh UUID
    // mint, duplicate-row insert. Replaces the prior Dart-side
    // sequence of `unique_label` + `resolveFolderPath` +
    // `dbSessionsDuplicate` round-trips.
    final String newId;
    try {
      newId = await rust_db.dbSessionsDuplicateWithPath(
        srcId: id,
        targetFolderPath: folderForCopy,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.instance.log(
        'duplicate FRB call failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
      rethrow;
    }
    // Re-pull the new row so the in-memory cache picks up the
    // server-of-truth shape — credentials stay Rust-side.
    await load();
    final copy = get(newId);
    if (copy == null) {
      throw StateError('Duplicate session $newId missing after reload');
    }
    return copy;
  }

  Future<void> moveSession(String sessionId, String newFolder) =>
      _runUndoable('move session', () async {
        final idx = state.indexWhere((s) => s.id == sessionId);
        if (idx < 0) return;
        final next = [...state];
        next[idx] = next[idx].copyWith(folder: newFolder);
        state = next;
        try {
          final folderId = await resolveFolderPath(newFolder, _folderMap);
          await rust_db.dbSessionsMoveToFolder(
            sessionId: sessionId,
            folderId: folderId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (e) {
          AppLogger.instance.log(
            'moveSession failed: $e',
            name: 'SessionNotifier',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> moveMultiple(Set<String> ids, String newFolder) =>
      _runUndoable('move multiple', () async {
        if (ids.isEmpty) return;
        final next = <Session>[];
        for (final s in state) {
          next.add(ids.contains(s.id) ? s.copyWith(folder: newFolder) : s);
        }
        state = next;
        try {
          final folderId = await resolveFolderPath(newFolder, _folderMap);
          await rust_db.dbSessionsMoveMultiple(
            ids: ids.toList(),
            folderId: folderId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (e) {
          AppLogger.instance.log(
            'moveMultiple failed: $e',
            name: 'SessionNotifier',
            level: LogLevel.warn,
          );
        }
      });

  // ── Empty folders ───────────────────────────────────────────────

  Future<void> addEmptyFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    _emptyFolders.add(folderPath);
    state = List.of(state);
    AppLogger.instance.log(
      'Added empty folder: $folderPath',
      name: 'SessionNotifier',
    );
    try {
      await resolveFolderPath(folderPath, _folderMap);
    } catch (e) {
      AppLogger.instance.log(
        'addEmptyFolder failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  }

  // ── Collapsed folders ───────────────────────────────────────────

  Future<void> toggleFolderCollapsed(String folderPath) async {
    final wasCollapsed = _collapsedFolders.contains(folderPath);
    if (wasCollapsed) {
      _collapsedFolders.remove(folderPath);
    } else {
      _collapsedFolders.add(folderPath);
    }
    state = List.of(state);
    AppLogger.instance.log(
      'Folder ${wasCollapsed ? 'expanded' : 'collapsed'}: $folderPath',
      name: 'SessionNotifier',
    );
    try {
      final folderId = findFolderIdByPath(folderPath, _folderMap);
      if (folderId != null) {
        await rust_db.dbFoldersToggleCollapsed(id: folderId);
        // Refresh cache row so subsequent reads see the new flag.
        final row = _folderMap[folderId];
        if (row != null) {
          _folderMap[folderId] = rust_db.DbFolder(
            id: row.id,
            name: row.name,
            parentId: row.parentId,
            sortOrder: row.sortOrder,
            collapsed: !row.collapsed,
            createdAtMs: row.createdAtMs,
          );
        }
      }
    } catch (e) {
      AppLogger.instance.log(
        'toggleFolderCollapsed failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  }

  /// Count sessions whose folder equals [folderPath] or sits under
  /// `{folderPath}/`. Routes through the Rust registry's
  /// `sessions_registry_count_in_folder` first (cached view, no
  /// per-call projection); falls back to the projecting
  /// `sessions::count_in_folder` shim when the registry hasn't
  /// been synced yet (typical unit-test path — registry empty but
  /// the Notifier's `state` carries the live session list).
  int countSessionsInFolder(String folderPath) {
    try {
      return rust_registry.sessionsRegistryCountInFolder(
        folderPath: folderPath,
      );
    } catch (_) {
      return rust_sess.sessionsCountInFolder(
        sessionFolders: state.map((s) => s.folder).toList(growable: false),
        folderPath: folderPath,
      );
    }
  }

  // ── Folder operations ───────────────────────────────────────────

  Future<void> renameFolder(String oldPath, String newPath) =>
      _runUndoable('rename folder', () async {
        if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;

        // Optimistic Dart-side cache cascade — the bus event will
        // re-hydrate from the registry snapshot, but the live cache
        // needs to reflect the new path between the FRB call and the
        // bus tick so widgets reading off `state` don't render the
        // old path for a frame.
        final next = <Session>[];
        for (final s in state) {
          if (s.folder == oldPath) {
            next.add(s.copyWith(folder: newPath));
          } else if (s.folder.startsWith('$oldPath/')) {
            next.add(
              s.copyWith(folder: newPath + s.folder.substring(oldPath.length)),
            );
          } else {
            next.add(s);
          }
        }
        state = next;

        final renamedEmpty = folderRenamePathsCascadeCompat(
          _emptyFolders,
          oldPath,
          newPath,
        );
        _emptyFolders
          ..clear()
          ..addAll(renamedEmpty);
        final renamedCollapsed = folderRenamePathsCascadeCompat(
          _collapsedFolders,
          oldPath,
          newPath,
        );
        _collapsedFolders
          ..clear()
          ..addAll(renamedCollapsed);

        // One Rust transaction now resolves the existing folder by
        // path, ensures the new parent path (creating segments as
        // needed), and updates the row. Replaces the prior two-step
        // (`findFolderIdByPath` Dart-side + `dbFoldersUpdateNameParent`
        // with the OLD `parent_id`) which silently failed to re-parent
        // on cross-tree moves.
        try {
          await rust_db.dbFoldersRenamePathCascade(
            oldPath: oldPath,
            newPath: newPath,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          final folders = await rust_db.dbFoldersListAll();
          _folderMap = buildFolderMap(folders);
        } catch (e) {
          AppLogger.instance.log(
            'renameFolder failed: $e',
            name: 'SessionNotifier',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> deleteFolder(String folderPath) =>
      _runUndoable('delete folder', () async {
        if (folderPath.isEmpty) return;
        // Collect every session rooted inside this folder (or any
        // descendant folder) — they have to be DELETED alongside the
        // folder rows. The schema's `sessions.folder_id` foreign key
        // resolves with `ON DELETE SET NULL`, so a folder delete on
        // its own would orphan these sessions into root and the user
        // would see them reappear at the top level on the next reload —
        // contradicting the confirm dialog's "will delete N sessions
        // inside" promise and reading as "delete folder doesn't work".
        final sessionIdsToDelete = state
            .where(
              (s) =>
                  s.folder == folderPath || s.folder.startsWith('$folderPath/'),
            )
            .map((s) => s.id)
            .toSet();
        state = state.where((s) => !sessionIdsToDelete.contains(s.id)).toList();
        _emptyFolders.removeWhere(
          (g) => g == folderPath || g.startsWith('$folderPath/'),
        );
        _collapsedFolders.removeWhere(
          (c) => c == folderPath || c.startsWith('$folderPath/'),
        );
        try {
          if (sessionIdsToDelete.isNotEmpty) {
            await rust_db.dbSessionsDeleteMultiple(
              ids: sessionIdsToDelete.toList(),
            );
          }
          final folderId = findFolderIdByPath(folderPath, _folderMap);
          if (folderId != null) {
            await rust_db.dbFoldersDeleteRecursive(id: folderId);
            final folders = await rust_db.dbFoldersListAll();
            _folderMap = buildFolderMap(folders);
          }
        } catch (e) {
          AppLogger.instance.log(
            'deleteFolder failed: $e',
            name: 'SessionNotifier',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> moveFolder(String folderPath, String newParent) async {
    if (folderPath.isEmpty) return;
    final folderName = folderPath.split('/').last;
    final newPath = newParent.isEmpty ? folderName : '$newParent/$folderName';
    if (newPath == folderPath) return;
    if (newPath.startsWith('$folderPath/')) return;
    await renameFolder(folderPath, newPath);
  }

  /// Deep-duplicate [sourcePath] under [targetParent]: creates a new
  /// folder (with a unique name when the source name collides under
  /// the target), then duplicates every session inside the source
  /// tree to the matching position in the new tree, and registers
  /// every empty subfolder along the way. Pasting a folder onto its
  /// own parent (or root) yields a sibling copy named "X (1)" /
  /// "X (2)" etc.
  ///
  /// Refuses no-op + cycle inputs the same way [moveFolder] does:
  /// duplicating a folder onto a path inside itself would recurse
  /// indefinitely as the loop discovers its own freshly-created
  /// children. Returns silently in that case.
  Future<void> duplicateFolder(String sourcePath, String targetParent) async {
    if (sourcePath.isEmpty) return;
    if (targetParent == sourcePath || targetParent.startsWith('$sourcePath/')) {
      return;
    }
    final sourceName = sourcePath.split('/').last;
    final newName = _uniqueFolderNameUnder(targetParent, sourceName);
    final newRoot = targetParent.isEmpty ? newName : '$targetParent/$newName';

    // Create the destination root folder. addEmptyFolder upserts the
    // DB row + cache + local empty-set in one shot.
    await addEmptyFolder(newRoot);

    // Snapshot the source-side data BEFORE we start adding new rows,
    // otherwise the freshly-created destination folders would feed
    // back into the iteration as we extend the cache.
    final sourceSessions = state
        .where(
          (s) => s.folder == sourcePath || s.folder.startsWith('$sourcePath/'),
        )
        .toList();
    final sourceEmptyFolders = _emptyFolders
        .where((f) => f == sourcePath || f.startsWith('$sourcePath/'))
        .toList();

    // Recreate every empty subfolder. Translates "$sourcePath/X/Y" →
    // "$newRoot/X/Y". Sessions handle their own folder ensure inside
    // [duplicate] (`dbSessionsDuplicateWithPath`), so this only has
    // to cover folders that hold no sessions.
    for (final emptyPath in sourceEmptyFolders) {
      if (emptyPath == sourcePath) continue; // already created above
      final rel = emptyPath.substring(sourcePath.length); // '/X/Y'
      await addEmptyFolder('$newRoot$rel');
    }

    // Duplicate every session under the source tree to its mirror
    // position in the new tree. The transactional Rust helper
    // ensures each session lands with a unique label and folder id.
    for (final session in sourceSessions) {
      final rel = session.folder.substring(sourcePath.length);
      final destFolder = rel.isEmpty ? newRoot : '$newRoot$rel';
      await duplicate(session.id, targetFolder: destFolder);
    }
  }

  /// Pick a folder name that doesn't collide with an existing child
  /// of [parentPath]. Appends "(1)", "(2)", ... until a free name
  /// is found. Used by [duplicateFolder] to mirror file-manager
  /// "Copy of X" semantics without surfacing a Dart-side rename
  /// dialog.
  String _uniqueFolderNameUnder(String parentPath, String baseName) {
    final existingPaths = <String>{
      ..._emptyFolders,
      for (final f in _folderMap.values) _composeFolderPath(f, _folderMap),
    };
    bool collides(String name) {
      final p = parentPath.isEmpty ? name : '$parentPath/$name';
      return existingPaths.contains(p);
    }

    if (!collides(baseName)) return baseName;
    for (var i = 1; i < 1000; i++) {
      final candidate = '$baseName ($i)';
      if (!collides(candidate)) return candidate;
    }
    return '$baseName (${DateTime.now().millisecondsSinceEpoch})';
  }

  /// Walk parent_id chain backwards to reconstruct the slash-joined
  /// path of [f]. Used by [_uniqueFolderNameUnder] to build the
  /// "exists" set.
  String _composeFolderPath(
    rust_db.DbFolder f,
    Map<String, rust_db.DbFolder> map,
  ) {
    final segments = <String>[];
    var cur = f;
    while (true) {
      segments.add(cur.name);
      final parentId = cur.parentId;
      if (parentId == null) break;
      final parent = map[parentId];
      if (parent == null) break;
      cur = parent;
    }
    return segments.reversed.join('/');
  }

  // ── Snapshot / restore (for undo) ───────────────────────────────

  Future<void> _restoreSnapshot(
    List<Session> sessions,
    Set<String> emptyFolders,
  ) async {
    // Same credential-clearing rule as `add` / `update` — undo
    // history snapshots may carry credential-bearing copies (the
    // history snapshot is built off the live cache, which may have
    // been hydrated with credentials by `loadWithCredentials` for a
    // recent edit dialog). Restore must not re-introduce them.
    state = sessions.map((s) => s.withoutCredentials()).toList();
    _emptyFolders
      ..clear()
      ..addAll(emptyFolders);

    // One Rust transaction now wipes live sessions + folders,
    // rebuilds the folder tree from the snapshot's session paths
    // + bare empty-folder list, and re-inserts every session under
    // the freshly-resolved folder id. Replaces the Dart
    // delete-all + N× resolveFolderPath + N× upsert + M×
    // resolveFolderPath fan-out.
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await rust_db.dbSessionsRestoreSnapshot(
        sessions: [
          for (final s in sessions)
            rust_db.DbRestoreSessionInput(
              id: s.id,
              label: s.label,
              folderPath: s.folder,
              host: s.host,
              port: s.port,
              user: s.user,
              authType: s.authType.name,
              password: s.password,
              keyPath: s.keyPath,
              keyData: s.keyData,
              keyId: s.keyId.isEmpty ? null : s.keyId,
              passphrase: s.passphrase,
              sortOrder: s.sortOrder,
              notes: s.notes,
              lastConnectedAtMs: s.lastConnectedAtMs,
              extras: s.extras.isEmpty ? '' : jsonEncode(s.extras),
              viaSessionId: (s.viaSessionId == null || s.viaSessionId!.isEmpty)
                  ? null
                  : s.viaSessionId,
              viaHost: s.viaOverride?.host,
              viaPort: s.viaOverride?.port,
              viaUser: s.viaOverride?.user,
              createdAtMs: s.createdAt.millisecondsSinceEpoch,
              updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
            ),
        ],
        emptyFolderPaths: emptyFolders.toList(growable: false),
        nowMs: nowMs,
      );
      // Refresh the folder cache so subsequent reads see the
      // post-restore tree without waiting for the bus tick.
      final folders = await rust_db.dbFoldersListAll();
      _folderMap = buildFolderMap(folders);
    } catch (e) {
      AppLogger.instance.log(
        'restoreSnapshot failed: $e',
        name: 'SessionNotifier',
        level: LogLevel.warn,
      );
    }
  }

  // ── Query ───────────────────────────────────────────────────────

  /// Distinct, sorted list of named folders referenced by any
  /// session in the cache. Routes through the Rust registry's
  /// `sessions_registry_distinct_folders` first (cache read, no
  /// per-call projection); falls back to the projecting
  /// `sessions::distinct_folders` shim when the registry hasn't
  /// been synced yet (typical unit-test path).
  List<String> folders() {
    try {
      return rust_registry.sessionsRegistryDistinctFolders();
    } catch (_) {
      return rust_sess.sessionsDistinctFolders(
        sessionFolders: state.map((s) => s.folder).toList(growable: false),
      );
    }
  }

  /// Cached sessions whose folder equals [folder] exactly (no
  /// prefix match — use [countSessionsInFolder] for the
  /// recursive count). Routes through the registry's
  /// `sessions_registry_ids_by_exact_folder` (cache read, no
  /// Dart-side scan per call) when available; falls back to the
  /// inline filter for flutter_test contexts.
  List<Session> byFolder(String folder) {
    try {
      final ids = rust_registry
          .sessionsRegistryIdsByExactFolder(folderPath: folder)
          .toSet();
      if (ids.isEmpty) return const <Session>[];
      return state.where((s) => ids.contains(s.id)).toList();
    } catch (_) {
      return state.where((s) => s.folder == folder).toList();
    }
  }

  // ── Undo / redo ─────────────────────────────────────────────────

  SessionSnapshot _snapshot(String description) => SessionSnapshot(
    sessions: List.of(state),
    emptyFolders: Set.of(_emptyFolders),
    description: description,
  );

  /// Run an undoable store operation: snapshot state, execute, sync.
  Future<T> _runUndoable<T>(String op, Future<T> Function() fn) async {
    _historyOrInit().pushUndo(_snapshot(op));
    try {
      return await fn();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to $op',
        name: 'SessionNotifier',
        error: e,
      );
      rethrow;
    }
  }

  Future<bool> undo() async {
    final current = _snapshot('current');
    final restored = _historyOrInit().undo(current);
    if (restored == null) return false;
    await _restoreSnapshot(restored.sessions, restored.emptyFolders);
    return true;
  }

  Future<bool> redo() async {
    final current = _snapshot('current');
    final restored = _historyOrInit().redo(current);
    if (restored == null) return false;
    await _restoreSnapshot(restored.sessions, restored.emptyFolders);
    return true;
  }
}

/// Case-insensitive substring search across (label, folder, host,
/// user). Routes through `lfs_core::sessions::filter_sessions` so
/// the four-field grammar lives one place; falls back to the
/// equivalent Dart predicate when the FRB native lib is not
/// loaded (flutter_test contexts that mock the DAOs).
List<Session> filterSessions(List<Session> sessions, String query) {
  if (query.isEmpty) return sessions;
  try {
    final projection = sessions
        .map(
          (s) => rust_sess.DbSearchableSession(
            id: s.id,
            label: s.label,
            folder: s.folder,
            host: s.host,
            user: s.user,
          ),
        )
        .toList(growable: false);
    final ids = rust_sess
        .sessionsFilter(items: projection, query: query)
        .toSet();
    return sessions.where((s) => ids.contains(s.id)).toList();
  } catch (_) {
    final q = query.toLowerCase();
    return sessions.where((s) {
      return s.label.toLowerCase().contains(q) ||
          s.folder.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q) ||
          s.user.toLowerCase().contains(q);
    }).toList();
  }
}

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
///
/// Routes through the registry's `sessions_registry_filter_ids`
/// when the FRB native lib is loaded — that path reads off the
/// cached view, avoiding the per-keystroke
/// `DbSearchableSession` projection that
/// [filterSessions] rebuilds. Falls back to the projecting helper
/// for flutter_test contexts.
final filteredSessionsProvider = Provider<List<Session>>((ref) {
  final sessions = ref.watch(sessionProvider);
  final query = ref.watch(sessionSearchProvider);
  if (query.isEmpty) return sessions;
  try {
    final ids = rust_registry.sessionsRegistryFilterIds(query: query).toSet();
    if (ids.isEmpty) return const <Session>[];
    return sessions.where((s) => ids.contains(s.id)).toList();
  } catch (_) {
    return filterSessions(sessions, query);
  }
});

/// Filtered tree based on search.
final filteredSessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(filteredSessionsProvider);
  // Watch sessionProvider so emptyFolders mutations (which rebuild
  // state via `state = List.of(state)`) re-trigger this Provider.
  ref.watch(sessionProvider);
  final notifier = ref.read(sessionProvider.notifier);
  return SessionTree.build(sessions, emptyFolders: notifier.emptyFolders);
});
