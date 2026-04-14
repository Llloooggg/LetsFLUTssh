import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/openssh_config_importer.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/ssh_config_import_preview_dialog.dart';

void main() {
  OpenSshConfigImportPreview makePreview({
    int hosts = 2,
    List<String> missingKeys = const [],
    String folder = '~/.ssh 2026-04-15',
  }) {
    final sessions = List.generate(
      hosts,
      (i) => Session(
        label: 'h$i',
        folder: folder,
        server: ServerAddress(host: 'h$i.example.com', user: 'u'),
      ),
    );
    return OpenSshConfigImportPreview(
      result: ImportResult(sessions: sessions, mode: ImportMode.merge),
      parsedHosts: hosts,
      hostsWithMissingKeys: missingKeys,
    );
  }

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: AppTheme.dark(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  group('SshConfigImportPreviewDialog', () {
    testWidgets('shows host count and allows import when hosts present', (
      tester,
    ) async {
      final preview = makePreview(hosts: 3);
      await tester.pumpWidget(
        wrap(
          SshConfigImportPreviewDialog(
            preview: preview,
            folderLabel: '~/.ssh 2026-04-15',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('3'), findsWidgets);
      expect(find.textContaining('h0'), findsOneWidget);
    });

    testWidgets('shows empty state when no hosts', (tester) async {
      final preview = makePreview(hosts: 0);
      await tester.pumpWidget(
        wrap(
          SshConfigImportPreviewDialog(preview: preview, folderLabel: 'unused'),
        ),
      );
      await tester.pump();

      expect(
        find.text('No importable hosts found in this file.'),
        findsOneWidget,
      );
    });

    testWidgets('shows missing-key warning when applicable', (tester) async {
      final preview = makePreview(hosts: 2, missingKeys: ['bastion']);
      await tester.pumpWidget(
        wrap(
          SshConfigImportPreviewDialog(
            preview: preview,
            folderLabel: '~/.ssh 2026-04-15',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('bastion'), findsOneWidget);
    });
  });
}
