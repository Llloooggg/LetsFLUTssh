import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/db/mappers.dart';
import '../core/session/session.dart';
import '../core/session/session_history.dart';
import '../core/session/session_tree.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/db.dart' as rust_db;
import '../src/rust/api/sessions.dart' as rust_sess;
import '../src/rust/api/sessions_registry.dart' as rust_registry;
import '../utils/logger.dart';

/// Typed payload broadcast by [_sessionsWorkspaceStreamProvider]: the
/// flat session list, the materialised empty-folder set, the
/// folder-collapsed set, and the id→DbFolder map. One snapshot per
/// `BusEvent::SessionsChanged` Rust-side tick — no Dart-cached drift.
class SessionWorkspaceSnapshot {
  const SessionWorkspaceSnapshot({
    required this.sessions,
    required this.emptyFolders,
    required this.collapsedFolders,
    required this.folderMap,
  });

  /// Sentinel for pre-FRB / pre-first-load / test contexts.
  static const empty = SessionWorkspaceSnapshot(
    sessions: <Session>[],
    emptyFolders: <String>{},
    collapsedFolders: <String>{},
    folderMap: <String, rust_db.DbFolder>{},
  );

  final List<Session> sessions;
  final Set<String> emptyFolders;
  final Set<String> collapsedFolders;
  final Map<String, rust_db.DbFolder> folderMap;
}

/// Stream of [SessionWorkspaceSnapshot]s. Yields:
///   1. An initial snapshot pulled via FRB from the Rust registry.
///   2. A fresh snapshot on every `BusEvent::SessionsChanged` tick.
///
/// The Rust side is the single source of truth: every mutation goes
/// through FRB (`db_sessions_*`, `db_folders_*`), Rust publishes
/// `SessionsChanged`, this stream re-fetches. No Dart-cached state.
///
/// Cold-start: the provider mounts on the first runApp frame, which
/// sits between FRB init and `securityController.bootstrap` (DB
/// open). The first `_loadSnapshot` therefore races `db_init` and
/// reads back `"db not initialized"` from the FRB layer — this
/// path returns [SessionWorkspaceSnapshot.empty] silently, and the
/// `SessionsChanged` event the post-unlock cascade publishes once
/// `db_init` lands drives the first real load. Pre-FRB-init contexts
/// (flutter_test without the native lib loaded) catch the
/// `StateError` through the same branch.
final sessionsWorkspaceStreamProvider =
    StreamProvider<SessionWorkspaceSnapshot>((ref) async* {
      yield await _loadSnapshot();
      await for (final event in AppBus.instance.subscribe(
        rust_bus.BusTopic.sessions,
      )) {
        if (event is rust_bus.BusEvent_SessionsChanged) {
          yield await _loadSnapshot();
        }
      }
    });

/// Fetch the current snapshot from the Rust `sessions::Registry` view.
/// All failure modes degrade to [SessionWorkspaceSnapshot.empty] — the
/// sidebar stays usable on pre-FRB / DB-missing / locked-tier reads.
Future<SessionWorkspaceSnapshot> _loadSnapshot() async {
  try {
    await rust_registry.sessionsRegistryReload();
    final view = rust_registry.sessionsRegistrySnapshot();
    final folderMap = buildFolderMap(view.folders);
    // Build a session-id → flags lookup once so the per-session
    // mapping stays O(1). `credentialFlags` is a parallel list keyed
    // by session_id; rare for it to outsize the session list.
    final flagsById = <String, rust_db.DbSessionCredentialFlags>{
      for (final f in view.credentialFlags) f.sessionId: f,
    };
    final sessions = view.sessions
        .map(
          (s) => dbSessionToSession(
            s,
            folderMap,
            credentialFlags: flagsById[s.id],
          ),
        )
        .toList(growable: false);
    AppLogger.instance.log(
      'Loaded ${sessions.length} sessions, ${folderMap.length} folders',
      name: 'SessionWorkspace',
    );
    return SessionWorkspaceSnapshot(
      sessions: sessions,
      emptyFolders: view.emptyFolders.toSet(),
      collapsedFolders: view.collapsedFolders.toSet(),
      folderMap: folderMap,
    );
  } catch (e) {
    // Cold-start race: the provider mounts before the post-unlock
    // cascade runs `db_init`. The post-unlock `SessionsChanged`
    // publish re-enters this function with the DB ready, so the
    // pre-init read is an expected step — degrade to empty without
    // surfacing it as an error. Mirrors `SshKeysMutator.loadAllMetadata`.
    if (e.toString().contains('db not initialized')) {
      return SessionWorkspaceSnapshot.empty;
    }
    AppLogger.instance.log(
      'Failed to load sessions snapshot',
      name: 'SessionWorkspace',
      error: e,
      level: LogLevel.warn,
    );
    return SessionWorkspaceSnapshot.empty;
  }
}

