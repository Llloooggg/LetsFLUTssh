import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../config/app_config.dart';
import '../security/key_store.dart';
import '../snippets/snippet.dart';
import '../tags/tag.dart';
import '../../features/settings/export_import.dart';
import '../session/qr_codec.dart' show ExportLink, ExportFolderTagLink;
import '../session/session.dart';

/// Applies import results to session and config state.
///
/// Extracted from main.dart and settings_screen.dart to eliminate
/// duplication and enable testing without Riverpod/UI context.
class ImportService {
  final Future<void> Function(Session session) addSession;
  final Future<void> Function(String folderPath) addEmptyFolder;
  final Future<void> Function(String id) deleteSession;
  final List<Session> Function() getSessions;
  final void Function(AppConfig config) applyConfig;

  /// Save a manager key and return its new ID (may differ from the original).
  final Future<String> Function(SshKeyEntry entry)? saveManagerKey;

  /// Tag import callbacks.
  final Future<String> Function(Tag tag)? saveTag;
  final Future<void> Function(String sessionId, String tagId)? tagSession;
  final Future<void> Function(String folderId, String tagId)? tagFolder;

  /// Snippet import callbacks.
  final Future<String> Function(Snippet snippet)? saveSnippet;
  final Future<void> Function(String snippetId, String sessionId)?
  linkSnippetToSession;

  /// Optional callbacks for rollback support in replace mode.
  /// When provided, a snapshot is taken before deleting existing sessions.
  /// If import fails, the snapshot is restored.
  final Set<String> Function()? getEmptyFolders;
  final Future<void> Function(List<Session> sessions, Set<String> emptyFolders)?
  restoreSnapshot;

  /// Existing ids in target stores — used to remap id collisions on merge so
  /// re-imported items land as `(copy)` alongside the existing ones instead
  /// of being silently skipped.
  final Future<Set<String>> Function()? existingTagIds;
  final Future<Set<String>> Function()? existingSnippetIds;

  /// Current config snapshot for rollback support in replace mode.
  final AppConfig Function()? getCurrentConfig;

  ImportService({
    required this.addSession,
    required this.addEmptyFolder,
    required this.deleteSession,
    required this.getSessions,
    required this.applyConfig,
    this.saveManagerKey,
    this.saveTag,
    this.tagSession,
    this.tagFolder,
    this.saveSnippet,
    this.linkSnippetToSession,
    this.getEmptyFolders,
    this.restoreSnapshot,
    this.existingTagIds,
    this.existingSnippetIds,
    this.getCurrentConfig,
  });

  /// Apply imported sessions and config.
  ///
  /// In replace mode, takes a snapshot before deleting existing sessions.
  /// If any import fails, the snapshot is restored to prevent data loss.
  ///
  /// In merge mode, id collisions with existing items (sessions/tags/snippets)
  /// are resolved by minting a fresh UUID and suffixing the label/name with
  /// `(copy)` — mirrors session duplication UX.
  Future<void> applyResult(ImportResult result) async {
    AppLogger.instance.log(
      'Applying import: mode=${result.mode.name}, '
      'sessions=${result.sessions.length}, '
      'managerKeys=${result.managerKeys.length}, '
      'hasConfig=${result.config != null}',
      name: 'Import',
    );

    final snapshot = result.mode == ImportMode.replace
        ? await _snapshotAndDeleteExisting()
        : null;

    try {
      await _applyCore(result, snapshot);
    } catch (_) {
      if (result.mode == ImportMode.replace) {
        await _tryRestore(snapshot);
      }
      rethrow;
    }
  }

