import 'dart:convert';

import '../../src/rust/api/archive.dart' as rust_archive;
import '../security/key_store.dart';
import '../snippets/snippet.dart';
import '../tags/tag.dart';
import '../../features/settings/export_import.dart';
import '../session/session.dart';

/// Per-type row counts from a completed import. Feeds the success toast so
/// the user sees what was actually applied (sessions, tags, snippets, keys,
/// config, known_hosts) instead of only a session count.
class ImportSummary {
  final int sessions;
  final int folders;
  final int managerKeys;
  final int tags;
  final int snippets;
  final bool configApplied;
  final bool knownHostsApplied;

  /// Number of session JSON entries in the archive that failed to parse and
  /// were dropped during decoding (e.g. wrong type for `port`, missing keys).
  /// Surfaced in the success toast so the user knows the archive contained
  /// corrupt records.
  final int skippedSessions;

  /// Total number of session→tag, folder→tag, and session→snippet links that
  /// were dropped because their target was not part of the import set (would
  /// FK-fail on insert) or because the underlying save callback threw.
  /// Surfaced in the success toast so the user knows some metadata
  /// associations did not survive the import.
  final int skippedLinks;

  const ImportSummary({
    this.sessions = 0,
    this.folders = 0,
    this.managerKeys = 0,
    this.tags = 0,
    this.snippets = 0,
    this.configApplied = false,
    this.knownHostsApplied = false,
    this.skippedSessions = 0,
    this.skippedLinks = 0,
  });
}

