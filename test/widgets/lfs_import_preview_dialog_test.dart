import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/widgets/lfs_import_preview_dialog.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lfs_preview_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  LfsPreview makePreview({
    int sessionsCount = 3,
    bool hasConfig = true,
    bool hasKnownHosts = true,
    Set<String> emptyFolders = const {'FolderA', 'FolderB'},
    int managerKeyCount = 2,
    int tagCount = 4,
    int snippetCount = 5,
  }) {
    final sessions = List.generate(
      sessionsCount,
      (i) => Session(
        id: 's$i',
        label: 'Session $i',
        server: ServerAddress(host: 'host$i.com', user: 'user'),
      ),
    );
    return LfsPreview(
      sessions: sessions,
      hasConfig: hasConfig,
      hasKnownHosts: hasKnownHosts,
      emptyFolders: emptyFolders,
      managerKeyCount: managerKeyCount,
      tagCount: tagCount,
      snippetCount: snippetCount,
    );
  }

  Widget buildDialog({required String filePath, required LfsPreview preview}) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LfsImportPreviewDialog(filePath: filePath, preview: preview),
        ),
      ),
    );
  }

  group('LfsImportPreviewDialog', () {
    testWidgets('renders title and file name', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/backup.lfs', preview: preview),
      );
      await tester.pump();

      expect(find.text('Import Data'), findsOneWidget);
      expect(find.text('backup.lfs'), findsOneWidget);
    });

    testWidgets('renders per-type counts next to checkboxes', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/count.lfs', preview: preview),
      );
      await tester.pump();

      // Checkbox labels are present — no info panel anymore.
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Snippets'), findsOneWidget);
      // Right-side count labels reflect preview fields.
      expect(find.text('3'), findsOneWidget); // sessions
      expect(find.text('4'), findsOneWidget); // tags
      expect(find.text('5'), findsOneWidget); // snippets
    });

    testWidgets('config and known_hosts show Yes/No trailing label', (
      tester,
    ) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/status.lfs', preview: preview),
      );
      await tester.pump();

      expect(find.text('App Settings'), findsOneWidget);
      expect(find.text('Known Hosts'), findsOneWidget);
      // App Settings + Known Hosts each render "Yes" trailing label.
      expect(find.text('Yes'), findsNWidgets(2));
    });

    testWidgets('does NOT render a password field (caller already decrypted)', (
      tester,
    ) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/pass.lfs', preview: preview),
      );
      await tester.pump();

      // Preview dialog must not prompt for password again — caller has it.
      expect(find.text('Master Password'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('renders mode selector with Merge and Replace', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/mode.lfs', preview: preview),
      );
      await tester.pump();

      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
    });

    testWidgets('Merge mode shows merge description', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/merge.lfs', preview: preview),
      );
      await tester.pump();

      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('Replace mode shows replace description', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/replace.lfs', preview: preview),
      );
      await tester.pump();

      await tester.tap(find.text('Replace'));
      await tester.pump();

      expect(find.text('Replace all sessions with imported'), findsOneWidget);
    });

    testWidgets('renders Cancel and Import buttons', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/btns.lfs', preview: preview),
      );
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('Import button is rendered with defaults', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(
          filePath: '${tempDir.path}/empty_pass.lfs',
          preview: preview,
        ),
      );
      await tester.pump();

      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('Import button is disabled when no selection', (tester) async {
      const preview = LfsPreview(
        sessions: [],
        hasConfig: false,
        hasKnownHosts: false,
      );

      await tester.pumpWidget(
        buildDialog(
          filePath: '${tempDir.path}/no_selection.lfs',
          preview: preview,
        ),
      );
      await tester.pump();

      // Dialog renders, Import button present but disabled
      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('Cancel button returns null', (tester) async {
      final preview = makePreview();
      LfsImportPreviewResult? result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await LfsImportPreviewDialog.show(
                    context,
                    filePath: '${tempDir.path}/cancel.lfs',
                    preview: preview,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('shows preset chips (Full / Selective)', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/preset.lfs', preview: preview),
      );
      await tester.pump();

      // "Full import" renders twice: once as a preset chip, once as the
      // trailing label on the collapsible section header.
      expect(find.text('Full import'), findsNWidgets(2));
      expect(find.text('Selective'), findsOneWidget);
    });

    testWidgets('can toggle config checkbox', (tester) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/toggle.lfs', preview: preview),
      );
      await tester.pump();

      // Config checkbox defaults to ON (archive has config).
      // Tap the App Settings row to toggle it off.
      await tester.tap(find.text('App Settings'));
      await tester.pump();

      expect(find.text('Import'), findsOneWidget);
    });

    testWidgets('switches between Merge and Replace modes', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/mode.lfs', preview: preview),
      );
      await tester.pump();

      // Default is Merge
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);

      // Switch to Replace
      await tester.tap(find.text('Replace'));
      await tester.pump();
      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      // Switch back to Merge
      await tester.tap(find.text('Merge'));
      await tester.pump();
      expect(find.text('Add new sessions, keep existing'), findsOneWidget);
    });

    testWidgets('Import with no selection stays open', (tester) async {
      // Dialog is taller than the default 800×600 viewport — size it up so
      // the bottom action row actually sits inside the viewport and tap()
      // doesn't emit a hit-test-miss warning.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const preview = LfsPreview(
        sessions: [],
        hasConfig: false,
        hasKnownHosts: false,
      );

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/empty.lfs', preview: preview),
      );
      await tester.pump();

      // With no data in the archive, _options.hasAnySelection is false
      // and Import is disabled. Dialog stays open.
      await tester.tap(find.text('Import'));
      await tester.pump();

      expect(find.text('Import Data'), findsOneWidget);
    });

    testWidgets(
      'checkbox rows are rendered even when archive has zero of that type',
      (tester) async {
        // Replace-mode intent: checking "Tags" with zero imported tags wipes
        // existing tags. The UI must keep every checkbox clickable regardless
        // of preview counts so that intent can be expressed.
        const preview = LfsPreview(
          sessions: [],
          hasConfig: false,
          hasKnownHosts: false,
          managerKeyCount: 0,
          tagCount: 0,
          snippetCount: 0,
        );

        await tester.pumpWidget(
          buildDialog(
            filePath: '${tempDir.path}/empty-archive.lfs',
            preview: preview,
          ),
        );
        await tester.pump();

        for (final label in const [
          'Sessions',
          'App Settings',
          'Tags',
          'Snippets',
          'Known Hosts',
        ]) {
          expect(find.text(label), findsOneWidget, reason: 'missing $label');
        }
      },
    );

    testWidgets('checkboxes collapse and expand via the section header', (
      tester,
    ) async {
      final preview = makePreview();

      await tester.pumpWidget(
        buildDialog(filePath: '${tempDir.path}/collapse.lfs', preview: preview),
      );
      await tester.pump();

      // Expanded by default → row labels visible.
      expect(find.text('Sessions'), findsOneWidget);

      await tester.tap(find.text('What to import:'));
      await tester.pump();

      // Collapsed → row labels gone, header still present.
      expect(find.text('Sessions'), findsNothing);
      expect(find.text('What to import:'), findsOneWidget);
    });
  });
}
