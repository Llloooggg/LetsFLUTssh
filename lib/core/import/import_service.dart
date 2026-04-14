import '../../utils/logger.dart';
import '../config/app_config.dart';
import '../security/key_store.dart';
import '../../features/settings/export_import.dart';
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

  /// Optional callbacks for rollback support in replace mode.
  /// When provided, a snapshot is taken before deleting existing sessions.
  /// If import fails, the snapshot is restored.
  final Set<String> Function()? getEmptyFolders;
  final Future<void> Function(List<Session> sessions, Set<String> emptyFolders)?
  restoreSnapshot;

  ImportService({
    required this.addSession,
    required this.addEmptyFolder,
    required this.deleteSession,
    required this.getSessions,
    required this.applyConfig,
    this.saveManagerKey,
    this.getEmptyFolders,
    this.restoreSnapshot,
  });

  /// Apply imported sessions and config.
  ///
  /// In replace mode, takes a snapshot before deleting existing sessions.
  /// If any import fails, the snapshot is restored to prevent data loss.
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

    // Import manager keys first — build oldId→newId map for session remapping
    final keyIdMap = await _importManagerKeys(result.managerKeys);

    // Remap session keyIds to the newly inserted key IDs
    final remappedResult = keyIdMap.isEmpty
        ? result
        : ImportResult(
            sessions: result.sessions.map((s) {
              final newKeyId = keyIdMap[s.keyId];
              if (newKeyId == null) return s;
              return s.copyWith(auth: s.auth.copyWith(keyId: newKeyId));
            }).toList(),
            emptyFolders: result.emptyFolders,
            managerKeys: result.managerKeys,
            config: result.config,
            mode: result.mode,
            knownHostsContent: result.knownHostsContent,
          );

    final imported = await _importSessions(remappedResult, snapshot);

    // Import empty folders.
    // NOTE: in replace mode this code is never reached if _importSessions
    // throws — the entire import is rolled back (including folders) to
    // prevent partial state.
    var foldersImported = 0;
    for (final folder in result.emptyFolders) {
      try {
        await addEmptyFolder(folder);
        foldersImported++;
      } catch (e) {
        if (result.mode == ImportMode.replace) {
          await _tryRestore(snapshot);
          rethrow;
        }
        AppLogger.instance.log(
          'Skipped empty folder $folder: $e',
          name: 'Import',
        );
      }
    }

    // Apply config
    if (result.config != null) {
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

    AppLogger.instance.log(
      'Import complete: $imported/${result.sessions.length} sessions, '
      '$foldersImported/${result.emptyFolders.length} folders imported',
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

  /// Takes a snapshot of existing sessions (when rollback callbacks are
  /// available) and deletes them. Returns the snapshot for rollback.
  Future<_Snapshot?> _snapshotAndDeleteExisting() async {
    final existing = List<Session>.of(getSessions());
    _Snapshot? snapshot;

    if (restoreSnapshot != null) {
      final folders = getEmptyFolders != null
          ? Set.of(getEmptyFolders!())
          : <String>{};
      snapshot = _Snapshot(existing, folders);
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

  /// Imports sessions from the result. On failure in replace mode, attempts
  /// rollback from [snapshot]. Returns the count of successfully imported
  /// sessions.
  Future<int> _importSessions(ImportResult result, _Snapshot? snapshot) async {
    var imported = 0;
    for (final s in result.sessions) {
      try {
        await addSession(s);
        imported++;
      } catch (e) {
        if (result.mode == ImportMode.replace) {
          await _tryRestore(snapshot);
          rethrow;
        }
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

  const _Snapshot(this.sessions, this.folders);
}
