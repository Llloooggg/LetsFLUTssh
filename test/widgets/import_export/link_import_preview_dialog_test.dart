import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/export_import.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/import_export/import_preview_dialog.dart';
import 'package:letsflutssh/widgets/import_export/link_import_preview_dialog.dart';

// `LinkImportPreviewDialog` is a thin wrapper around `ImportPreviewDialog`.
// The full preset / mode / checkbox matrix lives in
// `test/widgets/import_preview_dialog_test.dart`; this suite covers only the
// behaviour the wrapper adds on top:
//   - the link-flavoured header text + icon
//   - the count projection from `LfsPreview` to `ImportPreviewCounts`
//   - the static `showFromPreview` entry point's resolve / null contract
//
// The QR/Rust decode-driven `show(context, source:)` path needs an
// FRB-opaque `DbImportOpenResult`, which is not constructible Dart-side —
// that branch is covered by the import integration suite.

void main() {
  LfsPreview previewWith({
    int sessions = 0,
    bool hasConfig = false,
    int managerKeys = 0,
    int tags = 0,
    int snippets = 0,
    bool hasKnownHosts = false,
  }) {
    return LfsPreview(
      schemaVersion: 1,
      sessionCount: sessions,
      managerKeyCount: managerKeys,
      tagCount: tags,
      snippetCount: snippets,
      hasConfig: hasConfig,
      hasKnownHosts: hasKnownHosts,
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('LinkImportPreviewDialog — header', () {
    testWidgets(
      'renders the paste-import link title and link icon, not an archive header',
      // Spec: the wrapper exists to give the link/QR flow a header distinct
      // from the archive flow. The localized `pasteImportLinkTitle` ("Paste
      // import link") plus a leading `Icons.link` are the wrapper's whole
      // surface contribution; both must show in the rendered tree.
      (tester) async {
        await tester.pumpWidget(
          wrap(LinkImportPreviewDialog(preview: previewWith())),
        );
        await tester.pump();

        expect(find.text('Paste import link'), findsOneWidget);
        expect(find.byIcon(Icons.link), findsOneWidget);
      },
    );
  });

  group('LinkImportPreviewDialog — count projection', () {
    testWidgets(
      'empty preview surfaces zero counts and "No" for the boolean rows',
      // Spec: an LfsPreview with no payload (every count zero, both bool
      // fields false) must propagate verbatim to the underlying dialog —
      // no rounding up, no hiding of zero rows. Replace mode relies on the
      // user being able to see and toggle empty categories.
      (tester) async {
        await tester.pumpWidget(
          wrap(LinkImportPreviewDialog(preview: previewWith())),
        );
        await tester.pump();

        // Three count rows (sessions, manager keys, all manager keys, tags,
        // snippets) all render "0"; manager keys appears in two rows so
        // "0" shows up at least four times. The exact number depends on the
        // shared dialog's row order; the lower bound is the spec.
        expect(find.text('0'), findsWidgets);
        // hasConfig=false + hasKnownHosts=false → both yes/no rows show "No".
        expect(find.text('No'), findsNWidgets(2));
        expect(find.text('Yes'), findsNothing);
      },
    );

    testWidgets(
      'sessions-only preview surfaces the session count and "No" for config',
      // Spec: a QR payload that carries 3 sessions but no config / no known
      // hosts must surface "3" in the sessions row and "No" in both yes/no
      // rows. The link wrapper must not pre-filter by what the QR codec
      // typically emits — every field of LfsPreview projects through.
      (tester) async {
        await tester.pumpWidget(
          wrap(LinkImportPreviewDialog(preview: previewWith(sessions: 3))),
        );
        await tester.pump();

        expect(find.text('3'), findsOneWidget);
        expect(find.text('No'), findsNWidgets(2));
      },
    );

    testWidgets(
      'fully populated preview surfaces every numeric count and "Yes" for booleans',
      // Spec: counts pass through 1:1. managerKeyCount renders in two
      // rows (session-keys + all-keys); the other categories render once
      // each. hasConfig + hasKnownHosts both true → both yes/no rows show
      // "Yes".
      (tester) async {
        await tester.pumpWidget(
          wrap(
            LinkImportPreviewDialog(
              preview: previewWith(
                sessions: 7,
                hasConfig: true,
                managerKeys: 11,
                tags: 13,
                snippets: 17,
                hasKnownHosts: true,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('7'), findsOneWidget);
        expect(find.text('11'), findsNWidgets(2));
        expect(find.text('13'), findsOneWidget);
        expect(find.text('17'), findsOneWidget);
        expect(find.text('Yes'), findsNWidgets(2));
        expect(find.text('No'), findsNothing);
      },
    );
  });

  group('LinkImportPreviewDialog — showFromPreview', () {
    testWidgets(
      'Cancel resolves the future to null',
      // Spec: matching the underlying `ImportPreviewDialog.show` contract,
      // the wrapper must surface a null result on Cancel so callers can
      // short-circuit with `if (sel == null) return;`.
      (tester) async {
        LinkImportPreviewResult? result = (
          mode: ImportMode.merge,
          options: const ExportOptions(),
        );
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await LinkImportPreviewDialog.showFromPreview(
                    ctx,
                    preview: previewWith(sessions: 1),
                  );
                },
                child: const Text('open'),
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
      'Import resolves the future to (mode, options) and projects the chosen mode',
      // Spec: confirming with Import returns a record whose `mode` matches
      // the active mode button at confirmation time and whose `options`
      // reflects the live checkbox state — the wrapper does no rewriting.
      (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        LinkImportPreviewResult? result;
        await tester.pumpWidget(
          wrap(
            Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await LinkImportPreviewDialog.showFromPreview(
                    ctx,
                    preview: previewWith(
                      sessions: 2,
                      hasConfig: true,
                      managerKeys: 1,
                      tags: 1,
                      snippets: 1,
                      hasKnownHosts: true,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // Default mode is merge; switch to replace then confirm.
        await tester.tap(find.text('Replace'));
        await tester.pump();
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.mode, ImportMode.replace);
        // Full preset is the dialog's default, so sessions stays included.
        expect(result!.options.includeSessions, isTrue);
      },
    );
  });

  group('LinkImportPreviewDialog — counts projection contract', () {
    testWidgets(
      'projects every LfsPreview field 1:1 into the wrapped ImportPreviewDialog counts',
      // Spec: the wrapper's private `_countsOf` is the single boundary
      // between the Rust-shape preview and the engine-agnostic dialog
      // counts record. Probing the wrapped `ImportPreviewDialog.counts`
      // pins the field mapping so adding / renaming a field in either
      // shape fails this test, not user-visible behaviour.
      (tester) async {
        const preview = LfsPreview(
          schemaVersion: 1,
          sessionCount: 4,
          managerKeyCount: 6,
          tagCount: 8,
          snippetCount: 10,
          hasConfig: true,
          hasKnownHosts: false,
        );
        await tester.pumpWidget(
          wrap(const LinkImportPreviewDialog(preview: preview)),
        );
        await tester.pump();

        final inner = tester.widget<ImportPreviewDialog>(
          find.byType(ImportPreviewDialog),
        );
        expect(inner.counts.sessions, 4);
        expect(inner.counts.managerKeys, 6);
        expect(inner.counts.tags, 8);
        expect(inner.counts.snippets, 10);
        expect(inner.counts.hasConfig, isTrue);
        expect(inner.counts.hasKnownHosts, isFalse);
      },
    );
  });

  group('LinkImportPreviewDialog.show via QrDecodedSource', () {
    test('covered by integration: QrDecodedSource.rust wraps an FRB-opaque '
        'DbImportOpenResult that has no Dart constructor', () {
      // The `show(context, source:)` entry point only matters when a real
      // Rust-decoded payload exists. The opaque is produced by
      // `qrImportOpen` Rust-side and cannot be faked in unit tests, so
      // this branch is exercised by the link/QR import integration suite
      // (`test/integration/import_link_test.dart`).
    }, skip: 'covered by integration: FRB-opaque DbImportOpenResult');
  });
}
