import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import '../db/database.dart';
import '../db/mappers.dart';
import '../ssh/port_forward_rule.dart';
import 'session.dart';

/// CRUD + persistence for sessions, backed by `lfs_core.db`. Data
/// DAO is Rust + rusqlite; in-memory cache invariants match the
/// previous drift-era implementation.
///
/// `setDatabase(AppDatabase)` / [database] are kept as a transitional
/// hand-off: a couple of consumers still need the drift handle for
/// cross-DB workflows that have not been ported yet — `import_flow`
/// opens a drift `transaction` to wrap multi-store import as one
/// unit of work, and the security tier switcher drives
/// `PRAGMA rekey` against drift. Both retire when drift is removed.
///
/// Failures from FRB calls (DB locked / native lib missing in unit
/// tests) are caught at every entry point and degrade to the same
/// empty-result / no-op semantics drift's `_db == null` branch
/// used to expose. Live persistence coverage moves to integration_test.
class SessionStore {
  AppDatabase? _drift;

  /// Inject the drift handle. Transitional only — the data calls
  /// themselves go through FRB; this reference exists so legacy
  /// callers (`import_flow.runInTransaction`, security-tier rekey)
  /// keep operating until they migrate off drift.
  void setDatabase(AppDatabase db) {
    _drift = db;
    invalidateCache();
  }

  /// Drift handle, or null when locked / between unlocks. Used only
  /// by transitional consumers — see class doc.
  AppDatabase? get database => _drift;

  final List<Session> _sessions = [];
  final Set<String> _emptyFolders = {};
  final Set<String> _collapsedFolders = {};

  /// Folder tree cache (id → DbFolder). Rebuilt on [load].
  Map<String, rust_db.DbFolder> _folderMap = {};

  List<Session> get sessions => List.unmodifiable(_sessions);
  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);
  Set<String> get collapsedFolders => Set.unmodifiable(_collapsedFolders);

  /// Resolve a folder path string to its DB folder ID.
  /// Returns null if the path is empty or not found.
  String? folderIdByPath(String path) => findFolderIdByPath(path, _folderMap);

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake; replaces the drift-era
  /// `setDatabase` injection.
  void invalidateCache() {
    _sessions.clear();
    _emptyFolders.clear();
    _collapsedFolders.clear();
    _folderMap = {};
    _loadFuture = null;
  }

  /// Close the held drift handle and drop the reference. The
  /// auto-lock path calls this right after zeroing the in-memory DB
  /// key so MC's internal page cache (which retains the key in its
  /// C-layer state for as long as the handle is open) also gets
  /// zeroed. On unlock `_injectDatabase` opens a fresh drift handle
  /// and re-injects via [setDatabase].
  Future<void> closeDatabase() async {
    final drift = _drift;
    _drift = null;
    invalidateCache();
    if (drift == null) return;
    try {
      await drift.close();
    } catch (e) {
      AppLogger.instance.log(
        'SessionStore: drift close failed: $e',
        name: 'SessionStore',
      );
    }
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
      // Load folder tree
      final folders = await rust_db.dbFoldersListAll();
      _folderMap = buildFolderMap(folders);

      // Load sessions, convert to domain model WITHOUT credentials. The
      // cached list in memory must not carry plaintext passwords / keyData /
      // passphrases — callers that need them (connect, edit dialog, export)
      // fetch on demand via [loadWithCredentials].
      final dbSessions = await rust_db.dbSessionsListAll();
      _sessions
        ..clear()
        ..addAll(dbSessions.map((s) => dbSessionToSession(s, _folderMap)));

      // Empty folders = folders in tree that have no sessions pointing to them
      final usedFolderIds = dbSessions
          .map((s) => s.folderId)
          .whereType<String>()
          .toSet();
      _emptyFolders.clear();
      for (final folder in _folderMap.values) {
        if (!usedFolderIds.contains(folder.id)) {
          final path = _pathForId(folder.id);
          if (path.isNotEmpty) _emptyFolders.add(path);
        }
      }

      // Collapsed state from folder tree
      _collapsedFolders.clear();
      for (final folder in _folderMap.values) {
        if (folder.collapsed) {
          final path = _pathForId(folder.id);
          if (path.isNotEmpty) _collapsedFolders.add(path);
        }
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
    _sessions.add(session);
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
    _sessions[idx] = session;
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
    // The in-memory [get] result has no credentials; fetch the full row so
    // the duplicate inherits the password / keyData / passphrase. Fall back
    // to the cached entry when the DB isn't wired (e.g. early test setup).
    final full = await loadWithCredentials(id);
    final original = full ?? get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final base = original.duplicate();
    final copy = targetFolder == null
        ? base
        : base.copyWith(folder: targetFolder);
    await add(copy);
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

  int countSessionsInFolder(String folderPath) {
    return _sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .length;
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

    _renamePaths(_emptyFolders, oldPath, newPath);
    _renamePaths(_collapsedFolders, oldPath, newPath);

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

  /// Rename paths in a set: exact match and children under oldPath/.
  static void _renamePaths(Set<String> paths, String oldPath, String newPath) {
    final toRemove = <String>[];
    final toAdd = <String>[];
    for (final p in paths) {
      if (p == oldPath) {
        toRemove.add(p);
        toAdd.add(newPath);
      } else if (p.startsWith('$oldPath/')) {
        toRemove.add(p);
        toAdd.add(newPath + p.substring(oldPath.length));
      }
    }
    paths.removeAll(toRemove);
    paths.addAll(toAdd);
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
    _sessions
      ..clear()
      ..addAll(sessions);
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

  List<String> folders() {
    final g = _sessions
        .map((s) => s.folder)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    g.sort();
    return g;
  }

  List<Session> byFolder(String folder) {
    return _sessions.where((s) => s.folder == folder).toList();
  }

  List<Session> search(String query) => filterSessions(_sessions, query);

  static List<Session> filterSessions(List<Session> sessions, String query) {
    if (query.isEmpty) return sessions;
    final q = query.toLowerCase();
    return sessions.where((s) {
      return s.label.toLowerCase().contains(q) ||
          s.folder.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q) ||
          s.user.toLowerCase().contains(q);
    }).toList();
  }

  // ── Internals ───────────────────────────────────────────────────

  String _pathForId(String? folderId) {
    if (folderId == null) return '';
    final parts = <String>[];
    String? current = folderId;
    while (current != null) {
      final folder = _folderMap[current];
      if (folder == null) break;
      parts.add(folder.name);
      current = folder.parentId;
    }
    return parts.reversed.join('/');
  }
}
