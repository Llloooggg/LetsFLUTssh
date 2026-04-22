import 'package:drift/drift.dart';

import '../../utils/logger.dart';
import '../db/database.dart';
import '../db/mappers.dart';
import 'session.dart';

/// CRUD + persistence for sessions, backed by drift database.
///
/// Keeps the same public API as the old file-based store. Internally delegates
/// to [SessionDao] and [FolderDao]. The folder string paths ("Production/EU")
/// are translated to/from the DB folder tree transparently.
///
/// Call [setDatabase] before [load] — without a database, all reads return
/// empty data and writes are no-ops.
class SessionStore {
  AppDatabase? _db;

  final List<Session> _sessions = [];
  final Set<String> _emptyFolders = {};
  final Set<String> _collapsedFolders = {};

  /// Folder tree cache (id → DbFolder). Rebuilt on [load].
  Map<String, DbFolder> _folderMap = {};

  List<Session> get sessions => List.unmodifiable(_sessions);
  Set<String> get emptyFolders => Set.unmodifiable(_emptyFolders);
  Set<String> get collapsedFolders => Set.unmodifiable(_collapsedFolders);

  /// Resolve a folder path string to its DB folder ID.
  /// Returns null if the path is empty or not found.
  String? folderIdByPath(String path) => findFolderIdByPath(path, _folderMap);

  /// Inject the opened database. Replaces the old `setEncryptionKey()`.
  void setDatabase(AppDatabase db) {
    _db = db;
  }

  /// Current database, or null if [setDatabase] hasn't been called yet.
  /// Exposed so `ImportService` can open a transaction spanning every store.
  AppDatabase? get database => _db;

