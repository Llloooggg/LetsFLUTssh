import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/import_preview_dialog.dart';

void main() {
  // Default counts: every type present, non-zero sessions/keys/tags/snippets.
  const ImportPreviewCounts defaultCounts = (
    sessions: 2,
    hasConfig: true,
    managerKeys: 3,
    tags: 4,
    snippets: 5,
    hasKnownHosts: true,
  );

  Widget buildDialog({
    Widget header = const _StubHeader('STUB-HEADER'),
    ImportPreviewCounts counts = defaultCounts,
  }) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ImportPreviewDialog(header: header, counts: counts),
        ),
      ),
    );
  }

  group('ImportPreviewDialog', () {
    testWidgets(
      'renders the caller-supplied header verbatim',
      // Spec: the shared dialog doesn't know whether it's showing an archive
      // filename or a link title — it must pass the caller's header through
      // without modification so both sources can own their own visuals.
      (tester) async {
        await tester.pumpWidget(buildDialog());
        await tester.pump();

        expect(find.text('STUB-HEADER'), findsOneWidget);
      },
    );

    testWidgets(
      'trailing counts are read from the counts record, not from any payload',
      (tester) async {
        // Spec: the dialog is payload-agnostic. Whatever integers you feed in
        // are what show up on the right of each checkbox row — no "smart"
        // rewriting, no zero-hiding.
        await tester.pumpWidget(
          buildDialog(
            counts: const (
              sessions: 7,
              hasConfig: false,
              managerKeys: 11,
              tags: 13,
              snippets: 17,
              hasKnownHosts: false,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('7'), findsOneWidget); // sessions
        expect(find.text('13'), findsOneWidget); // tags
        expect(find.text('17'), findsOneWidget); // snippets
        // managerKeys count 11 is rendered twice (session-keys + all-keys rows).
        expect(find.text('11'), findsNWidgets(2));
        // hasConfig=false + hasKnownHosts=false → both yes/no rows show "No".
        expect(find.text('No'), findsNWidgets(2));
        expect(find.text('Yes'), findsNothing);
      },
    );

    testWidgets(
      'tapping Selective preset flips the trailing preset label',
      // Spec: Full and Selective preset chips drive the checkbox state, and
      // the collapsible section header surfaces the active preset name so a
      // user who collapsed the grid still sees which preset is in effect.
      (tester) async {
        await tester.pumpWidget(buildDialog());
        await tester.pump();

        // Default preset is Full — label appears twice (chip + section header).
        expect(find.text('Full import'), findsNWidgets(2));

        await tester.tap(find.text('Selective'));
        await tester.pump();

        // After switching: Selective appears twice (chip + section header),
        // Full import only once (just the chip).
        expect(find.text('Selective'), findsNWidgets(2));
        expect(find.text('Full import'), findsOneWidget);
      },
    );

    testWidgets(
      'Import button disabled only when every standalone entity is off',
      // Spec from qr_codec.ExportOptions.hasAnySelection: a selection is
      // "empty" iff none of the standalone entities (sessions, config,
      // known_hosts, all-manager-keys, tags, snippets) is selected. As long
      // as any one of them is ticked, Import stays enabled — e.g. a
      // tags-only or manager-keys-only import is a valid operation.
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        ImportPreviewSelection? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await ImportPreviewDialog.show(
                      ctx,
                      header: const _StubHeader('H'),
                      counts: defaultCounts,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Default preset is Full → every standalone flag is ON. Toggle each
        // off in turn. After the last tap, hasAnySelection flips to false
        // and Import becomes disabled.
        for (final label in const [
          'Sessions',
          'App Settings',
          'All manager keys',
          'Tags',
          'Snippets',
          'Known Hosts',
        ]) {
          await tester.tap(find.text(label));
          await tester.pump();
        }

        // Import should now be disabled → tapping does nothing, dialog stays
        // and show() has not resolved.
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.text('Import Data'), findsOneWidget);
      },
    );

    testWidgets(
      'Import stays enabled with only Tags selected (standalone entity)',
      // Spec: tags is a standalone entity per hasAnySelection — a
      // tags-only import must succeed. Regression guard against the old
      // gate that required sessions/config/known_hosts.
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        ImportPreviewSelection? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await ImportPreviewDialog.show(
                      ctx,
                      header: const _StubHeader('H'),
                      counts: defaultCounts,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // From Full preset, uncheck every row except Tags.
        for (final label in const [
          'Sessions',
          'App Settings',
          'All manager keys',
          'Snippets',
          'Known Hosts',
        ]) {
          await tester.tap(find.text(label));
          await tester.pump();
        }

        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.options.includeTags, isTrue);
        expect(result!.options.includeSessions, isFalse);
        expect(result!.options.includeConfig, isFalse);
        expect(result!.options.includeKnownHosts, isFalse);
      },
    );

    testWidgets(
      'Cancel returns null from show()',
      // Spec: show() resolves to null when the user cancels so callers can
      // cleanly short-circuit with `if (sel == null) return;`.
      (tester) async {
        ImportPreviewSelection? result = (
          mode: ImportMode.merge,
          options: const ExportOptions(),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await ImportPreviewDialog.show(
                      ctx,
                      header: const _StubHeader('H'),
                      counts: defaultCounts,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(result, isNull);
      },
    );

    testWidgets(
      'Import returns (mode, options) with Replace after user switches mode',
      // Spec: show() resolves with whatever mode + options the user picked
      // at confirmation time — not the initial defaults.
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        ImportPreviewSelection? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await ImportPreviewDialog.show(
                      ctx,
                      header: const _StubHeader('H'),
                      counts: defaultCounts,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace'));
        await tester.pump();
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.mode, ImportMode.replace);
        expect(result!.options.includeSessions, isTrue);
      },
    );

    testWidgets(
      'toggling session-keys clears all-keys and vice versa',
      // Spec: "Session keys" and "All keys" are mutually exclusive — turning
      // one on turns the other off. Picking "all keys" in Selective mode
      // must not leave both flags true at once, because the importer would
      // otherwise double-insert the manager key set.
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        ImportPreviewSelection? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await ImportPreviewDialog.show(
                      ctx,
                      header: const _StubHeader('H'),
                      counts: defaultCounts,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Default: Full preset → includeAllManagerKeys true, includeManagerKeys
        // false. Tap "Session keys" to flip to session-only mode.
        await tester.tap(find.text('Session keys (manager)'));
        await tester.pump();
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.options.includeManagerKeys, isTrue);
        expect(result!.options.includeAllManagerKeys, isFalse);
      },
    );

    testWidgets('preset ChoiceChips hide the default checkmark overlay so the '
        'avatar icon stays visible when selected', (tester) async {
      await tester.pumpWidget(buildDialog());
      await tester.pump();
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips, isNotEmpty);
      for (final chip in chips) {
        expect(
          chip.showCheckmark,
          isFalse,
          reason:
              'checkmark overlay must be disabled — the avatar icon is the '
              'only indicator, selection is signalled by background colour',
        );
      }
    });
  });
}

class _StubHeader extends StatelessWidget {
  final String marker;
  const _StubHeader(this.marker);

  @override
  Widget build(BuildContext context) => Text(marker);
}