/// Apply an [ImportResult] entirely through the Rust core
/// (`lfs_core::archive::apply_pending_import`). Collisions, replace-mode
/// snapshot/rollback, junction inserts, and folder hierarchy reconstruction
/// all happen Rust-side under a sqlite transaction — on failure the whole
/// apply rolls back atomically.
///
/// The caller is expected to refresh any in-memory caches (Riverpod
/// providers, store `_sessions` lists) after this call returns — the Rust
/// path writes through the DB directly without going through the per-store
/// add callbacks. `refreshAfterImport` runs once on success so the caller
/// can wire it to `sessionStore.loadAll()` + provider invalidation.
///
/// In replace mode, any failure is wrapped in [LfsImportRolledBackException]
/// so the UI surfaces the dedicated "data restored" message — the Rust
/// transaction guarantees the DB is back to its pre-import state.
Future<rust_archive.DbApplyResult> applyResultViaRust(
  ImportResult result, {
  Future<void> Function()? refreshAfterImport,
}) async {
  final staged = _stageFromResult(result);
  final handleId = await rust_archive.dbImportStage(input: staged);
  try {
    final apply = await rust_archive.dbImportApply(
      handleId: handleId,
      options: rust_archive.DbApplyOptions(
        mode: result.mode == ImportMode.replace
            ? rust_archive.DbImportMode.replace
            : rust_archive.DbImportMode.merge,
        applySessions:
            result.sessions.isNotEmpty || result.emptyFolders.isNotEmpty,
        applyKeys: result.managerKeys.isNotEmpty,
        applyTags: result.tags.isNotEmpty,
        applySnippets: result.snippets.isNotEmpty,
        applyKnownHosts:
            result.knownHostsContent != null &&
            result.knownHostsContent!.isNotEmpty,
      ),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (refreshAfterImport != null) {
      await refreshAfterImport();
    }
    return apply;
  } catch (e) {
    // Drop the staged handle on failure so the registry doesn't accumulate
    // orphans. `dbImportApply` on a successful path already takes the handle
    // out.
    try {
      await rust_archive.dbImportDrop(handleId: handleId);
    } catch (_) {}
    if (result.mode == ImportMode.replace) {
      throw LfsImportRolledBackException(cause: e);
    }
    rethrow;
  }
}

/// Serialise an [ImportResult] into the JSON-string envelope the Rust
/// apply driver consumes. Mirrors the field set
/// `lfs_core::archive::export_archive` emits — the Rust apply reader is
/// the same parser, so a round-trip
/// (Dart-built `ImportResult` → staged JSON → Rust apply) holds without
/// exporter / importer drift.
rust_archive.DbStagedImport _stageFromResult(ImportResult result) {
  final sessionsJson = result.sessions.isEmpty
      ? null
      : jsonEncode([for (final s in result.sessions) _sessionToJson(s)]);
  final keysJson = result.managerKeys.isEmpty
      ? null
      : jsonEncode([for (final k in result.managerKeys) _keyToJson(k)]);
  final tagsJson = result.tags.isEmpty
      ? null
      : jsonEncode([for (final t in result.tags) _tagToJson(t)]);
  // `ExportLink.sessionId` is the session's id; `targetId` is the
  // tag/snippet on the other end (the field is reused for both M2M
  // relations).
  final sessionTagsJson = result.sessionTags.isEmpty
      ? null
      : jsonEncode([
          for (final l in result.sessionTags)
            {'session_id': l.sessionId, 'tag_id': l.targetId},
        ]);
  // Folder→tag links carry the folder PATH, not an id — the Rust apply
  // driver currently keys junctions on folder_id, so these are dropped
  // for now. A follow-up resolves paths to freshly-minted folder ids the
  // same way `apply_folder_tree` does for sessions.
  const String? folderTagsJson = null;
  final _ = result.folderTags;
  final snippetsJson = result.snippets.isEmpty
      ? null
      : jsonEncode([for (final s in result.snippets) _snippetToJson(s)]);
  final sessionSnippetsJson = result.sessionSnippets.isEmpty
      ? null
      : jsonEncode([
          for (final l in result.sessionSnippets)
            {'session_id': l.sessionId, 'snippet_id': l.targetId},
        ]);
  final emptyFoldersJson = result.emptyFolders.isEmpty
      ? null
      : jsonEncode(result.emptyFolders.toList());
  return rust_archive.DbStagedImport(
    manifestJson: null,
    sessionsJson: sessionsJson,
    keysJson: keysJson,
    tagsJson: tagsJson,
    sessionTagsJson: sessionTagsJson,
    folderTagsJson: folderTagsJson,
    snippetsJson: snippetsJson,
    sessionSnippetsJson: sessionSnippetsJson,
    emptyFoldersJson: emptyFoldersJson,
    configJson: null, // config restore stays Dart-side via applyConfig
    knownHostsText: result.knownHostsContent,
  );
}

Map<String, Object?> _sessionToJson(Session s) {
  final obj = <String, Object?>{
    'id': s.id,
    'label': s.label,
    'folder': s.folder,
    'host': s.host,
    'port': s.port,
    'user': s.user,
    'auth_type': s.authType.name,
    'password': s.password,
    'key_path': s.keyPath,
    'key_data': s.keyData,
    'passphrase': s.passphrase,
    'created_at': _isoUtc(s.createdAt),
    'updated_at': _isoUtc(s.updatedAt),
  };
  if (s.keyId.isNotEmpty) {
    obj['key_id'] = s.keyId;
  }
  if (s.extras.isNotEmpty) {
    obj['extras'] = s.extras;
  }
  if (s.viaSessionId != null && s.viaSessionId!.isNotEmpty) {
    obj['via_session_id'] = s.viaSessionId;
  }
  final ov = s.viaOverride;
  if (ov != null) {
    obj['via_override'] = {'host': ov.host, 'port': ov.port, 'user': ov.user};
  }
  return obj;
}

Map<String, Object?> _keyToJson(SshKeyEntry k) => {
  'id': k.id,
  'label': k.label,
  'private_key': k.privateKey,
  'public_key': k.publicKey,
  'key_type': k.keyType,
  'is_generated': k.isGenerated,
  'created_at': _isoUtc(k.createdAt),
};

Map<String, Object?> _tagToJson(Tag t) => {
  'id': t.id,
  'name': t.name,
  if (t.color != null) 'color': t.color,
  'created_at': _isoUtc(t.createdAt),
};

Map<String, Object?> _snippetToJson(Snippet s) => {
  'id': s.id,
  'title': s.title,
  'command': s.command,
  'description': s.description,
  'created_at': _isoUtc(s.createdAt),
  'updated_at': _isoUtc(s.updatedAt),
};

String _isoUtc(DateTime dt) => dt.toUtc().toIso8601String();

/// Thrown by [applyResultViaRust] in replace mode when the Rust apply
/// fails and the surrounding sqlite transaction has rolled back the DB.
/// The UI surfaces this with a dedicated localized message ("Import failed
/// — your data has been restored") so the user knows the database is back
/// to the prior state, not in a half-imported limbo.
///
/// [cause] is the original failure (FK-violation, decode exception, etc.).
class LfsImportRolledBackException implements Exception {
  final Object cause;
  const LfsImportRolledBackException({required this.cause});

  @override
  String toString() => 'LfsImportRolledBackException: $cause';
}
