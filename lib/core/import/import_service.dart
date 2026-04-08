import '../../utils/logger.dart';
import '../config/app_config.dart';
import '../../features/settings/export_import.dart';
import '../security/credential_store.dart';
import '../session/session.dart';

/// Applies import results to session and config state.
///
/// Extracted from main.dart and settings_screen.dart to eliminate
/// duplication and enable testing without Riverpod/UI context.
class ImportService {
  final Future<void> Function(Session session) addSession;
  final Future<void> Function(String id) deleteSession;
  final List<Session> Function() getSessions;
  final void Function(AppConfig config) applyConfig;

  /// Optional callbacks for rollback support in replace mode.
  /// When provided, a snapshot is taken before deleting existing sessions.
  /// If import fails, the snapshot is restored.
  final Set<String> Function()? getEmptyFolders;
  final Future<Map<String, CredentialData>> Function(Set<String> ids)?
  loadCredentials;
  final Future<void> Function(
    List<Session> sessions,
    Set<String> emptyFolders,
    Map<String, CredentialData> credentials,
  )?
  restoreSnapshot;

  ImportService({
    required this.addSession,
    required this.deleteSession,
    required this.getSessions,
    required this.applyConfig,
    this.getEmptyFolders,
    this.loadCredentials,
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
      'hasConfig=${result.config != null}',
      name: 'Import',
    );

    final snapshot = result.mode == ImportMode.replace
        ? await _snapshotAndDeleteExisting()
        : null;

    final imported = await _importSessions(result, snapshot);

    if (result.config != null) {
      applyConfig(result.config!);
    }

    AppLogger.instance.log(
      'Import complete: $imported/${result.sessions.length} sessions imported',
      name: 'Import',
    );
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
      final creds = loadCredentials != null
          ? await loadCredentials!(existing.map((s) => s.id).toSet())
          : <String, CredentialData>{};
      snapshot = _Snapshot(existing, folders, creds);
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
      await restoreSnapshot!(
        snapshot.sessions,
        snapshot.folders,
        snapshot.credentials,
      );
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
  final Map<String, CredentialData> credentials;

  const _Snapshot(this.sessions, this.folders, this.credentials);
}
