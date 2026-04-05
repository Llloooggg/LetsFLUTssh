import '../../utils/logger.dart';
import '../../features/settings/export_import.dart';
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

  ImportService({
    required this.addSession,
    required this.deleteSession,
    required this.getSessions,
    required this.applyConfig,
  });

  /// Apply imported sessions and config.
  Future<void> applyResult(ImportResult result) async {
    AppLogger.instance.log(
      'Applying import: mode=${result.mode.name}, '
      'sessions=${result.sessions.length}, '
      'hasConfig=${result.config != null}',
      name: 'Import',
    );

    if (result.mode == ImportMode.replace) {
      final existing = getSessions();
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
        if (result.mode == ImportMode.replace) rethrow;
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
}
