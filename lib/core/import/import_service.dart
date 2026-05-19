import '../../src/rust/api/archive.dart' as rust_archive;
import '../../src/rust/api/archive_stage.dart' as rust_stage;
import '../../src/rust/api/config.dart' as rust_config;
import '../config/app_config.dart';
import '../security/ssh_key.dart';
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
/// Used by callers that hold an in-memory [ImportResult] tree
/// (QR import, paste-link import, OpenSSH config import). For
/// `.lfs` archive imports the bytes are decoded Rust-side and the
/// caller routes through [applyOpenedHandle] instead — no Dart-side
/// staging round-trip.
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
  return _applyHandle(
    handleId: handleId,
    mode: result.mode,
    applySessions: result.sessions.isNotEmpty || result.emptyFolders.isNotEmpty,
    applyKeys: result.managerKeys.isNotEmpty,
    applyTags: result.tags.isNotEmpty,
    applySnippets: result.snippets.isNotEmpty,
    applyKnownHosts:
        result.knownHostsContent != null &&
        result.knownHostsContent!.isNotEmpty,
    // Staged-import callers (QR / paste-link / OpenSSH) ship the
    // bandwidth-bound subset — recordings never travel through
    // their pipeline; pass `false` so the apply driver does not
    // even check the (empty) pending.recordings list.
    applyRecordings: false,
    refreshAfterImport: refreshAfterImport,
  );
}

/// Apply an already-staged Rust-side import handle (from
/// `dbImportOpen`). The Rust apply driver consumes the handle on
/// success; failures wrap into [LfsImportRolledBackException] in
/// replace mode same as [applyResultViaRust]. Caller passes the
/// per-entity toggles from the preview dialog.
Future<rust_archive.DbApplyResult> applyOpenedHandle({
  required String handleId,
  required ImportMode mode,
  required bool applySessions,
  required bool applyKeys,
  required bool applyTags,
  required bool applySnippets,
  required bool applyKnownHosts,
  required bool applyRecordings,
  Future<void> Function()? refreshAfterImport,
}) {
  return _applyHandle(
    handleId: handleId,
    mode: mode,
    applySessions: applySessions,
    applyKeys: applyKeys,
    applyTags: applyTags,
    applySnippets: applySnippets,
    applyKnownHosts: applyKnownHosts,
    applyRecordings: applyRecordings,
    refreshAfterImport: refreshAfterImport,
  );
}