/// Synchronous view of the latest [SessionWorkspaceSnapshot]. Yields
/// [SessionWorkspaceSnapshot.empty] while the first stream emission
/// is in flight or the stream is in an error state — consumers that
/// need the loading / error discriminant watch
/// [sessionsWorkspaceStreamProvider] directly.
final sessionWorkspaceProvider = Provider<SessionWorkspaceSnapshot>((ref) {
  final async = ref.watch(sessionsWorkspaceStreamProvider);
  return async.hasValue
      ? async.value as SessionWorkspaceSnapshot
      : SessionWorkspaceSnapshot.empty;
});

/// Backwards-compatible flat session list — derived from the
/// workspace snapshot so every `ref.watch(sessionProvider)` keeps
/// working while the data flow itself goes Rust → stream → derived
/// Provider. Same shape, zero Dart-cached state.
final sessionProvider = Provider<List<Session>>((ref) {
  return ref.watch(sessionWorkspaceProvider).sessions;
});

/// Folder paths the user has materialised without a session inside —
/// `_emptyFolders` set in the previous Dart-cached store, now a
/// derived slice of the Rust-owned snapshot.
final emptyFoldersProvider = Provider<Set<String>>((ref) {
  return ref.watch(sessionWorkspaceProvider).emptyFolders;
});

/// Folder paths the user has collapsed in the sidebar — derived
/// from the Rust-owned `folders.collapsed` column via the workspace
/// snapshot. UI toggles route through [SessionMutator.toggleFolderCollapsed],
/// which calls `dbFoldersToggleCollapsed` Rust-side; the publish on
/// success re-flows the stream.
final collapsedFoldersProvider = Provider<Set<String>>((ref) {
  return ref.watch(sessionWorkspaceProvider).collapsedFolders;
});

/// Derived O(1)-by-id session map. Rebuilds whenever the snapshot
/// stream emits; consumers should use
/// `ref.watch(sessionsByIdProvider.select((m) => m[id]))` so the
/// dependent widget rebuilds only when *its specific* session
/// changes — instead of every list-mutation forcing every
/// `firstWhere`-scanning consumer to rebuild + re-scan O(N).
final sessionsByIdProvider = Provider<Map<String, Session>>((ref) {
  final list = ref.watch(sessionProvider);
  return {for (final s in list) s.id: s};
});

/// True while the workspace stream has not produced its first
/// emission yet. The sidebar treats this as "render a blank
/// placeholder instead of the empty-state" so cold-start doesn't
/// flash "No sessions" for ~1 s before the rows paint.
final sessionsLoadingProvider = Provider<bool>((ref) {
  final async = ref.watch(sessionsWorkspaceStreamProvider);
  // `isLoading` is false once the first emission lands (success or
  // error). `hasError` paths still flip the loading flag off so the
  // sidebar drops the placeholder and renders the empty state — more
  // honest than a permanent placeholder.
  return async.isLoading && !async.hasValue && !async.hasError;
});

/// Pure-FRB mutator surface. No Dart-cached state — every method is a
/// thin pass-through to `letsflutssh.db` write paths. After each
/// successful FRB write, Rust publishes `BusEvent::SessionsChanged`
/// on the global bus; [sessionsWorkspaceStreamProvider] re-fetches
/// the snapshot, every derived provider re-emits, every widget
/// consumer rebuilds.
///
/// Undo/redo handle the Rust-side `session_history` actor; the
/// handle is minted lazily on first use and torn down when the
/// Provider tears down.
class SessionMutator {
  SessionMutator(this._ref);

  final Ref _ref;
  SessionHistory? _history;

  /// Lazily mint the Rust-side history actor. First call hits the
  /// FRB boundary; subsequent calls reuse the handle. Test seams
  /// override [SessionMutator] entirely so they never hit this path.
  SessionHistory _historyOrInit() => _history ??= SessionHistory();

  /// Read the current snapshot. Sync — backed by the Provider derived
  /// from the stream. Used internally by mutator paths that need to
  /// short-circuit on a missing row (`delete` / `moveSession`) or
  /// compute a transactional input (`_restoreSnapshot`,
  /// `duplicateFolder`).
  SessionWorkspaceSnapshot get _snap => _ref.read(sessionWorkspaceProvider);

