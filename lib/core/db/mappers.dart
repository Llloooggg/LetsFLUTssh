import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import '../session/session.dart';
import '../ssh/ssh_config.dart';
import '_folder_path_compat.dart';

// ---------------------------------------------------------------------------
// Session ↔ DB mapping
// ---------------------------------------------------------------------------

/// Convert FRB [rust_db.DbSession] to domain [Session] using a folder
/// map for path resolution.
///
/// When [withCredentials] is false (default), the returned `SessionAuth`
/// carries empty `password`/`keyData`/`passphrase` strings — the DB row's
/// plaintext secrets are never copied into the in-memory cache. Callers
/// that genuinely need credentials (connect, edit, export) must pass
/// `withCredentials: true` at the moment of use, so secrets spend as
/// little time on the Dart heap as possible.
Session dbSessionToSession(
  rust_db.DbSession db,
  Map<String, rust_db.DbFolder> folderMap, {
  bool withCredentials = false,
}) {
  // Per-slot stored-secret flags so the edit dialog can render
  // "[Saved]" badges next to each field whose underlying column has
  // a value, without ever pre-filling the controller. Without these
  // an embedded-key session would look broken after a restart.
  return Session(
    id: db.id,
    label: db.label,
    folder: _buildFolderPath(db.folderId, folderMap),
    kind: SessionKind.fromWire(db.kind),
    server: ServerAddress(host: db.host, port: db.port, user: db.user),
    auth: SessionAuth(
      authType: AuthType.values.firstWhere(
        (e) => e.name == db.authType,
        orElse: () => AuthType.password,
      ),
      keyId: db.keyId ?? '',
      hasStoredPassword: db.password.isNotEmpty,
      hasStoredKeyData: db.keyData.isNotEmpty,
      hasStoredPassphrase: db.passphrase.isNotEmpty,
      password: withCredentials ? db.password : '',
      keyPath: db.keyPath,
      keyData: withCredentials ? db.keyData : '',
      passphrase: withCredentials ? db.passphrase : '',
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(db.createdAtMs),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(db.updatedAtMs),
    extras: _decodeExtras(db.extras),
    viaSessionId: db.viaSessionId,
    viaOverride: _decodeOverride(db.viaHost, db.viaPort, db.viaUser),
    notes: db.notes,
    sortOrder: db.sortOrder,
    lastConnectedAtMs: db.lastConnectedAtMs,
  );
}

/// Reassemble a [ProxyJumpOverride] from the three nullable columns,
/// requiring all three to be set. A partial row (e.g. user wiped the
/// host but left port behind via direct DB edit) maps to `null` so
/// the runtime never tries to dial half a bastion.
ProxyJumpOverride? _decodeOverride(String? host, int? port, String? user) {
  if (host == null || host.trim().isEmpty) return null;
  if (user == null || user.trim().isEmpty) return null;
  return ProxyJumpOverride(host: host, port: port ?? 22, user: user);
}

/// Decode the `Sessions.extras` JSON column. Tolerates malformed
/// blobs (returns empty) — corrupt extras must never block a session
/// from loading. The column default is `'{}'`, so this is a recovery
/// path for hand-edited DBs or future schema regressions.
Map<String, Object?> _decodeExtras(String raw) {
  if (raw.isEmpty) return const <String, Object?>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } on FormatException {
    AppLogger.instance.log(
      'Corrupt session.extras JSON, dropping to empty map',
      name: 'SessionMapper',
    );
  }
  return const <String, Object?>{};
}