Future<rust_archive.DbApplyResult> _applyHandle({
  required String handleId,
  required ImportMode mode,
  required bool applySessions,
  required bool applyKeys,
  required bool applyTags,
  required bool applySnippets,
  required bool applyKnownHosts,
  required bool applyRecordings,
  Future<void> Function()? refreshAfterImport,
}) async {
  try {
    final apply = await rust_archive.dbImportApply(
      handleId: handleId,
      options: rust_archive.DbApplyOptions(
        mode: mode == ImportMode.replace
            ? rust_archive.DbImportMode.replace
            : rust_archive.DbImportMode.merge,
        applySessions: applySessions,
        applyKeys: applyKeys,
        applyTags: applyTags,
        applySnippets: applySnippets,
        applyKnownHosts: applyKnownHosts,
        applyRecordings: applyRecordings,
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
    if (mode == ImportMode.replace) {
      throw LfsImportRolledBackException(cause: e);
    }
    rethrow;
  }
}

/// Decode an [AppConfig] from the JSON returned by [applyOpenedHandle]
/// / [applyResultViaRust] in `DbApplyResult.configJson`. Returns null
/// if the staged archive carried no config entry. Routes through the
/// canonical Rust-side parser via [`config_app_config_from_json_typed`]
/// so the JSON grammar (field defaults, schema-version stamping,
/// sanitisation clamps) lives one place; a malformed blob collapses
/// to `null` — the import driver treats that as "no config entry".
AppConfig? decodeConfigFromApply(rust_archive.DbApplyResult apply) {
  final raw = apply.configJson;
  if (raw == null || raw.isEmpty) return null;
  final typed = rust_config.configAppConfigFromJsonTyped(inputJson: raw);
  if (typed == null) return null;
  return AppConfig.fromTyped(typed);
}

/// Serialise an [ImportResult] into the JSON-string envelope the Rust
/// apply driver consumes. Mirrors the field set
/// `lfs_core::archive::export_archive` emits — the Rust apply reader is
/// the same parser, so a round-trip
/// (Dart-built `ImportResult` → staged JSON → Rust apply) holds without
/// exporter / importer drift.
///
/// Sessions / keys / tags / snippets / link-tables / empty-folders
/// all route through `lfs_core::archive_stage::stage_*_to_json` (FRB
/// sync). The JSON-shape contract — field names, default-omission,
/// ISO timestamp formatting, nested `via_override` object, the
/// link-table column names — lives one place: the apply driver
/// re-parses the same JSON the stagers emit, and a wire-format bump
/// is a single Rust-side edit.
rust_archive.DbStagedImport _stageFromResult(ImportResult result) {
  final sessionsJson = _stageSessionsJson(result.sessions);
  final keysJson = _stageKeysJson(result.managerKeys);
  final tagsJson = _stageTagsJson(result.tags);
  // `ExportLink.sessionId` is the session's id; `targetId` is the
  // tag/snippet on the other end (the field is reused for both M2M
  // relations).
  final sessionTagsJson = rust_stage.archiveStageSessionTagsToJson(
    rows: [
      for (final l in result.sessionTags)
        rust_stage.DbStagedSessionTagLink(
          sessionId: l.sessionId,
          tagId: l.targetId,
        ),
    ],
  );
  // Folder→tag links carry the folder PATH; the Rust apply driver
  // resolves it against the freshly-built `folder_path → folder_id`
  // map populated by `apply_folder_tree` + `apply_empty_folders`.
  final folderTagsJson = rust_stage.archiveStageFolderTagsToJson(
    rows: [
      for (final l in result.folderTags)
        rust_stage.DbStagedFolderTagLink(
          folderPath: l.folderPath,
          tagId: l.tagId,
        ),
    ],
  );
  final snippetsJson = _stageSnippetsJson(result.snippets);
  final sessionSnippetsJson = rust_stage.archiveStageSessionSnippetsToJson(
    rows: [
      for (final l in result.sessionSnippets)
        rust_stage.DbStagedSessionSnippetLink(
          sessionId: l.sessionId,
          snippetId: l.targetId,
        ),
    ],
  );
  final emptyFoldersJson = rust_stage.archiveStageEmptyFoldersToJson(
    paths: result.emptyFolders.toList(),
  );
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

/// Sessions / keys / tags / snippets all route through
/// `lfs_core::archive_stage::stage_*_to_json` (FRB sync) — that's the
/// only path. The Rust stagers are the canonical wire format; any
/// caller needing to stage in flutter_test must bootstrap RustLib like
/// the integration suite does.
String? _stageSessionsJson(List<Session> sessions) {
  if (sessions.isEmpty) return null;
  return rust_stage.archiveStageSessionsToJson(
    rows: [
      for (final s in sessions)
        rust_stage.DbStagedSessionImport(
          id: s.id,
          label: s.label,
          folder: s.folder,
          host: s.host,
          port: s.port,
          user: s.user,
          authType: s.authType.name,
          password: s.password,
          keyPath: s.keyPath,
          keyData: s.keyData,
          passphrase: s.passphrase,
          keyId: s.keyId.isEmpty ? null : s.keyId,
          extrasJson: extrasMapToJson(s.extras),
          viaSessionId: (s.viaSessionId == null || s.viaSessionId!.isEmpty)
              ? null
              : s.viaSessionId,
          viaOverrideHost: s.viaOverride?.host,
          viaOverridePort: s.viaOverride?.port,
          viaOverrideUser: s.viaOverride?.user,
          createdAtMs: s.createdAt.millisecondsSinceEpoch,
          updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
        ),
    ],
  );
}

String? _stageKeysJson(List<SshKeyEntry> keys) {
  if (keys.isEmpty) return null;
  return rust_stage.archiveStageKeysToJson(
    rows: [
      for (final k in keys)
        rust_stage.DbStagedKeyImport(
          id: k.id,
          label: k.label,
          privateKey: k.privateKey,
          publicKey: k.publicKey,
          keyType: k.keyType,
          isGenerated: k.isGenerated,
          createdAtMs: k.createdAt.millisecondsSinceEpoch,
        ),
    ],
  );
}

String? _stageTagsJson(List<Tag> tags) {
  if (tags.isEmpty) return null;
  return rust_stage.archiveStageTagsToJson(
    rows: [
      for (final t in tags)
        rust_stage.DbStagedTagImport(
          id: t.id,
          name: t.name,
          color: t.color,
          createdAtMs: t.createdAt.millisecondsSinceEpoch,
        ),
    ],
  );
}

String? _stageSnippetsJson(List<Snippet> snippets) {
  if (snippets.isEmpty) return null;
  return rust_stage.archiveStageSnippetsToJson(
    rows: [
      for (final s in snippets)
        rust_stage.DbStagedSnippetImport(
          id: s.id,
          title: s.title,
          command: s.command,
          description: s.description,
          createdAtMs: s.createdAt.millisecondsSinceEpoch,
          updatedAtMs: s.updatedAt.millisecondsSinceEpoch,
        ),
    ],
  );
}

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
