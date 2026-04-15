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

  /// Replace-mode wipe + rollback hooks. When [ImportResult.includeTags] /
  /// `includeSnippets` / `includeKnownHosts` is true in replace mode, the
  /// corresponding local store is snapshotted and cleared before the import
  /// writes new rows — otherwise duplicate IDs or unique-name conflicts
  /// (e.g. `Tags.name` UNIQUE) would abort the import. If the import later
  /// throws, the captured lists are replayed back in.
  final Future<List<Tag>> Function()? loadAllTags;
  final Future<void> Function()? deleteAllTags;
  final Future<List<Snippet>> Function()? loadAllSnippets;
  final Future<void> Function()? deleteAllSnippets;
  final Future<String> Function()? exportKnownHosts;
  final Future<void> Function()? clearKnownHosts;
  final Future<void> Function(String content)? importKnownHosts;

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
    this.loadAllTags,
    this.deleteAllTags,
    this.loadAllSnippets,
    this.deleteAllSnippets,
    this.exportKnownHosts,
    this.clearKnownHosts,
    this.importKnownHosts,
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
        ? await _snapshotAndDeleteExisting(result)
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
    // Import manager keys first — the saveManagerKey callback dedups by
    // fingerprint (see KeyStore), so the returned map resolves incoming keys
    // to either a brand-new or an existing stored key id.
    final keyIdMap = await _importManagerKeys(result.managerKeys);
    final rekeyedSessions = _remapSessionKeyIds(result.sessions, keyIdMap);

    // Merge mode: remap colliding session ids to fresh UUIDs + "(copy)" label.
    // Replace mode: existing was cleared, no collisions possible.
    final (sessions, sessionIdMap) = result.mode == ImportMode.merge
        ? _resolveSessionCollisions(rekeyedSessions)
        : (rekeyedSessions, const <String, String>{});

    final imported = await _importSessions(
      ImportResult(
        sessions: sessions,
        emptyFolders: result.emptyFolders,
        mode: result.mode,
      ),
      snapshot,
    );

    final foldersImported = await _importEmptyFolders(
      result.emptyFolders,
      result.mode,
    );

    final tagIdMap = await _importTags(result.tags, result.mode);
    await _importTagLinks(
      result.sessionTags,
      result.folderTags,
      tagIdMap,
      sessionIdMap,
    );

    final snippetIdMap = await _importSnippets(result.snippets, result.mode);
    await _importSnippetLinks(
      result.sessionSnippets,
      snippetIdMap,
      sessionIdMap,
    );

    _applyImportedConfig(result);
    await _applyImportedKnownHosts(result);

    AppLogger.instance.log(
      'Import complete: $imported/${result.sessions.length} sessions, '
      '$foldersImported/${result.emptyFolders.length} folders, '
      '${tagIdMap.length}/${result.tags.length} tags, '
      '${snippetIdMap.length}/${result.snippets.length} snippets imported',
      name: 'Import',
    );
  }

  /// Rewrite session `keyId` fields using the manager-key id map.
  ///
  /// Sessions referencing a keyId that is not in [keyIdMap] get their keyId
  /// nulled out — the referenced key was not imported (either not included
  /// in the archive or filtered out by the user), so keeping the id would
  /// cause a `FOREIGN KEY constraint failed` on insert. The session is still
  /// imported; the user can re-associate a key afterwards.
  List<Session> _remapSessionKeyIds(
    List<Session> sessions,
    Map<String, String> keyIdMap,
  ) {
    return sessions.map((s) {
      final oldKeyId = s.keyId;
      if (oldKeyId.isEmpty) return s;
      final newKeyId = keyIdMap[oldKeyId];
      if (newKeyId == null) {
        return s.copyWith(auth: s.auth.copyWith(keyId: ''));
      }
      return s.copyWith(auth: s.auth.copyWith(keyId: newKeyId));
    }).toList();
  }

  /// Resolve merge-mode session id collisions by minting a fresh UUID and
  /// suffixing the label with `(copy)`. Returns the remapped list and an
  /// oldId→newId map for downstream link rewriting.
  (List<Session>, Map<String, String>) _resolveSessionCollisions(
    List<Session> sessions,
  ) {
    final existing = getSessions().map((s) => s.id).toSet();
    final idMap = <String, String>{};
    final remapped = sessions.map((s) {
      if (!existing.contains(s.id)) return s;
      final newId = const Uuid().v4();
      idMap[s.id] = newId;
      return Session(
        id: newId,
        label: _withCopySuffix(s.label),
        folder: s.folder,
        server: s.server,
        auth: s.auth,
        createdAt: s.createdAt,
      );
    }).toList();
    return (remapped, idMap);
  }

  /// Import the empty-folder set, counting successes. In replace mode a
  /// single failure aborts the import so the outer catch can roll back;
  /// merge mode logs and continues.
  Future<int> _importEmptyFolders(Set<String> folders, ImportMode mode) async {
    var imported = 0;
    for (final folder in folders) {
      try {
        await addEmptyFolder(folder);
        imported++;
      } catch (e) {
        if (mode == ImportMode.replace) rethrow;
        AppLogger.instance.log('Skipped empty folder: $e', name: 'Import');
      }
    }
    return imported;
  }

  /// Apply the imported config. Merge mode logs and swallows failures (config
  /// is independent of sessions); replace mode lets them propagate so the
  /// outer catch in [applyResult] rolls back atomically.
  void _applyImportedConfig(ImportResult result) {
    final config = result.config;
    if (config == null) return;
    if (result.mode == ImportMode.replace) {
      applyConfig(config);
      return;
    }
    try {
      applyConfig(config);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to apply config: $e',
        name: 'Import',
        error: e,
      );
    }
  }

  /// Append known_hosts content from the archive. In replace mode the store
  /// was already cleared in the snapshot step; in merge mode new entries are
  /// added and existing host:port rows are skipped by the importer.
  Future<void> _applyImportedKnownHosts(ImportResult result) async {
    final content = result.knownHostsContent;
    if (content == null || content.isEmpty) return;
    if (importKnownHosts == null) return;
    try {
      await importKnownHosts!(content);
    } catch (e) {
      if (result.mode == ImportMode.replace) rethrow;
      AppLogger.instance.log(
        'Failed to import known_hosts: $e',
        name: 'Import',
        error: e,
      );
    }
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
        AppLogger.instance.log('Skipped manager key: $e', name: 'Import');
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
        final Tag effective;
        if (existing.contains(tag.id)) {
          effective = Tag(
            id: const Uuid().v4(),
            name: _withCopySuffix(tag.name),
            color: tag.color,
            createdAt: tag.createdAt,
          );
        } else {
          effective = tag;
        }
        final newId = await saveTag!(effective);
        idMap[tag.id] = newId;
      } catch (e) {
        AppLogger.instance.log('Skipped tag: $e', name: 'Import');
      }
    }
    return idMap;
  }

  /// Append `(copy)` to a non-empty label. Returns the input unchanged if
  /// empty so we never produce a lone `(copy)` string.
  static String _withCopySuffix(String label) =>
      label.isEmpty ? label : '$label (copy)';

  /// Apply session→tag and folder→tag links with remapped IDs.
  Future<void> _importTagLinks(
    List<ExportLink> sessionLinks,
    List<ExportFolderTagLink> folderLinks,
    Map<String, String> tagIdMap,
    Map<String, String> sessionIdMap,
  ) async {
    if (tagSession != null) {
      for (final link in sessionLinks) {
        final newTagId = tagIdMap[link.targetId];
        if (newTagId == null) continue; // tag not imported — would FK-fail
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
        final newTagId = tagIdMap[link.tagId];
        if (newTagId == null) continue;
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
        final Snippet effective;
        if (existing.contains(snippet.id)) {
          effective = Snippet(
            id: const Uuid().v4(),
            title: _withCopySuffix(snippet.title),
            command: snippet.command,
            description: snippet.description,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt,
          );
        } else {
          effective = snippet;
        }
        final newId = await saveSnippet!(effective);
        idMap[snippet.id] = newId;
      } catch (e) {
        AppLogger.instance.log('Skipped snippet: $e', name: 'Import');
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
      final newSnippetId = snippetIdMap[link.targetId];
      // snippet not imported — would FK-fail
      if (newSnippetId == null) continue;
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

  /// Takes a snapshot of existing data and clears the stores that the user
  /// asked to replace. Returns the snapshot for rollback.
  ///
  /// Sessions are always cleared in replace mode (that's the defining
  /// behavior). Tags / snippets / known_hosts are only cleared when the
  /// corresponding `includeX` flag on [result] is set — an unchecked type
  /// stays untouched.
  Future<_Snapshot?> _snapshotAndDeleteExisting(ImportResult result) async {
    final existing = List<Session>.of(getSessions());

    final folders = getEmptyFolders != null
        ? Set.of(getEmptyFolders!())
        : <String>{};
    final config = getCurrentConfig?.call();

    final List<Tag> tagsBackup = result.includeTags && loadAllTags != null
        ? await loadAllTags!()
        : const [];
    final List<Snippet> snippetsBackup =
        result.includeSnippets && loadAllSnippets != null
        ? await loadAllSnippets!()
        : const [];
    final String? knownHostsBackup =
        result.includeKnownHosts && exportKnownHosts != null
        ? await exportKnownHosts!()
        : null;

    final snapshot = _Snapshot(
      sessions: existing,
      folders: folders,
      config: config,
      tags: tagsBackup,
      snippets: snippetsBackup,
      knownHosts: knownHostsBackup,
    );

    AppLogger.instance.log(
      'Replace mode: clearing sessions=${existing.length}, '
      'tags=${result.includeTags ? tagsBackup.length : "skip"}, '
      'snippets=${result.includeSnippets ? snippetsBackup.length : "skip"}, '
      'knownHosts=${result.includeKnownHosts ? "yes" : "skip"}',
      name: 'Import',
    );

    for (final s in existing) {
      await deleteSession(s.id);
    }
    if (result.includeTags && deleteAllTags != null) {
      await deleteAllTags!();
    }
    if (result.includeSnippets && deleteAllSnippets != null) {
      await deleteAllSnippets!();
    }
    if (result.includeKnownHosts && clearKnownHosts != null) {
      await clearKnownHosts!();
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
        AppLogger.instance.log('Skipped session: $e', name: 'Import');
      }
    }
    return imported;
  }

  /// Attempt to restore a pre-import snapshot. Logs but does not throw
  /// on failure — the original import error takes priority.
  Future<void> _tryRestore(_Snapshot? snapshot) async {
    if (snapshot == null) return;
    if (restoreSnapshot != null) {
      try {
        await restoreSnapshot!(snapshot.sessions, snapshot.folders);
      } catch (e) {
        AppLogger.instance.log(
          'Failed to restore sessions snapshot',
          name: 'Import',
          error: e,
        );
      }
    }
    if (snapshot.config != null) {
      try {
        applyConfig(snapshot.config!);
      } catch (e) {
        AppLogger.instance.log(
          'Failed to restore config',
          name: 'Import',
          error: e,
        );
      }
    }
    await _restoreTags(snapshot.tags);
    await _restoreSnippets(snapshot.snippets);
    await _restoreKnownHosts(snapshot.knownHosts);
    AppLogger.instance.log(
      'Restored ${snapshot.sessions.length} sessions, '
      '${snapshot.tags.length} tags, ${snapshot.snippets.length} snippets '
      'after import failure',
      name: 'Import',
    );
  }

  Future<void> _restoreTags(List<Tag> tags) async {
    if (tags.isEmpty || saveTag == null || deleteAllTags == null) return;
    try {
      await deleteAllTags!();
      for (final t in tags) {
        await saveTag!(t);
      }
    } catch (e) {
      AppLogger.instance.log(
        'Failed to restore tags snapshot',
        name: 'Import',
        error: e,
      );
    }
  }

  Future<void> _restoreSnippets(List<Snippet> snippets) async {
    if (snippets.isEmpty || saveSnippet == null || deleteAllSnippets == null) {
      return;
    }
    try {
      await deleteAllSnippets!();
      for (final s in snippets) {
        await saveSnippet!(s);
      }
    } catch (e) {
      AppLogger.instance.log(
        'Failed to restore snippets snapshot',
        name: 'Import',
        error: e,
      );
    }
  }

  Future<void> _restoreKnownHosts(String? content) async {
    if (content == null ||
        importKnownHosts == null ||
        clearKnownHosts == null) {
      return;
    }
    try {
      await clearKnownHosts!();
      if (content.isNotEmpty) await importKnownHosts!(content);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to restore known_hosts snapshot',
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
  final List<Tag> tags;
  final List<Snippet> snippets;
  final String? knownHosts;

  const _Snapshot({
    required this.sessions,
    required this.folders,
    required this.config,
    this.tags = const [],
    this.snippets = const [],
    this.knownHosts,
  });
}