/// Convert domain [Session] to FRB [rust_db.DbSession] for upsert.
rust_db.DbSession sessionToRustRow(Session s, {required String? folderId}) {
  // viaSessionId wins over viaOverride — see Session class doc.
  // Persist the loser as null so a stray override left over from a
  // prior edit cannot resurrect after viaSessionId is cleared.
  final usingSavedBastion = s.viaSessionId != null;
  return rust_db.DbSession(
    id: s.id,
    label: s.label,
    folderId: folderId,
    kind: s.kind.wire,
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
    extras: jsonEncode(s.extras),
    viaSessionId: s.viaSessionId,
    viaHost: usingSavedBastion ? null : s.viaOverride?.host,
    viaPort: usingSavedBastion ? null : s.viaOverride?.port,
    viaUser: usingSavedBastion ? null : s.viaOverride?.user,
    createdAtMs: s.createdAt.millisecondsSinceEpoch,
    updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
  );
}

// ---------------------------------------------------------------------------
// Folder path ↔ tree resolution
// ---------------------------------------------------------------------------

/// Build folder path string (e.g. "Production/EU") from a folderId by walking
/// up the parent chain. Routes through `lfs_core::folder_path::build_folder_path`
/// via the FRB shim — same orphan-marker grammar (a missing parent_id surfaces
/// as `(orphaned)/{partial}` so the UI sees the inconsistency rather than
/// silently dropping the leaf name).
String _buildFolderPath(
  String? folderId,
  Map<String, rust_db.DbFolder> folderMap,
) {
  return folderBuildPathCompat(folderId, folderMap);
}

/// Resolve a folder path string to a folderId, creating missing folders.
///
/// Returns null for empty paths (root-level session).
///
/// [cache] is treated as the authoritative view of the folder tree —
/// the caller (`SessionStore`) keeps it in sync with the DB on load and
/// on every mutation. Lookups walk the cache in memory instead of
/// issuing a folder-list round-trip per path segment, so a 50-session
/// import across deep folders no longer fans out into hundreds of
/// awaited reads. Only folder **inserts** still hit the DB.
Future<String?> resolveFolderPath(
  String path,
  Map<String, rust_db.DbFolder> cache,
) async {
  if (path.isEmpty) return null;
  final parts = path.split('/');
  String? parentId;
  for (final name in parts) {
    final existing = _findChildByName(cache, parentId, name);
    if (existing != null) {
      parentId = existing.id;
      continue;
    }
    final id = const Uuid().v4();
    final now = DateTime.now();
    final row = rust_db.DbFolder(
      id: id,
      name: name,
      parentId: parentId,
      sortOrder: 0,
      collapsed: false,
      createdAtMs: now.millisecondsSinceEpoch,
    );
    await rust_db.dbFoldersUpsert(row: row);
    cache[id] = row;
    parentId = id;
  }
  return parentId;
}

/// Linear scan over [cache] for the child of [parentId] named [name].
/// Typical folder trees have ≤100 entries, so an O(N) scan per segment
/// is ~1000× faster than the DB round-trip it replaces. If that ever
/// stops being true, switch to a `(parentId, name) → DbFolder`
/// secondary index maintained alongside [cache].
rust_db.DbFolder? _findChildByName(
  Map<String, rust_db.DbFolder> cache,
  String? parentId,
  String name,
) {
  for (final folder in cache.values) {
    if (folder.parentId == parentId && folder.name == name) return folder;
  }
  return null;
}

/// Build a complete folder map (id → DbFolder) from a flat list.
Map<String, rust_db.DbFolder> buildFolderMap(List<rust_db.DbFolder> folders) {
  return {for (final f in folders) f.id: f};
}

/// Collect all folder path strings from the folder tree. Routes through
/// `lfs_core::folder_path::all_folder_paths` so the Rust + Dart paths agree
/// on the orphan-marker grammar by construction.
Set<String> allFolderPaths(Map<String, rust_db.DbFolder> folderMap) {
  return folderAllPathsCompat(folderMap);
}

/// Find folderId by exact path string (returns null if not found). Routes
/// through `lfs_core::folder_path::find_folder_id_by_path`.
String? findFolderIdByPath(
  String path,
  Map<String, rust_db.DbFolder> folderMap,
) {
  return folderFindIdByPathCompat(path, folderMap);
}
