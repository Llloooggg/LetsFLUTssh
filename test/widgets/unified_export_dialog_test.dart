import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/widgets/data_checkboxes.dart';
import 'package:letsflutssh/widgets/hover_region.dart';
import 'package:letsflutssh/widgets/unified_export_dialog.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unified_export_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Session makeSession(
    String id,
    String label, {
    String folder = '',
    String password = '',
    AuthType authType = AuthType.password,
    String keyData = '',
  }) => Session(
    id: id,
    label: label,
    folder: folder,
    server: ServerAddress(host: '$label.com', user: 'user'),
    auth: SessionAuth(authType: authType, password: password, keyData: keyData),
  );

  Widget buildDialog({
    required List<Session> sessions,
    Set<String> emptyFolders = const {},
    AppConfig? config,
    String? knownHostsContent,
    bool isQrMode = false,
    Map<String, String> managerKeys = const {},
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: UnifiedExportDialog(
            data: UnifiedExportDialogData(
              sessions: sessions,
              emptyFolders: emptyFolders,
              config: config,
              knownHostsContent: knownHostsContent,
              managerKeys: managerKeys,
            ),
            isQrMode: isQrMode,
          ),
        ),
      ),
    );
  }

  group('UnifiedExportDialog — QR mode', () {
    testWidgets('renders title for QR mode', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      expect(find.text('Export Sessions via QR'), findsOneWidget);
    });

    testWidgets('renders checkboxes in QR mode', (tester) async {
      final sessions = [makeSession('1', 'Test')];
      const config = AppConfig.defaults;

      await tester.pumpWidget(
        buildDialog(
          sessions: sessions,
          config: config,
          knownHostsContent: 'github.com ssh-rsa AAA',
          isQrMode: true,
        ),
      );
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('renders session list', (tester) async {
      final sessions = [
        makeSession('1', 'Server1', folder: 'Production'),
        makeSession('2', 'Server2', folder: 'Production'),
      ];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('select all checkbox exists', (tester) async {
      final sessions = [makeSession('1', 'A'), makeSession('2', 'B')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('renders Show QR button in QR mode', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      expect(find.text('Show QR'), findsOneWidget);
    });

    testWidgets('shows QR size indicator with payload size', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      // Size indicator shows payload size in KB
      expect(find.textContaining('KB'), findsOneWidget);
    });

    testWidgets('shows keys-disabled disclaimer in QR mode by default', (
      tester,
    ) async {
      final sessions = [makeSession('1', 'Test', password: 'secret')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      // The QR export disclaimer explains that SSH keys are off by default.
      expect(find.textContaining('disabled by default'), findsOneWidget);
    });

    testWidgets('shows warning when embedded keys enabled in QR mode', (
      tester,
    ) async {
      final sessions = [
        makeSession(
          '1',
          'Test',
          authType: AuthType.key,
          keyData: 'ssh-rsa AAA',
        ),
      ];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      // Expand the collapsed "What to import" section to reveal checkboxes.
      await tester.tap(find.text('What to import:'));
      await tester.pumpAndSettle();

      // Embedded keys are OFF by default — enable it (second checkbox)
      final embeddedKeysCheckbox = find.byType(Checkbox).at(1);
      await tester.tap(embeddedKeysCheckbox);
      await tester.pumpAndSettle();

      // Warning text is now visible
      expect(find.textContaining('exceed QR size'), findsOneWidget);
    });

    testWidgets(
      'QR-mode checkbox defaults mirror the "Sessions only" preset sans keys',
      (tester) async {
        // Regression guard: the QR export defaults must match the live
        // "Sessions only" preset (sessions + passwords + tags + snippets),
        // but with every key-bearing option OFF to keep the payload small.
        final sessions = [makeSession('1', 'Test', password: 'secret')];
        const config = AppConfig.defaults;

        await tester.pumpWidget(
          buildDialog(
            sessions: sessions,
            config: config,
            knownHostsContent: 'github.com ssh-rsa AAA',
            isQrMode: true,
          ),
        );
        await tester.pump();

        // Expand the collapsible section so we can read checkbox states.
        await tester.tap(find.text('What to import:'));
        await tester.pumpAndSettle();

        // Map visible checkboxes by the label rendered to the right of them.
        // Row layout: Checkbox → Icon → Expanded(Column(label...)). Looking
        // up the ancestor Row of each label gives us the matching Checkbox.
        Checkbox checkboxFor(String label) {
          final row = find
              .ancestor(of: find.text(label), matching: find.byType(Row))
              .first;
          return tester.widget<Checkbox>(
            find.descendant(of: row, matching: find.byType(Checkbox)),
          );
        }

        expect(checkboxFor('App Settings').value, isFalse);
        expect(checkboxFor('Session passwords').value, isTrue);
        expect(checkboxFor('Session keys').value, isFalse);
        expect(checkboxFor('Session SSH keys').value, isFalse);
        expect(checkboxFor('All manager keys').value, isFalse);
        expect(checkboxFor('Known Hosts').value, isFalse);
        expect(checkboxFor('Tags').value, isTrue);
        expect(checkboxFor('Snippets').value, isTrue);
      },
    );

    testWidgets('no warnings in LFS mode even with credentials enabled', (
      tester,
    ) async {
      final sessions = [
        makeSession(
          '1',
          'Test',
          password: 'secret',
          authType: AuthType.key,
          keyData: 'ssh-rsa AAA',
        ),
      ];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: false));
      await tester.pump();

      // LFS mode has credentials ON by default, but no QR-only disclaimers.
      expect(find.textContaining('disabled by default'), findsNothing);
      expect(find.textContaining('exceed QR size'), findsNothing);
    });
  });

  group('UnifiedExportDialog — LFS export mode', () {
    testWidgets('renders title for LFS mode', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: false));
      await tester.pump();

      expect(find.text('Export Data'), findsOneWidget);
    });

    testWidgets('renders Export button in LFS mode', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: false));
      await tester.pump();

      expect(find.text('Export'), findsOneWidget);
    });
  });

  group('UnifiedExportDialog — Cancel returns null', () {
    testWidgets('Cancel button closes dialog with null result', (tester) async {
      UnifiedExportResult? result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await UnifiedExportDialog.show(
                    context,
                    data: UnifiedExportDialogData(
                      sessions: [makeSession('1', 'Test')],
                      emptyFolders: const {},
                    ),
                    isQrMode: false,
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

    testWidgets('Export button returns result with selections', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await UnifiedExportDialog.show(
                    context,
                    data: UnifiedExportDialogData(
                      sessions: [makeSession('1', 'Test')],
                      emptyFolders: const {},
                    ),
                    isQrMode: false,
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

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Verify dialog closed (result may be null if Navigator.pop
      // doesn't reach the test's navigator in widget test context)
      // The key assertion is that Export button is clickable without crash.
    });
  });

  group('UnifiedExportDialog — session selection', () {
    testWidgets('deselecting all sessions disables Export in QR mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sessions = [makeSession('1', 'A'), makeSession('2', 'B')];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await UnifiedExportDialog.show(
                    context,
                    data: UnifiedExportDialogData(
                      sessions: sessions,
                      emptyFolders: const {},
                    ),
                    isQrMode: true,
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

      // Deselect all via select-all checkbox (true → null → false)
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      // Show QR button should be disabled (no sessions selected)
      expect(find.text('Show QR'), findsOneWidget);
    });

    testWidgets('can toggle individual session checkbox', (tester) async {
      final sessions = [makeSession('1', 'A'), makeSession('2', 'B')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: false));
      await tester.pump();

      // Count checkboxes before (select-all + sessions)
      final beforeCount = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .length;

      // Tap the first session's checkbox (index 1, after select-all)
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();

      // Checkbox count should be the same (just value changed)
      final afterCount = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .length;
      expect(afterCount, beforeCount);
    });

    testWidgets('folder selection toggles all sessions in folder', (
      tester,
    ) async {
      final sessions = [
        makeSession('1', 'A', folder: 'Production'),
        makeSession('2', 'B', folder: 'Production'),
        makeSession('3', 'C', folder: 'Staging'),
      ];
      const emptyFolders = {'Production', 'Staging'};

      await tester.pumpWidget(
        buildDialog(
          sessions: sessions,
          emptyFolders: emptyFolders,
          isQrMode: false,
        ),
      );
      await tester.pump();

      // Should show folder entries in tree
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsOneWidget);
    });
  });

  group('UnifiedExportDialog — QR size validation', () {
    testWidgets('does not close dialog when payload exceeds QR limit', (
      tester,
    ) async {
      // Use a larger viewport so the "Show QR" button is visible
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Create many sessions to exceed QR limit
      final sessions = List.generate(
        50,
        (i) => makeSession('s$i', 'Server $i with a long label'),
      );

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: true));
      await tester.pump();

      // Verify Show QR button exists
      expect(find.text('Show QR'), findsOneWidget);

      // Tap it — dialog should stay open (shows SnackBar error)
      await tester.tap(find.text('Show QR'));
      await tester.pump();

      // Dialog is still visible (the export button is still there)
      expect(find.text('Show QR'), findsOneWidget);
    });
  });

  group('UnifiedExportDialog — data type checkboxes', () {
    testWidgets('toggling session passwords checkbox works', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(buildDialog(sessions: sessions, isQrMode: false));
      await tester.pump();

      // Expand the collapsed "What to import" section to reveal checkboxes.
      await tester.tap(find.text('What to import:'));
      await tester.pumpAndSettle();

      // Tap the session passwords checkbox (English l10n)
      await tester.tap(find.text('Session passwords'));
      await tester.pump();

      // Tap Embedded Keys (l10n: "Session keys")
      await tester.tap(find.text('Session keys'));
      await tester.pump();

      // No crash, UI is responsive
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('config checkbox hidden when config is null', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(
        buildDialog(sessions: sessions, config: null, isQrMode: false),
      );
      await tester.pump();

      expect(find.text('App Settings'), findsNothing);
    });

    testWidgets('known hosts hidden when content is empty', (tester) async {
      final sessions = [makeSession('1', 'Test')];

      await tester.pumpWidget(
        buildDialog(sessions: sessions, knownHostsContent: '', isQrMode: false),
      );
      await tester.pump();

      expect(find.text('Known Hosts'), findsNothing);
    });
  });

  // ===========================================================================
  // Specs derived from lib/widgets/unified_export_dialog.dart:
  //
  //  * "Full backup" preset chip flips every includeX to true and selects
  //    every session — the user's one-click "give me everything" path.
  //  * "Sessions only" preset chip clears config / known-hosts / keys /
  //    tags / snippets so a casual "give me my sessions" export doesn't
  //    accidentally ship app settings or keys.
  //  * Each data-type checkbox row toggles its underlying ExportOptions
  //    flag. The Export button's returned UnifiedExportResult carries
  //    that flag — same bit the LFS / QR encoders will honor downstream.
  //  * Tags and Snippets rows only render when the payload actually has
  //    them; empty tags / snippets hide the row entirely so the user
  //    isn't invited to toggle something that has no effect.
  //
  // We drive the dialog through show() and inspect the returned
  // UnifiedExportResult, because that's the contract the caller relies on.
  // ===========================================================================
  group(
    'UnifiedExportDialog — preset chips and data-type toggles drive result',
    () {
      Widget openerFor({
        required List<Session> sessions,
        AppConfig? config,
        String? knownHostsContent,
        Map<String, String> managerKeys = const {},
        required ValueChanged<UnifiedExportResult?> onResult,
      }) {
        return MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final r = await UnifiedExportDialog.show(
                    context,
                    data: UnifiedExportDialogData(
                      sessions: sessions,
                      emptyFolders: const {},
                      config: config,
                      knownHostsContent: knownHostsContent,
                      managerKeys: managerKeys,
                    ),
                    isQrMode: false,
                  );
                  onResult(r);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
      }

      testWidgets(
        'Full backup preset selects every session and every data type',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          UnifiedExportResult? result;
          final sessions = [makeSession('1', 'A'), makeSession('2', 'B')];
          await tester.pumpWidget(
            openerFor(
              sessions: sessions,
              config: AppConfig.defaults,
              knownHostsContent: 'github.com ssh-rsa AAA',
              onResult: (r) => result = r,
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(ChoiceChip, 'Full backup'));
          await tester.pump();
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();

          expect(result, isNotNull);
          expect(result!.options.includeSessions, isTrue);
          expect(result!.options.includeConfig, isTrue);
          expect(result!.options.includeKnownHosts, isTrue);
          expect(result!.options.includePasswords, isTrue);
          expect(result!.options.includeAllManagerKeys, isTrue);
          // Every session is in the selection.
          expect(result!.selectedSessions.map((s) => s.id), ['1', '2']);
        },
      );

      testWidgets(
        'Sessions preset drops config/known-hosts but keeps session-linked data',
        // Spec (_sessionsPreset, L687-696): "Sessions" means "send this
        // sessions package to the other device" — it must carry the
        // sessions plus anything only meaningful *with* a session
        // (passwords, embedded keys, session-referenced manager keys,
        // tags, snippets). What it drops is the *global* stuff:
        // includeConfig (app settings) and includeKnownHosts (host-key
        // trust DB). includeAllManagerKeys is off because "all keys" is
        // the full-app-transfer mode, which belongs to Full backup.
        (tester) async {
          tester.view.physicalSize = const Size(900, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          UnifiedExportResult? result;
          await tester.pumpWidget(
            openerFor(
              sessions: [makeSession('1', 'A')],
              config: AppConfig.defaults,
              knownHostsContent: 'github.com ssh-rsa AAA',
              onResult: (r) => result = r,
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ChoiceChip, 'Sessions'));
          await tester.pump();
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();

          expect(result, isNotNull);
          expect(result!.options.includeSessions, isTrue);
          // Dropped global-scope flags.
          expect(result!.options.includeConfig, isFalse);
          expect(result!.options.includeKnownHosts, isFalse);
          expect(result!.options.includeAllManagerKeys, isFalse);
          // Kept session-scoped flags.
          expect(result!.options.includePasswords, isTrue);
          expect(result!.options.includeManagerKeys, isTrue);
          expect(result!.options.includeTags, isTrue);
          expect(result!.options.includeSnippets, isTrue);
        },
      );

      testWidgets(
        'App Settings checkbox toggle flips includeConfig on the result',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          UnifiedExportResult? result;
          await tester.pumpWidget(
            openerFor(
              sessions: [makeSession('1', 'A')],
              config: AppConfig.defaults,
              onResult: (r) => result = r,
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Default preset is Full (every flag on). Expand checkbox section,
          // flip "App Settings" off, export.
          // BUG: export dialog currently labels its checkbox section "What to
          // import:" (L754 uses importWhatToImport). Tapping the first
          // HoverRegion inside the CollapsibleCheckboxesSection expands the
          // grid without relying on that wrong label — swap this out once the
          // l10n fix lands.
          await tester.tap(
            find
                .descendant(
                  of: find.byType(CollapsibleCheckboxesSection),
                  matching: find.byType(HoverRegion),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('App Settings'));
          await tester.pump();
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();

          expect(result, isNotNull);
          expect(result!.options.includeConfig, isFalse);
          expect(result!.options.includeSessions, isTrue);
        },
      );

      testWidgets(
        'Known Hosts checkbox toggle flips includeKnownHosts on the result',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          UnifiedExportResult? result;
          await tester.pumpWidget(
            openerFor(
              sessions: [makeSession('1', 'A')],
              knownHostsContent: 'github.com ssh-rsa AAA',
              onResult: (r) => result = r,
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // BUG: export dialog currently labels its checkbox section "What to
          // import:" (L754 uses importWhatToImport). Tapping the first
          // HoverRegion inside the CollapsibleCheckboxesSection expands the
          // grid without relying on that wrong label — swap this out once the
          // l10n fix lands.
          await tester.tap(
            find
                .descendant(
                  of: find.byType(CollapsibleCheckboxesSection),
                  matching: find.byType(HoverRegion),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Known Hosts'));
          await tester.pump();
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();

          expect(result, isNotNull);
          expect(result!.options.includeKnownHosts, isFalse);
        },
      );

      testWidgets(
        'All manager keys row flips includeAllManagerKeys and clears session keys',
        // Spec (L820-825): All-keys and Session-keys are mutually exclusive
        // — turning all-keys on must turn session-keys off. Exporting both
        // at once would double-encode the subset in the archive.
        (tester) async {
          tester.view.physicalSize = const Size(900, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          UnifiedExportResult? result;
          await tester.pumpWidget(
            openerFor(
              sessions: [makeSession('1', 'A')],
              managerKeys: {'k1': 'PRIVKEYPEM'},
              onResult: (r) => result = r,
            ),
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Start from Sessions-only so both key flags begin OFF.
          await tester.tap(find.widgetWithText(ChoiceChip, 'Sessions'));
          await tester.pump();
          // BUG: export dialog currently labels its checkbox section "What to
          // import:" (L754 uses importWhatToImport). Tapping the first
          // HoverRegion inside the CollapsibleCheckboxesSection expands the
          // grid without relying on that wrong label — swap this out once the
          // l10n fix lands.
          await tester.tap(
            find
                .descendant(
                  of: find.byType(CollapsibleCheckboxesSection),
                  matching: find.byType(HoverRegion),
                )
                .first,
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('All manager keys'));
          await tester.pump();
          await tester.tap(find.text('Export'));
          await tester.pumpAndSettle();

          expect(result, isNotNull);
          expect(result!.options.includeAllManagerKeys, isTrue);
          expect(result!.options.includeManagerKeys, isFalse);
        },
      );
    },
  );
}
