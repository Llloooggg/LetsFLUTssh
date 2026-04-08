import '../../utils/logger.dart';
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
  final void Function(dynamic config) applyConfig;

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

    // Snapshot for rollback (replace mode only, when callbacks available)
    List<Session>? snapshotSessions;
    Set<String>? snapshotFolders;
    Map<String, CredentialData>? snapshotCreds;

    if (result.mode == ImportMode.replace) {
      final existing = List<Session>.of(getSessions());

      if (restoreSnapshot != null) {
        snapshotSessions = existing;
        snapshotFolders = getEmptyFolders != null
            ? Set.of(getEmptyFolders!())
            : <String>{};
        snapshotCreds = loadCredentials != null
            ? await loadCredentials!(existing.map((s) => s.id).toSet())
            : <String, CredentialData>{};
      }

      AppLogger.instance.log(
        'Replace mode: deleting ${existing.length} existing sessions',
        name: 'Import',
      );
      for (final s in existing) {
        await deleteSession(s.id);
      }
    }

    var imported = 0;
    for (final s in result.sessions) {
      try {
        await addSession(s);
        imported++;
      } catch (e) {
        if (result.mode == ImportMode.replace) {
          await _tryRestore(snapshotSessions, snapshotFolders, snapshotCreds);
          rethrow;
        }
        AppLogger.instance.log(
          'Skipped session ${s.label}: $e',
          name: 'Import',
        );
      }
    }

    if (result.config != null) {
      applyConfig(result.config!);
    }

    AppLogger.instance.log(
      'Import complete: $imported/${result.sessions.length} sessions imported',
      name: 'Import',
    );
  }

  /// Attempt to restore a pre-import snapshot. Logs but does not throw
  /// on failure — the original import error takes priority.
  Future<void> _tryRestore(
    List<Session>? sessions,
    Set<String>? folders,
    Map<String, CredentialData>? creds,
  ) async {
    if (restoreSnapshot == null || sessions == null) return;
    try {
      await restoreSnapshot!(sessions, folders ?? {}, creds ?? {});
      AppLogger.instance.log(
        'Restored ${sessions.length} sessions after import failure',
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