  Future<void> _applyCore(ImportResult result, _Snapshot? snapshot) async {
    // Import manager keys first — build oldId→newId map for session remapping.
    // The saveManagerKey callback itself dedups by fingerprint (see KeyStore),
    // so this map will resolve incoming keys to either a brand-new or an
    // existing stored key id.
    final keyIdMap = await _importManagerKeys(result.managerKeys);

    // Remap session keyIds to the newly inserted key IDs
    var sessions = keyIdMap.isEmpty
        ? result.sessions
        : result.sessions.map((s) {
            final newKeyId = keyIdMap[s.keyId];
            if (newKeyId == null) return s;
            return s.copyWith(auth: s.auth.copyWith(keyId: newKeyId));
          }).toList();

    // Merge mode: remap colliding session ids to fresh UUIDs + "(copy)" label.
    // Replace mode: existing was cleared, no collisions possible.
    final sessionIdMap = <String, String>{};
    if (result.mode == ImportMode.merge) {
      final existing = getSessions().map((s) => s.id).toSet();
      sessions = sessions.map((s) {
        if (!existing.contains(s.id)) return s;
        final newId = const Uuid().v4();
        sessionIdMap[s.id] = newId;
        return Session(
          id: newId,
          label: s.label.isNotEmpty ? '${s.label} (copy)' : '',
          folder: s.folder,
          server: s.server,
          auth: s.auth,
          createdAt: s.createdAt,
        );
      }).toList();
    }

    final imported = await _importSessions(
      ImportResult(
        sessions: sessions,
        emptyFolders: result.emptyFolders,
        mode: result.mode,
      ),
      snapshot,
    );

    // Import empty folders
    var foldersImported = 0;
    for (final folder in result.emptyFolders) {
      try {
        await addEmptyFolder(folder);
        foldersImported++;
      } catch (e) {
        if (result.mode == ImportMode.replace) rethrow;
        AppLogger.instance.log(
          'Skipped empty folder $folder: $e',
          name: 'Import',
        );
      }
    }

    // Import tags and their session/folder assignments
    final tagIdMap = await _importTags(result.tags, result.mode);
    await _importTagLinks(
      result.sessionTags,
      result.folderTags,
      tagIdMap,
      sessionIdMap,
    );

    // Import snippets and their session links
    final snippetIdMap = await _importSnippets(result.snippets, result.mode);
    await _importSnippetLinks(
      result.sessionSnippets,
      snippetIdMap,
      sessionIdMap,
    );

    // Apply config last. Merge mode: log and continue (config is independent
    // of imported sessions). Replace mode: propagate so the outer catch in
    // applyResult rolls back sessions/folders/config atomically.
    if (result.config != null) {
      if (result.mode == ImportMode.replace) {
        applyConfig(result.config!);
      } else {
        try {
          applyConfig(result.config!);
        } catch (e) {
          AppLogger.instance.log(
            'Failed to apply config: $e',
            name: 'Import',
            error: e,
          );
        }
      }
    }

    AppLogger.instance.log(
      'Import complete: $imported/${result.sessions.length} sessions, '
      '$foldersImported/${result.emptyFolders.length} folders, '
      '${tagIdMap.length}/${result.tags.length} tags, '
      '${snippetIdMap.length}/${result.snippets.length} snippets imported',
      name: 'Import',
    );
  }

  /// Import manager keys into KeyStore. Returns a map of oldId→newId
  /// for remapping session keyIds.
  Future<Map<String, String>> _importManagerKeys(List<SshKeyEntry> keys) async {
    if (keys.isEmpty || saveManagerKey == null) return {};
    final idMap = <String, String>{};
    for (final key in keys) {
      try {
        final newId = await saveManagerKey!(key);
        idMap[key.id] = newId;
      } catch (e) {
        AppLogger.instance.log(
          'Skipped manager key ${key.label}: $e',
          name: 'Import',
        );
      }
    }
    AppLogger.instance.log(
      'Imported ${idMap.length}/${keys.length} manager keys',
      name: 'Import',
    );
    return idMap;
  }

  /// Import tags. Returns oldId→newId map. On merge mode, tags whose id
  /// collides with an existing one are inserted with a fresh UUID and a
  /// `(copy)` suffix on the name.
  Future<Map<String, String>> _importTags(
    List<Tag> tags,
    ImportMode mode,
  ) async {
    if (tags.isEmpty || saveTag == null) return {};
    final existing = mode == ImportMode.merge && existingTagIds != null
        ? await existingTagIds!()
        : const <String>{};
    final idMap = <String, String>{};
    for (final tag in tags) {
      try {
        final effective = existing.contains(tag.id)
            ? Tag(
                id: const Uuid().v4(),
                name: tag.name.isNotEmpty ? '${tag.name} (copy)' : tag.name,
                color: tag.color,
                createdAt: tag.createdAt,
              )
            : tag;
        final newId = await saveTag!(effective);
        idMap[tag.id] = newId;
      } catch (e) {
        AppLogger.instance.log('Skipped tag ${tag.name}: $e', name: 'Import');
      }
    }
    return idMap;
  }

  /// Apply session→tag and folder→tag links with remapped IDs.
  Future<void> _importTagLinks(
    List<ExportLink> sessionLinks,
    List<ExportFolderTagLink> folderLinks,
    Map<String, String> tagIdMap,
    Map<String, String> sessionIdMap,
  ) async {
    if (tagSession != null) {
      for (final link in sessionLinks) {
        final newTagId = tagIdMap[link.targetId] ?? link.targetId;
        final newSessionId = sessionIdMap[link.sessionId] ?? link.sessionId;
        try {
          await tagSession!(newSessionId, newTagId);
        } catch (e) {
          AppLogger.instance.log(
            'Skipped session-tag link: $e',
            name: 'Import',
          );
        }
      }
    }
    if (tagFolder != null) {
      for (final link in folderLinks) {
        final newTagId = tagIdMap[link.tagId] ?? link.tagId;
        try {
          await tagFolder!(link.folderPath, newTagId);
        } catch (e) {
          AppLogger.instance.log('Skipped folder-tag link: $e', name: 'Import');
        }
      }
    }
  }

