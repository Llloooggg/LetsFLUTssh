import 'dart:async';
import 'dart:convert';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/sessions.dart' as rust_sess;
import '../../src/rust/api/sessions_registry.dart' as rust_registry;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../db/_folder_path_compat.dart';
import '../db/mappers.dart';
import '../ssh/port_forward_rule.dart';
import 'session.dart';

/// CRUD + persistence for sessions, backed by `lfs_core.db`. Data
/// DAO is Rust + rusqlite; in-memory cache invariants match the
/// previous drift-era implementation.
///
/// Failures from FRB calls (DB locked / native lib missing in unit
/// tests) are caught at every entry point and degrade to the same
/// empty-result / no-op semantics the legacy `_db == null` branch
/// used to expose. Live persistence coverage moves to integration_test.
class SessionStore {
  SessionStore() {
    // Subscribe to the global Sessions topic so any FRB-side
    // mutation (including bulk-import paths) refreshes the cache.
    // The subscribe call hits the FRB native lib at construction
    // time; flutter_test contexts that don't load the lib raise
    // synchronously. Catch + log so the store stays usable in
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
        'SessionStore bus subscribe failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  StreamSubscription<rust_bus.BusEvent>? _busSub;

  final List<Session> _sessions = [];
  final Set<String> _emptyFolders = {};
  final Set<String> _collapsedFolders = {};

  /// Folder tree cache (id → DbFolder). Rebuilt on [load].
  Map<String, rust_db.DbFolder> _folderMap = {};

  /// Force a reload from the DB on the next [load] call. Used by the
  /// bus subscriber (above) to drop the cached future after a
  /// `SessionsChanged` event so the next read picks up the new state.
  Future<void> reload() async {
    invalidateCache();
    await load();
  }

  /// Cancel the bus subscription. Call from disposing the provider.
  void dispose() {
    unawaited(_busSub?.cancel());
    _busSub = null;
  }

  List<Session> get sessions => List.unmodifiable(_sessions);
  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);
  Set<String> get collapsedFolders => Set.unmodifiable(_collapsedFolders);

  /// Resolve a folder path string to its DB folder ID.
  /// Returns null if the path is empty or not found.
  String? folderIdByPath(String path) => findFolderIdByPath(path, _folderMap);

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake.
  void invalidateCache() {
    _sessions.clear();
    _emptyFolders.clear();
    _collapsedFolders.clear();
    _folderMap = {};
    _loadFuture = null;
  }

  /// Guards concurrent [load] calls.
  Future<List<Session>>? _loadFuture;

  Future<List<Session>> load() async {
    if (_loadFuture != null) return _loadFuture!;
    final future = _doLoad();
    _loadFuture = future;
    try {
      return await future;
    } finally {
      _loadFuture = null;
    }
  }

  Future<List<Session>> _doLoad() async {
    try {
      // Hydrate from the Rust-side `sessions::Registry` snapshot when
      // the FRB native lib is available — the registry is kept in sync
      // by the FRB DAO write paths so the snapshot reflects the latest
      // committed state without an extra DAO round-trip from Dart.
      // `sessionsRegistryReload` forces an initial pull from disk on
      // first load (the registry starts empty). Falls back to the
      // explicit DAO walk below for the flutter_test surface that
      // doesn't bootstrap RustLib.
      var hydratedFromRegistry = false;
      try {
        await rust_registry.sessionsRegistryReload();
        final view = rust_registry.sessionsRegistrySnapshot();
        _folderMap = buildFolderMap(view.folders);
        _sessions
          ..clear()
          ..addAll(view.sessions.map((s) => dbSessionToSession(s, _folderMap)));
        _emptyFolders
          ..clear()
          ..addAll(view.emptyFolders);
        _collapsedFolders
          ..clear()
          ..addAll(view.collapsedFolders);
        hydratedFromRegistry = true;
      } catch (e) {
        AppLogger.instance.log(
          'SessionStore registry hydration failed, falling back to DAO walk: $e',
          name: 'SessionStore',
          level: LogLevel.warn,
        );
      }

      if (!hydratedFromRegistry) {
        // Load folder tree
        final folders = await rust_db.dbFoldersListAll();
        _folderMap = buildFolderMap(folders);

        // Load sessions, convert to domain model WITHOUT credentials.
        final dbSessions = await rust_db.dbSessionsListAll();
        _sessions
          ..clear()
          ..addAll(dbSessions.map((s) => dbSessionToSession(s, _folderMap)));

        final usedFolderIds = dbSessions
            .map((s) => s.folderId)
            .whereType<String>()
            .toSet();
        _emptyFolders
          ..clear()
          ..addAll(folderDeriveEmptyCompat(_folderMap, usedFolderIds));
        _collapsedFolders
          ..clear()
          ..addAll(folderDeriveCollapsedCompat(_folderMap));
      }

      AppLogger.instance.log(
        'Loaded ${_sessions.length} sessions, '
        '${_folderMap.length} folders',
        name: 'SessionStore',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load sessions',
        name: 'SessionStore',
        error: e,
      );
    }
    return List.of(_sessions);
  }

