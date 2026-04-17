import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../session/session.dart';
import '../ssh/ssh_config.dart';
import 'dao/folder_dao.dart';
import 'database.dart';

// ---------------------------------------------------------------------------
// Session ↔ DB mapping
// ---------------------------------------------------------------------------

/// Convert [DbSession] to domain [Session] using a folder map for path
/// resolution.
///
/// When [withCredentials] is false (default), the returned `SessionAuth`
/// carries empty `password`/`keyData`/`passphrase` strings — the DB row's
/// plaintext secrets are never copied into the in-memory cache. Callers
/// that genuinely need credentials (connect, edit, export) must pass
/// `withCredentials: true` at the moment of use, so secrets spend as
/// little time on the Dart heap as possible.
Session dbSessionToSession(
  DbSession db,
  Map<String, DbFolder> folderMap, {
  bool withCredentials = false,
}) {
  // Record whether the row actually carries a secret even when we strip
  // it from the in-memory copy — the tree view needs this to decide
  // whether to flag the session as incomplete (yellow warning). Without
  // it, every embedded-key session would look broken after a restart.
  final hasStoredSecret =
      db.password.isNotEmpty ||
      db.keyData.isNotEmpty ||
      db.passphrase.isNotEmpty;
  return Session(
    id: db.id,
    label: db.label,
    folder: _buildFolderPath(db.folderId, folderMap),
    server: ServerAddress(host: db.host, port: db.port, user: db.user),
    auth: SessionAuth(
      authType: AuthType.values.firstWhere(
        (e) => e.name == db.authType,
        orElse: () => AuthType.password,
      ),
      keyId: db.keyId ?? '',
      hasStoredSecret: hasStoredSecret,
      password: withCredentials ? db.password : '',
      keyPath: db.keyPath,
      keyData: withCredentials ? db.keyData : '',
      passphrase: withCredentials ? db.passphrase : '',
    ),
    createdAt: db.createdAt,
    updatedAt: db.updatedAt,
  );
}

/// Convert domain [Session] to [SessionsCompanion] for DB insert/update.
SessionsCompanion sessionToCompanion(Session s, {required String? folderId}) {
  return SessionsCompanion(
    id: Value(s.id),
    label: Value(s.label),
    folderId: Value(folderId),
    host: Value(s.host),
    port: Value(s.port),
    user: Value(s.user),
    authType: Value(s.authType.name),
    password: Value(s.password),
    keyPath: Value(s.keyPath),
    keyData: Value(s.keyData),
    keyId: Value(s.keyId.isEmpty ? null : s.keyId),
    passphrase: Value(s.passphrase),
    createdAt: Value(s.createdAt),
    updatedAt: Value(s.updatedAt),
  );
}

// ---------------------------------------------------------------------------
// Folder path ↔ tree resolution
// ---------------------------------------------------------------------------

/// Build folder path string (e.g. "Production/EU") from a folderId by walking
/// up the parent chain.
///
/// If a referenced folder id is not present in [folderMap] (an orphaned
/// `parent_id` pointing at a deleted row), the partial path collected so far
/// is prefixed with `(orphaned)/` so the inconsistency is surfaced in the UI
/// instead of being silently truncated, and a warning is logged with both ids
/// so it can be diagnosed offline.
String _buildFolderPath(String? folderId, Map<String, DbFolder> folderMap) {
  if (folderId == null) return '';
  final parts = <String>[];
  String? current = folderId;
  while (current != null) {
    final folder = folderMap[current];
    if (folder == null) {
      AppLogger.instance.log(
        'Orphan folder reference: id=$current (started from $folderId). '
        'Partial path: ${parts.reversed.join('/')}',
        name: 'FolderMapper',
      );
      return '(orphaned)/${parts.reversed.join('/')}';
    }
    parts.add(folder.name);
    current = folder.parentId;
  }
  return parts.reversed.join('/');
}

/// Resolve a folder path string to a folderId, creating missing folders.
///
/// Returns null for empty paths (root-level session).
Future<String?> resolveFolderPath(
  String path,
  FolderDao dao,
  Map<String, DbFolder> cache,
) async {
  if (path.isEmpty) return null;
  final parts = path.split('/');
  String? parentId;
  for (final name in parts) {
    final children = await dao.getChildren(parentId);
    final existing = children.where((f) => f.name == name).firstOrNull;
    if (existing != null) {
      parentId = existing.id;
    } else {
      final id = const Uuid().v4();
      await dao.insert(
        FoldersCompanion.insert(
          id: id,
          name: name,
          parentId: Value(parentId),
          createdAt: DateTime.now(),
        ),
      );
      cache[id] = DbFolder(
        id: id,
        name: name,
        parentId: parentId,
        sortOrder: 0,
        collapsed: false,
        createdAt: DateTime.now(),
      );
      parentId = id;
    }
  }
  return parentId;
}

/// Build a complete folder map (id → DbFolder) from a flat list.
Map<String, DbFolder> buildFolderMap(List<DbFolder> folders) {
  return {for (final f in folders) f.id: f};
}

/// Collect all folder path strings from the folder tree.
Set<String> allFolderPaths(Map<String, DbFolder> folderMap) {
  final paths = <String>{};
  for (final folder in folderMap.values) {
    paths.add(_buildFolderPath(folder.id, folderMap));
  }
  return paths;
}

/// Find folderId by exact path string (returns null if not found).
String? findFolderIdByPath(String path, Map<String, DbFolder> folderMap) {
  if (path.isEmpty) return null;
  for (final entry in folderMap.entries) {
    if (_buildFolderPath(entry.key, folderMap) == path) {
      return entry.key;
    }
  }
  return null;
}