  /// Import snippets. Returns oldId→newId map. Same id-collision handling
  /// as [_importTags].
  Future<Map<String, String>> _importSnippets(
    List<Snippet> snippets,
    ImportMode mode,
  ) async {
    if (snippets.isEmpty || saveSnippet == null) return {};
    final existing = mode == ImportMode.merge && existingSnippetIds != null
        ? await existingSnippetIds!()
        : const <String>{};
    final idMap = <String, String>{};
    for (final snippet in snippets) {
      try {
        final effective = existing.contains(snippet.id)
            ? Snippet(
                id: const Uuid().v4(),
                title: snippet.title.isNotEmpty
                    ? '${snippet.title} (copy)'
                    : snippet.title,
                command: snippet.command,
                description: snippet.description,
                createdAt: snippet.createdAt,
                updatedAt: snippet.updatedAt,
              )
            : snippet;
        final newId = await saveSnippet!(effective);
        idMap[snippet.id] = newId;
      } catch (e) {
        AppLogger.instance.log(
          'Skipped snippet ${snippet.title}: $e',
          name: 'Import',
        );
      }
    }
    return idMap;
  }

  /// Apply session→snippet links with remapped IDs.
  Future<void> _importSnippetLinks(
    List<ExportLink> links,
    Map<String, String> snippetIdMap,
    Map<String, String> sessionIdMap,
  ) async {
    if (linkSnippetToSession == null) return;
    for (final link in links) {
      final newSnippetId = snippetIdMap[link.targetId] ?? link.targetId;
      final newSessionId = sessionIdMap[link.sessionId] ?? link.sessionId;
      try {
        await linkSnippetToSession!(newSnippetId, newSessionId);
      } catch (e) {
        AppLogger.instance.log(
          'Skipped session-snippet link: $e',
          name: 'Import',
        );
      }
    }
  }

  /// Takes a snapshot of existing sessions (when rollback callbacks are
  /// available) and deletes them. Returns the snapshot for rollback.
  Future<_Snapshot?> _snapshotAndDeleteExisting() async {
    final existing = List<Session>.of(getSessions());
    _Snapshot? snapshot;

    if (restoreSnapshot != null) {
      final folders = getEmptyFolders != null
          ? Set.of(getEmptyFolders!())
          : <String>{};
      final config = getCurrentConfig?.call();
      snapshot = _Snapshot(existing, folders, config);
    }

    AppLogger.instance.log(
      'Replace mode: deleting ${existing.length} existing sessions',
      name: 'Import',
    );
    for (final s in existing) {
      await deleteSession(s.id);
    }

    return snapshot;
  }

  /// Imports sessions from the result. On failure in replace mode, rethrows
  /// so the outer applyResult can roll back the full snapshot (sessions +
  /// folders + config).
  Future<int> _importSessions(ImportResult result, _Snapshot? snapshot) async {
    var imported = 0;
    for (final s in result.sessions) {
      try {
        await addSession(s);
        imported++;
      } catch (e) {
        if (result.mode == ImportMode.replace) rethrow;
        AppLogger.instance.log(
          'Skipped session ${s.label}: $e',
          name: 'Import',
        );
      }
    }
    return imported;
  }

  /// Attempt to restore a pre-import snapshot. Logs but does not throw
  /// on failure — the original import error takes priority.
  Future<void> _tryRestore(_Snapshot? snapshot) async {
    if (restoreSnapshot == null || snapshot == null) return;
    try {
      await restoreSnapshot!(snapshot.sessions, snapshot.folders);
      if (snapshot.config != null) {
        try {
          applyConfig(snapshot.config!);
        } catch (e) {
          AppLogger.instance.log(
            'Failed to restore config after import failure',
            name: 'Import',
            error: e,
          );
        }
      }
      AppLogger.instance.log(
        'Restored ${snapshot.sessions.length} sessions after import failure',
        name: 'Import',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to restore snapshot after import failure',
        name: 'Import',
        error: e,
      );
    }
  }
}

class _Snapshot {
  final List<Session> sessions;
  final Set<String> folders;
  final AppConfig? config;

  const _Snapshot(this.sessions, this.folders, this.config);
}
