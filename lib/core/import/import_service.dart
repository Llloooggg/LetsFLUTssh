import 'package:flutter/foundation.dart';
import '../session/session.dart';
import '../../features/settings/export_import.dart';

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
    if (result.mode == ImportMode.replace) {
      final existing = getSessions();
      for (final s in existing) {
        await deleteSession(s.id);
      }
    }

    for (final s in result.sessions) {
      try {
        await addSession(s);
      } catch (e) {
        if (result.mode == ImportMode.replace) rethrow;
        debugPrint('Import: skipped session ${s.label}: $e');
      }
    }

    if (result.config != null) {
      applyConfig(result.config!);
    }
  }
}
