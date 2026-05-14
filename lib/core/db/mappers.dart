import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/folder_path.dart' as rust_fp;
import '../../src/rust/api/sessions.dart' as rust_sess;
import '../session/session.dart';
import '../ssh/ssh_config.dart';

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
    kind: rust_sess.sessionKindFromWire(value: db.kind),
    server: ServerAddress(host: db.host, port: db.port, user: db.user),
    auth: SessionAuth(
      authType: rust_sess.authTypeFromWire(value: db.authType),
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

/// Decode the `Sessions.extras` JSON column via the Rust-side typed
/// decoder. Corrupt blobs fold to empty Rust-side — the FRB call
/// always returns a valid list — so a session can never fail to load
/// on a malformed extras column. The column default is `'{}'`, so the
/// typical path returns an empty list with no work.
Map<String, Object?> _decodeExtras(String raw) {
  if (raw.isEmpty) return const <String, Object?>{};
  return extrasListToMap(rust_sess.sessionExtrasDecode(json: raw));
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
  return rust_fp.folderBuildPath(
    folderId: folderId ?? '',
    folders: folderMap.values.toList(growable: false),
  );
}

/// Resolve a folder path string to a folderId, creating missing
/// folders. Returns `null` for empty paths (root-level session).
///
/// Routes through `lfs_core::db::folders::resolve_or_create_path`,
/// which walks every `/`-separated segment inside a single
/// transaction — a crash mid-walk leaves no partially-resolved
/// subtree. The Rust side reads the `folders` table by
/// `(parent_id, name)`, so callers don't need to maintain a folder
/// cache; the DB is the source of truth for the tree.
Future<String?> resolveFolderPath(String path) async {
  if (path.isEmpty) return null;
  return rust_db.dbFoldersResolveOrCreatePath(
    path: path,
    nowMs: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Build a complete folder map (id → DbFolder) from a flat list.
Map<String, rust_db.DbFolder> buildFolderMap(List<rust_db.DbFolder> folders) {
  return {for (final f in folders) f.id: f};
}

/// Collect all folder path strings from the folder tree. Routes through
/// `lfs_core::folder_path::all_folder_paths` so the Rust + Dart paths agree
/// on the orphan-marker grammar by construction.
Set<String> allFolderPaths(Map<String, rust_db.DbFolder> folderMap) {
  return rust_fp
      .folderAllPaths(folders: folderMap.values.toList(growable: false))
      .toSet();
}

/// Find folderId by exact path string (returns null if not found). Routes
/// through `lfs_core::folder_path::find_folder_id_by_path`.
String? findFolderIdByPath(
  String path,
  Map<String, rust_db.DbFolder> folderMap,
) {
  return rust_fp.folderFindIdByPath(
    path: path,
    folders: folderMap.values.toList(growable: false),
  );
}
