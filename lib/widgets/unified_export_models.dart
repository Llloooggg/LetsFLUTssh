import '../core/config/app_config.dart';
import '../core/session/qr_codec.dart';
import '../core/session/session.dart';
import '../core/snippets/snippet.dart';
import '../core/tags/tag.dart';

/// Bundle of data the unified export dialog displays. Groups related
/// optional parameters so the dialog's `show()` stays small. Lives
/// in this dedicated file (not next to the dialog widget) because
/// the controller and the dialog both need the type — putting it in
/// either of those would create an import cycle. Pure data, no
/// Flutter / framework dependency beyond the model imports.
class UnifiedExportDialogData {
  final List<Session> sessions;
  final Set<String> emptyFolders;
  final AppConfig? config;
  final String? knownHostsContent;

  /// All tags for size calculation and export.
  final List<Tag> tags;

  /// All snippets for size calculation and export.
  final List<Snippet> snippets;

  const UnifiedExportDialogData({
    required this.sessions,
    required this.emptyFolders,
    this.config,
    this.knownHostsContent,
    this.tags = const [],
    this.snippets = const [],
  });
}

/// Result returned by the unified export dialog when the user
/// confirms — the chosen export options plus the resolved session +
/// empty-folder selection.
class UnifiedExportResult {
  final ExportOptions options;
  final List<Session> selectedSessions;
  final Set<String> selectedEmptyFolders;

  const UnifiedExportResult({
    required this.options,
    required this.selectedSessions,
    required this.selectedEmptyFolders,
  });
}