  /// Close the held database handle and drop the reference. The
  /// auto-lock path calls this right after zeroing the in-memory DB
  /// key so MC's internal page cache (which retains the key
  /// in its C-layer state for as long as the handle is open) also
  /// gets zeroed. On unlock `main._injectDatabase` opens a fresh
  /// handle and re-injects via [setDatabase].
  ///
  /// Best-effort: a failure to close (stale file descriptor, drift
  /// internal error) is logged by the caller; losing the reference
  /// is enough to unblock the re-open path.
  Future<void> closeDatabase() async {
    final db = _db;
    _db = null;
    if (db == null) return;
    try {
      await db.close();
    } catch (_) {
      // Best-effort. Handle may have been closed elsewhere already.
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
    final db = _db;
    if (db == null) return [];

    try {
      // Load folder tree
      final folders = await db.folderDao.getAll();
      _folderMap = buildFolderMap(folders);

      // Load sessions, convert to domain model WITHOUT credentials. The
      // cached list in memory must not carry plaintext passwords / keyData /
      // passphrases — callers that need them (connect, edit dialog, export)
      // fetch on demand via [loadWithCredentials].
      final dbSessions = await db.sessionDao.getAll();
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

  /// Fetch a single session with credentials populated (password/keyData/
  /// passphrase). Returns null if the session no longer exists in the DB.
  ///
  /// The in-memory cache stores credential-free copies to shrink the window
  /// in which plaintext secrets live on the Dart heap. Connect/edit/export
  /// flows call this right before they need the secrets and drop the
  /// reference as soon as the consumer is done with it.
  Future<Session?> loadWithCredentials(String id) async {
    final db = _db;
    if (db == null) return null;
    final row = await db.sessionDao.getById(id);
    if (row == null) return null;
    return dbSessionToSession(row, _folderMap, withCredentials: true);
  }

  // ── CRUD ─────────────────────────────────────────────────────────

  Future<void> add(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    _sessions.add(session);
    final db = _db;
    if (db != null) {
      final folderId = await resolveFolderPath(
        session.folder,
        db.folderDao,
        _folderMap,
      );
      await db.sessionDao.insert(
        sessionToCompanion(session, folderId: folderId),
      );
    }
  }

  Future<void> update(Session session) async {
    final error = session.validate();
    if (error != null) throw ArgumentError(error);
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx < 0) throw ArgumentError('Session not found: ${session.id}');
    _sessions[idx] = session;
    final db = _db;
    if (db != null) {
      final folderId = await resolveFolderPath(
        session.folder,
        db.folderDao,
        _folderMap,
      );
      await db.sessionDao.update(
        sessionToCompanion(session, folderId: folderId),
      );
    }
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    await _db?.sessionDao.deleteById(id);
  }

  Future<void> deleteMultiple(Set<String> ids) async {
    if (ids.isEmpty) return;
    _sessions.removeWhere((s) => ids.contains(s.id));
    await _db?.sessionDao.deleteMultiple(ids);
  }

  Future<void> deleteAll() async {
    _sessions.clear();
    _emptyFolders.clear();
    _collapsedFolders.clear();
    final db = _db;
    if (db != null) {
      await db.sessionDao.deleteAll();
      // Delete all folders (empty + non-empty)
      final allFolders = await db.folderDao.getAll();
      for (final f in allFolders) {
        await db.folderDao.deleteById(f.id);
      }
      _folderMap.clear();
    }
  }

  Session? get(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<Session> duplicateSession(String id) async {
    // The in-memory [get] result has no credentials; fetch the full row so
    // the duplicate inherits the password / keyData / passphrase. Fall back
    // to the cached entry when the DB isn't wired (e.g. early test setup).
    final full = await loadWithCredentials(id);
    final original = full ?? get(id);
    if (original == null) throw ArgumentError('Session not found: $id');
    final copy = original.duplicate();
    await add(copy);
    return copy;
  }

  Future<void> moveSession(String sessionId, String newFolder) async {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx] = _sessions[idx].copyWith(folder: newFolder);
    final db = _db;
    if (db != null) {
      final folderId = await resolveFolderPath(
        newFolder,
        db.folderDao,
        _folderMap,
      );
      await db.sessionDao.moveToFolder(sessionId, folderId);
    }
  }

  Future<void> moveMultiple(Set<String> ids, String newFolder) async {
    if (ids.isEmpty) return;
    for (var i = 0; i < _sessions.length; i++) {
      if (ids.contains(_sessions[i].id)) {
        _sessions[i] = _sessions[i].copyWith(folder: newFolder);
      }
    }
    final db = _db;
    if (db != null) {
      final folderId = await resolveFolderPath(
        newFolder,
        db.folderDao,
        _folderMap,
      );
      await db.sessionDao.moveMultiple(ids, folderId);
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
    final db = _db;
    if (db != null) {
      await resolveFolderPath(folderPath, db.folderDao, _folderMap);
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
    final db = _db;
    if (db != null) {
      final folderId = findFolderIdByPath(folderPath, _folderMap);
      if (folderId != null) {
        await db.folderDao.toggleCollapsed(folderId);
      }
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

    // Update DB: rename the folder node
    final db = _db;
    if (db != null) {
      final folderId = findFolderIdByPath(oldPath, _folderMap);
      if (folderId != null) {
        final newName = newPath.split('/').last;
        await db.folderDao.update(
          FoldersCompanion(id: Value(folderId), name: Value(newName)),
        );
        // Rebuild cache
        final folders = await db.folderDao.getAll();
        _folderMap = buildFolderMap(folders);
      }
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
    final db = _db;
    if (db != null) {
      final folderId = findFolderIdByPath(folderPath, _folderMap);
      if (folderId != null) {
        await db.folderDao.deleteRecursive(folderId);
        final folders = await db.folderDao.getAll();
        _folderMap = buildFolderMap(folders);
      }
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

    final db = _db;
    if (db != null) {
      // Clear and rebuild
      await db.sessionDao.deleteAll();
      final allFolders = await db.folderDao.getAll();
      for (final f in allFolders) {
        await db.folderDao.deleteById(f.id);
      }
      _folderMap.clear();

      // Re-insert sessions with folder resolution
      for (final session in sessions) {
        final folderId = await resolveFolderPath(
          session.folder,
          db.folderDao,
          _folderMap,
        );
        await db.sessionDao.insert(
          sessionToCompanion(session, folderId: folderId),
        );
      }

      // Re-create empty folders
      for (final path in emptyFolders) {
        await resolveFolderPath(path, db.folderDao, _folderMap);
      }
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