  /// Read every saved port-forward rule for [sessionId], sorted by
  /// the user-defined order. Empty when the session has no rules
  /// (the runtime then skips attaching a `PortForwardRuntime` and
  /// the connection pays no cost).
  Future<List<PortForwardRule>> loadPortForwards(String sessionId) async {
    try {
      final rows = await rust_db.dbPortForwardsListForSession(
        sessionId: sessionId,
      );
      return rows
          .map(
            (r) => PortForwardRule(
              id: r.id,
              kind: PortForwardKindExt.fromWireName(r.kind),
              bindHost: r.bindHost,
              bindPort: r.bindPort,
              remoteHost: r.remoteHost,
              remotePort: r.remotePort,
              description: r.description,
              enabled: r.enabled,
              sortOrder: r.sortOrder,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
            ),
          )
          .toList(growable: false);
    } catch (e) {
      AppLogger.instance.log(
        'loadPortForwards failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  /// Insert or update [rule] for [sessionId]. Idempotent on the rule
  /// id — re-saving a rule with the same id overwrites.
  Future<void> upsertPortForward(String sessionId, PortForwardRule rule) async {
    try {
      await rust_db.dbPortForwardsUpsert(
        row: rust_db.DbPortForwardRule(
          id: rule.id,
          sessionId: sessionId,
          kind: rule.kind.wireName,
          bindHost: rule.bindHost,
          bindPort: rule.bindPort,
          remoteHost: rule.remoteHost,
          remotePort: rule.remotePort,
          description: rule.description,
          enabled: rule.enabled,
          sortOrder: rule.sortOrder,
          createdAtMs: rule.createdAt.millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'upsertPortForward failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop a single rule by id. Returns true when something was
  /// removed (helpful for the UI confirm-toast).
  Future<bool> deletePortForward(String ruleId) async {
    try {
      final n = await rust_db.dbPortForwardsDelete(id: ruleId);
      return n > 0;
    } catch (e) {
      AppLogger.instance.log(
        'deletePortForward failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
      return false;
    }
  }

  /// Fetch a single session with credentials populated (password/keyData/
  /// passphrase). Returns null if the session no longer exists in the DB.
  Future<Session?> loadWithCredentials(String id) async {
    try {
      final row = await rust_db.dbSessionsGet(id: id);
      if (row == null) return null;
      return dbSessionToSession(row, _folderMap, withCredentials: true);
    } catch (e) {
      AppLogger.instance.log(
        'loadWithCredentials failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
      return null;
    }
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
    _sessions.add(session.withoutCredentials());
    try {
      final folderId = await resolveFolderPath(session.folder, _folderMap);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore.add failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> update(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx < 0) throw ArgumentError('Session not found: ${session.id}');
    // Same credential-clearing rule as `add` — the cache row never
    // carries plaintext.
    _sessions[idx] = session.withoutCredentials();
    try {
      final folderId = await resolveFolderPath(session.folder, _folderMap);
      await rust_db.dbSessionsUpsert(
        row: sessionToRustRow(session, folderId: folderId),
      );
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore.update failed: $e',
        name: 'SessionStore',
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
    final idx = _sessions.indexWhere((s) => s.id == session.id);
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
          sortOrder: 0,
          notes: '',
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
        'SessionStore.updatePartial failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
      rethrow;
    }
    // Reload to refresh the per-slot `hasStoredX` flags + cached
    // metadata after a partial save (dirty-bit changes shift the
    // saved-or-not indicator state for the next dialog open).
    await load();
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    try {
      await rust_db.dbSessionsDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore.delete failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> deleteMultiple(Set<String> ids) async {
    if (ids.isEmpty) return;
    _sessions.removeWhere((s) => ids.contains(s.id));
    try {
      await rust_db.dbSessionsDeleteMultiple(ids: ids.toList());
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore.deleteMultiple failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> deleteAll() async {
    _sessions.clear();
    _emptyFolders.clear();
    _collapsedFolders.clear();
    try {
      await rust_db.dbSessionsDeleteAll();
      await rust_db.dbFoldersDeleteAll();
      _folderMap.clear();
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore.deleteAll failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Session? get(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<Session> duplicateSession(String id, {String? targetFolder}) async {
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
        'duplicateSession FRB call failed: $e',
        name: 'SessionStore',
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

  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(folder: newFolder);
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
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    if (ids.isEmpty) return;
    for (var i = 0; i < _sessions.length; i++) {
      if (ids.contains(_sessions[i].id)) {
        _sessions[i] = _sessions[i].copyWith(folder: newFolder);
      }
    }
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
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  // ── Empty folders ───────────────────────────────────────────────

  Future<void> addEmptyFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    _emptyFolders.add(folderPath);
    AppLogger.instance.log(
      'Added empty folder: $folderPath',
      name: 'SessionStore',
    );
    try {
      await resolveFolderPath(folderPath, _folderMap);
    } catch (e) {
      AppLogger.instance.log(
        'addEmptyFolder failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> removeEmptyFolder(String folderPath) async {
    _emptyFolders.remove(folderPath);
    // Folder stays in tree — will be cleaned up naturally when it gets sessions
  }

  // ── Collapsed folders ───────────────────────────────────────────

  Future<void> toggleFolderCollapsed(String folderPath) async {
    final wasCollapsed = _collapsedFolders.contains(folderPath);
    if (wasCollapsed) {
      _collapsedFolders.remove(folderPath);
    } else {
      _collapsedFolders.add(folderPath);
    }
    AppLogger.instance.log(
      'Folder ${wasCollapsed ? 'expanded' : 'collapsed'}: $folderPath',
      name: 'SessionStore',
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
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Count sessions whose folder equals [folderPath] or sits under
  /// `{folderPath}/`. Routes through the Rust registry's
  /// `sessions_registry_count_in_folder` when the FRB native lib
  /// is loaded — that path reads off the cached view, no folder-
  /// list projection per call. Falls back to the projecting
  /// `sessions::count_in_folder` shim and finally to the inline
  /// scan for flutter_test contexts that bring up neither.
  int countSessionsInFolder(String folderPath) {
    try {
      return rust_registry.sessionsRegistryCountInFolder(
        folderPath: folderPath,
      );
    } catch (_) {
      // Registry path unreachable — fall through to the
      // projecting shim, then the inline scan.
    }
    try {
      return rust_sess.sessionsCountInFolder(
        sessionFolders: _sessions.map((s) => s.folder).toList(growable: false),
        folderPath: folderPath,
      );
    } catch (_) {
      if (folderPath.isEmpty) {
        return _sessions.where((s) => s.folder.isEmpty).length;
      }
      final prefix = '$folderPath/';
      return _sessions
          .where((s) => s.folder == folderPath || s.folder.startsWith(prefix))
          .length;
    }
  }

  // ── Folder operations ───────────────────────────────────────────

  Future<void> renameFolder(String oldPath, String newPath) async {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;

    // Update in-memory sessions
    for (int i = 0; i < _sessions.length; i++) {
      final s = _sessions[i];
      if (s.folder == oldPath) {
        _sessions[i] = s.copyWith(folder: newPath);
      } else if (s.folder.startsWith('$oldPath/')) {
        _sessions[i] = s.copyWith(
          folder: newPath + s.folder.substring(oldPath.length),
        );
      }
    }

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

    try {
      final folderId = findFolderIdByPath(oldPath, _folderMap);
      if (folderId != null) {
        final row = _folderMap[folderId];
        final newName = newPath.split('/').last;
        await rust_db.dbFoldersUpdateNameParent(
          id: folderId,
          name: newName,
          parentId: row?.parentId,
        );
        // Rebuild cache
        final folders = await rust_db.dbFoldersListAll();
        _folderMap = buildFolderMap(folders);
      }
    } catch (e) {
      AppLogger.instance.log(
        'renameFolder failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> deleteFolder(String folderPath) async {
    if (folderPath.isEmpty) return;
    _sessions.removeWhere(
      (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
    );
    _emptyFolders.removeWhere(
      (g) => g == folderPath || g.startsWith('$folderPath/'),
    );
    _collapsedFolders.removeWhere(
      (c) => c == folderPath || c.startsWith('$folderPath/'),
    );
    try {
      final folderId = findFolderIdByPath(folderPath, _folderMap);
      if (folderId != null) {
        await rust_db.dbFoldersDeleteRecursive(id: folderId);
        final folders = await rust_db.dbFoldersListAll();
        _folderMap = buildFolderMap(folders);
      }
    } catch (e) {
      AppLogger.instance.log(
        'deleteFolder failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> moveFolder(String folderPath, String newParent) async {
    if (folderPath.isEmpty) return;
    final folderName = folderPath.split('/').last;
    final newPath = newParent.isEmpty ? folderName : '$newParent/$folderName';
    if (newPath == folderPath) return;
    if (newPath.startsWith('$folderPath/')) return;
    await renameFolder(folderPath, newPath);
  }

  // ── Snapshot / restore (for undo) ───────────────────────────────

  Future<void> restoreSnapshot(
    List<Session> sessions,
    Set<String> emptyFolders,
  ) async {
    // Same credential-clearing rule as `add` / `update` — undo
    // history snapshots may carry credential-bearing copies (the
    // history snapshot is built off the live cache, which may have
    // been hydrated with credentials by `loadWithCredentials` for a
    // recent edit dialog). Restore must not re-introduce them.
    _sessions
      ..clear()
      ..addAll(sessions.map((s) => s.withoutCredentials()));
    _emptyFolders
      ..clear()
      ..addAll(emptyFolders);

    try {
      // Clear and rebuild
      await rust_db.dbSessionsDeleteAll();
      await rust_db.dbFoldersDeleteAll();
      _folderMap.clear();

      // Re-insert sessions with folder resolution
      for (final session in sessions) {
        final folderId = await resolveFolderPath(session.folder, _folderMap);
        await rust_db.dbSessionsUpsert(
          row: sessionToRustRow(session, folderId: folderId),
        );
      }

      // Re-create empty folders
      for (final path in emptyFolders) {
        await resolveFolderPath(path, _folderMap);
      }
    } catch (e) {
      AppLogger.instance.log(
        'restoreSnapshot failed: $e',
        name: 'SessionStore',
        level: LogLevel.warn,
      );
    }
  }

  // ── Query ───────────────────────────────────────────────────────

  /// Distinct, sorted list of named folders referenced by any
  /// session in the cache. Routes through the Rust registry's
  /// `sessions_registry_distinct_folders` (cache read, no Dart-
  /// side projection per call) when the FRB native lib is
  /// loaded; falls back to the projecting `distinctFolders`
  /// shim and finally to the inline pipeline for flutter_test
  /// contexts.
  List<String> folders() {
    try {
      return rust_registry.sessionsRegistryDistinctFolders();
    } catch (_) {
      // Registry path unreachable — fall through to the
      // projecting shim, then the inline pipeline.
    }
    try {
      return rust_sess.sessionsDistinctFolders(
        sessionFolders: _sessions.map((s) => s.folder).toList(growable: false),
      );
    } catch (_) {
      final g = _sessions
          .map((s) => s.folder)
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList();
      g.sort();
      return g;
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
      return _sessions.where((s) => ids.contains(s.id)).toList();
    } catch (_) {
      return _sessions.where((s) => s.folder == folder).toList();
    }
  }

  /// Case-insensitive substring search across the cached session
  /// list. Routes through the Rust registry's
  /// `sessions_registry_filter_ids` when the FRB native lib is
  /// loaded — that path reads off the same view this store
  /// hydrated from, so the projection round-trip
  /// `filterSessions` makes per call disappears. Falls back to
  /// the projecting `filterSessions` for flutter_test contexts.
  List<Session> search(String query) {
    if (query.isEmpty) return List.unmodifiable(_sessions);
    try {
      final ids = rust_registry.sessionsRegistryFilterIds(query: query).toSet();
      if (ids.isEmpty) return const <Session>[];
      return _sessions.where((s) => ids.contains(s.id)).toList();
    } catch (_) {
      return filterSessions(_sessions, query);
    }
  }

  /// Case-insensitive substring search across (label, folder, host,
  /// user). Routes through `lfs_core::sessions::filter_sessions` so
  /// the four-field grammar lives one place; falls back to the
  /// equivalent Dart predicate when the FRB native lib is not
  /// loaded (flutter_test contexts that mock the DAOs).
  static List<Session> filterSessions(List<Session> sessions, String query) {
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
}