  // ── Public read accessors (notifier-style passthrough) ──────────

  bool get canUndo => _history?.canUndo ?? false;
  bool get canRedo => _history?.canRedo ?? false;

  /// Resolve a folder path string to its DB folder ID. Returns null
  /// if the path is empty or not found.
  String? folderIdByPath(String path) =>
      findFolderIdByPath(path, _snap.folderMap);

  /// Lookup a session by id from the current snapshot. Returns null
  /// when the session is not present (already deleted, snapshot
  /// pre-load).
  Session? get(String id) {
    for (final s in _snap.sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Distinct, sorted list of named folders referenced by any
  /// session in the snapshot. Routes through the Rust registry's
  /// `sessions_registry_distinct_folders` first (cache read, no
  /// per-call projection); falls back to the projecting shim when
  /// the registry hasn't been synced yet.
  List<String> folders() {
    try {
      return rust_registry.sessionsRegistryDistinctFolders();
    } catch (_) {
      return rust_sess.sessionsDistinctFolders(
        sessionFolders: _snap.sessions
            .map((s) => s.folder)
            .toList(growable: false),
      );
    }
  }

  /// Sessions whose folder equals [folder] exactly (no prefix
  /// match — use [countSessionsInFolder] for the recursive count).
  /// Routes through the registry's
  /// `sessions_registry_ids_by_exact_folder` (cache read, no
  /// Dart-side scan per call) when available; falls back to the
  /// inline filter for flutter_test contexts.
  List<Session> byFolder(String folder) {
    try {
      final ids = rust_registry
          .sessionsRegistryIdsByExactFolder(folderPath: folder)
          .toSet();
      if (ids.isEmpty) return const <Session>[];
      return _snap.sessions.where((s) => ids.contains(s.id)).toList();
    } catch (_) {
      return _snap.sessions.where((s) => s.folder == folder).toList();
    }
  }

  /// Count sessions whose folder equals [folderPath] or sits under
  /// `{folderPath}/`. Routes through the Rust registry first;
  /// falls back to the projecting shim when the registry hasn't
  /// been synced yet.
  int countSessionsInFolder(String folderPath) {
    try {
      return rust_registry.sessionsRegistryCountInFolder(
        folderPath: folderPath,
      );
    } catch (_) {
      return rust_sess.sessionsCountInFolder(
        sessionFolders: _snap.sessions
            .map((s) => s.folder)
            .toList(growable: false),
        folderPath: folderPath,
      );
    }
  }

  // ── CRUD ─────────────────────────────────────────────────────────

  Future<void> add(Session session) async {
    final error = rust_sess.sessionsValidateFields(
      host: session.host,
      port: session.port,
      user: session.user,
    );
    if (error != null) throw ArgumentError(error);
    try {
      final folderId = await resolveFolderPath(session.folder);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionMutator.add failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> update(Session session) async {
    final error = rust_sess.sessionsValidateFields(
      host: session.host,
      port: session.port,
      user: session.user,
    );
    if (error != null) throw ArgumentError(error);
    if (get(session.id) == null) {
      throw ArgumentError('Session not found: ${session.id}');
    }
    try {
      final folderId = await resolveFolderPath(session.folder);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionMutator.update failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  }

  /// Save metadata edits without round-tripping the secret columns
  /// through the Dart heap. Each `*Dirty` flag selects whether the
  /// corresponding credential column is part of the write.
  Future<void> updatePartial(
    Session session, {
    bool passwordDirty = false,
    bool keyDataDirty = false,
    bool passphraseDirty = false,
  }) async {
    final error = rust_sess.sessionsValidateFields(
      host: session.host,
      port: session.port,
      user: session.user,
    );
    if (error != null) throw ArgumentError(error);
    if (get(session.id) == null) {
      throw ArgumentError('Session not found: ${session.id}');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final folderId = await resolveFolderPath(session.folder);
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
          extras: extrasMapToJson(session.extras),
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
        'SessionMutator.updatePartial failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
      rethrow;
    }
  }

  Future<void> delete(String id) => _runUndoable('delete session', () async {
    try {
      await rust_db.dbSessionsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'SessionMutator.delete failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  });

  Future<void> deleteMultiple(Set<String> ids) =>
      _runUndoable('delete multiple', () async {
        if (ids.isEmpty) return;
        try {
          await rust_db.dbSessionsDeleteMultiple(ids: ids.toList());
        } catch (e) {
          AppLogger.instance.log(
            'SessionMutator.deleteMultiple failed: $e',
            name: 'SessionMutator',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> deleteAll() => _runUndoable('delete all', () async {
    try {
      await rust_db.dbSessionsDeleteAll();
      await rust_db.dbFoldersDeleteAll();
    } catch (e) {
      AppLogger.instance.log(
        'SessionMutator.deleteAll failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  });

  Future<Session> duplicate(String id, {String? targetFolder}) async {
    final original = get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final folderForCopy = targetFolder ?? original.folder;
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
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
      rethrow;
    }
    // Re-fetch straight from the Rust registry, NOT the Riverpod
    // snapshot. Rust publishes `SessionsChanged` inside the duplicate
    // call, but the Dart `sessionsWorkspaceStreamProvider` consumes that
    // event off a broadcast stream and re-loads on a later event-loop
    // turn — so `get(newId)` (which reads the cached snapshot) is still
    // pre-insert when this await returns, and would spuriously throw even
    // though the row is already in the DB. A direct `_loadSnapshot()`
    // reload reads the source of truth now.
    final snapshot = await _loadSnapshot();
    Session? copy;
    for (final s in snapshot.sessions) {
      if (s.id == newId) {
        copy = s;
        break;
      }
    }
    if (copy == null) {
      throw StateError('Duplicate session $newId missing after insert');
    }
    return copy;
  }

  Future<void> moveSession(String sessionId, String newFolder) =>
      _runUndoable('move session', () async {
        if (get(sessionId) == null) return;
        try {
          final folderId = await resolveFolderPath(newFolder);
          await rust_db.dbSessionsMoveToFolder(
            sessionId: sessionId,
            folderId: folderId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (e) {
          AppLogger.instance.log(
            'moveSession failed: $e',
            name: 'SessionMutator',
            level: LogLevel.warn,
          );
        }
      });

  Future<void> moveMultiple(Set<String> ids, String newFolder) =>
      _runUndoable('move multiple', () async {
        if (ids.isEmpty) return;
        try {
          final folderId = await resolveFolderPath(newFolder);
          await rust_db.dbSessionsMoveMultiple(
            ids: ids.toList(),
            folderId: folderId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (e) {
          AppLogger.instance.log(
            'moveMultiple failed: $e',
            name: 'SessionMutator',
            level: LogLevel.warn,
          );
        }
      });

  // ── Empty folders ───────────────────────────────────────────────

  Future<void> addEmptyFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    AppLogger.instance.log(
      'Added empty folder: <folder>',
      name: 'SessionMutator',
    );
    try {
      await resolveFolderPath(folderPath);
    } catch (e) {
      AppLogger.instance.log(
        'addEmptyFolder failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  }

  // ── Collapsed folders ───────────────────────────────────────────

  Future<void> toggleFolderCollapsed(String folderPath) async {
    final wasCollapsed = _snap.collapsedFolders.contains(folderPath);
    AppLogger.instance.log(
      'Folder ${wasCollapsed ? 'expanded' : 'collapsed'}: <folder>',
      name: 'SessionMutator',
    );
    try {
      final folderId = findFolderIdByPath(folderPath, _snap.folderMap);
      if (folderId != null) {
        // `db_folders_toggle_collapsed` emits `SessionsChanged` on
        // success; the workspace stream re-fetches and the
        // collapsed-folder Provider re-emits. The Rust DB row is the
        // single source of truth.
        await rust_db.dbFoldersToggleCollapsed(id: folderId);
      }
    } catch (e) {
      AppLogger.instance.log(
        'toggleFolderCollapsed failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  }

  // ── Folder operations ───────────────────────────────────────────

  Future<void> renameFolder(String oldPath, String newPath) =>
      _runUndoable('rename folder', () async {
        if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;
        try {
          await rust_db.dbFoldersRenamePathCascade(
            oldPath: oldPath,
            newPath: newPath,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
        } catch (e) {
          AppLogger.instance.log(
            'renameFolder failed: $e',
            name: 'SessionMutator',
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
        // inside" promise.
        final sessions = _snap.sessions;
        final folderMap = _snap.folderMap;
        final sessionIdsToDelete = sessions
            .where(
              (s) =>
                  s.folder == folderPath || s.folder.startsWith('$folderPath/'),
            )
            .map((s) => s.id)
            .toSet();
        try {
          if (sessionIdsToDelete.isNotEmpty) {
            await rust_db.dbSessionsDeleteMultiple(
              ids: sessionIdsToDelete.toList(),
            );
          }
          final folderId = findFolderIdByPath(folderPath, folderMap);
          if (folderId != null) {
            await rust_db.dbFoldersDeleteRecursive(id: folderId);
          }
        } catch (e) {
          AppLogger.instance.log(
            'deleteFolder failed: $e',
            name: 'SessionMutator',
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

    // Snapshot the source-side data BEFORE we start adding new rows;
    // the workspace stream re-flows on every Rust write, so reading
    // the live snapshot during the loop would see freshly-created
    // destination folders feed back into iteration.
    final snap = _snap;
    final sourceSessions = snap.sessions
        .where(
          (s) => s.folder == sourcePath || s.folder.startsWith('$sourcePath/'),
        )
        .toList(growable: false);
    final sourceEmptyFolders = snap.emptyFolders
        .where((f) => f == sourcePath || f.startsWith('$sourcePath/'))
        .toList(growable: false);

    // Create the destination root folder. addEmptyFolder upserts the
    // DB row in one shot; the bus tick rebuilds the snapshot.
    await addEmptyFolder(newRoot);

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
    // position in the new tree.
    for (final session in sourceSessions) {
      final rel = session.folder.substring(sourcePath.length);
      final destFolder = rel.isEmpty ? newRoot : '$newRoot$rel';
      await duplicate(session.id, targetFolder: destFolder);
    }
  }

  /// Pick a folder name that doesn't collide with an existing child
  /// of [parentPath]. Appends "(1)", "(2)", ... until a free name
  /// is found.
  String _uniqueFolderNameUnder(String parentPath, String baseName) {
    final snap = _snap;
    final existingPaths = <String>{
      ...snap.emptyFolders,
      for (final f in snap.folderMap.values)
        _composeFolderPath(f, snap.folderMap),
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
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await rust_db.dbSessionsRestoreSnapshot(
        sessions: [
          for (final s in sessions)
            rust_db.DbRestoreSessionInput(
              id: s.id,
              label: s.label,
              folderPath: s.folder,
              kind: s.kind.name,
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
              extras: extrasMapToJson(s.extras),
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
    } catch (e) {
      AppLogger.instance.log(
        'restoreSnapshot failed: $e',
        name: 'SessionMutator',
        level: LogLevel.warn,
      );
    }
  }

  // ── Undo / redo ─────────────────────────────────────────────────

  SessionSnapshot _captureSnapshot(String description) => SessionSnapshot(
    sessions: List.of(_snap.sessions),
    emptyFolders: Set.of(_snap.emptyFolders),
    description: description,
  );

  /// Run an undoable store operation: snapshot state, execute, sync.
  Future<T> _runUndoable<T>(String op, Future<T> Function() fn) async {
    _historyOrInit().pushUndo(_captureSnapshot(op));
    try {
      return await fn();
    } catch (e) {
      AppLogger.instance.log('Failed to $op', name: 'SessionMutator', error: e);
      rethrow;
    }
  }

  Future<bool> undo() async {
    final current = _captureSnapshot('current');
    final restored = _historyOrInit().undo(current);
    if (restored == null) return false;
    await _restoreSnapshot(restored.sessions, restored.emptyFolders);
    return true;
  }

  Future<bool> redo() async {
    final current = _captureSnapshot('current');
    final restored = _historyOrInit().redo(current);
    if (restored == null) return false;
    await _restoreSnapshot(restored.sessions, restored.emptyFolders);
    return true;
  }

  /// Release the Rust-side history actor handle. Called by the
  /// Provider's `onDispose` so the actor doesn't outlive its owner.
  void disposeHistory() {
    _history?.dispose();
    _history = null;
  }
}

/// Process-singleton mutator surface. Stateless aside from the
/// lazily-minted [SessionHistory] handle; the handle is released
/// when the Provider tears down.
final sessionMutatorProvider = Provider<SessionMutator>((ref) {
  final mutator = SessionMutator(ref);
  ref.onDispose(mutator.disposeHistory);
  return mutator;
});

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

/// Filtered tree based on search. Watches the workspace snapshot so
/// the tree re-renders on every mutation (session add, folder
/// rename, empty-folder add) without a `ref.watch(sessionProvider)`
/// nudge — the snapshot itself is the trigger.
final filteredSessionTreeProvider = Provider<List<SessionTreeNode>>((ref) {
  final sessions = ref.watch(filteredSessionsProvider);
  final emptyFolders = ref.watch(emptyFoldersProvider);
  return SessionTree.build(sessions, emptyFolders: emptyFolders);
});
