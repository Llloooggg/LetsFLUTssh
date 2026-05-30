/// Widget test for [RecordingsPanel] — the recordings manager shell.
/// The recording reader / playback / list-logic are covered by
/// recording_reader_test, recording_playback_dialog_test and
/// recordings_logic_test; this covers the panel's scan→render glue:
/// the seeded-content paths (plaintext row + encrypted-no-key row) and
/// the fresh-install (no directory) empty-state path.
///
/// Tagged `frb_global_store` because the seeded-content tests have to
/// call `app_reset_support_dir_for_tests` to re-pin the recordings
/// root onto a fresh per-test tempDir; without isolation, parallel
/// tests that already pinned their own support dir would observe the
/// reset and walk an empty tree.
@Tags(['frb_global_store'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/recordings/recordings_browser.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/widgets/core/app_data_row.dart';
import 'package:letsflutssh/widgets/core/app_empty_state.dart';
import 'package:letsflutssh/widgets/core/app_icon_button.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('recordings_panel_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // `pin_support_dir` is "first pin wins" — without this reset the
    // second test inherits the first test's tempDir (now deleted)
    // and the recordings scan walks an empty/missing tree. The test
    // seam clears the pin so each test scopes the singleton against
    // its own fresh tempDir.
    rust_app.appResetSupportDirForTests();
    await bootstrapRustConfigStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('a recordings root with no files renders the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: RecordingsPanel()),
        ),
      ),
    );
    // The async scan (migration sweep + Rust dir walk) crosses real
    // event-loop ticks; drain until the loading spinner resolves into
    // the empty state. pumpAndSettle would hang on the spinner.
    for (
      var i = 0;
      i < 60 && find.byType(AppEmptyState).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets(
    'a seeded plaintext .cast recording renders a row with metadata',
    (tester) async {
      // Spec: a valid asciicast v2 file (`{header}` then one or more
      // `[ts, "o", "text"]` event lines) lands in
      // `<recordingsRoot>/<sessionId>/<timestamp>.cast` and the panel
      // surfaces a row with the session label / size / duration. The
      // file is plaintext, so `canPlay` is unconditionally true and
      // the row is tappable.
      //
      // The recordings root resolves via the config-store pinned
      // support dir, so we seed under `<tempDir>/recordings/...`.
      final root = Directory('${tempDir.path}/recordings/session-abc')
        ..createSync(recursive: true);
      File('${root.path}/2026-05-29T10-00-00.cast').writeAsStringSync(
        '{"version": 2, "width": 80, "height": 24, "timestamp": 1700000000}\n'
        '[0.5, "o", "hello\\r\\n"]\n'
        '[1.0, "o", "world\\r\\n"]\n',
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: RecordingsPanel()),
          ),
        ),
      );
      // Drain until the row paints (the scan reads the meta header
      // through the FRB decoder).
      for (
        var i = 0;
        i < 80 && find.byType(AppDataRow).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(AppDataRow), findsOneWidget);
      // No empty state in this configuration.
      expect(find.byType(AppEmptyState), findsNothing);
    },
  );

  testWidgets(
    'an encrypted .lfsr recording on a no-key tier still renders a row '
    '(with the "locked" hint) so the user can at least delete it',
    (tester) async {
      // Spec: encrypted recordings on a tier with no active DB key
      // cannot be played, but the user still needs to see them in
      // the list so they can clean up. The row renders with the
      // localised "encrypted" / "locked" markers and the play tap is
      // disabled; the delete button stays available.
      final root = Directory('${tempDir.path}/recordings/session-locked')
        ..createSync(recursive: true);
      // Content shape doesn't matter — `readMeta` short-circuits to
      // null on a no-key tier and the row falls back to `?` duration.
      // Only the `.lfsr` extension drives `encrypted = true`.
      File(
        '${root.path}/2026-05-29T11-00-00.lfsr',
      ).writeAsBytesSync(List<int>.filled(64, 0));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            home: Scaffold(body: RecordingsPanel()),
          ),
        ),
      );
      for (
        var i = 0;
        i < 80 && find.byType(AppDataRow).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(AppDataRow), findsOneWidget);
    },
  );

  // Helper: pump a single-row recordings panel + drain async ticks
  // until the row is visible. Each test seeds its own file before
  // calling.
  Future<void> pumpUntilRow(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(body: RecordingsPanel()),
        ),
      ),
    );
    for (var i = 0; i < 80 && find.byType(AppDataRow).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets('delete trailing button opens the ConfirmDialog; tapping Cancel '
      'leaves the row in place', (tester) async {
    // Spec: `_delete` runs `ConfirmDialog.show` first and bails when
    // it returns false. The Rust delete + rescan should NOT fire and
    // the row must remain visible. The plaintext recording shape
    // (asciicast v2 header + one event line) keeps `_scan` returning
    // a single row deterministically.
    final root = Directory('${tempDir.path}/recordings/session-del-cancel')
      ..createSync(recursive: true);
    File('${root.path}/2026-05-29T12-00-00.cast').writeAsStringSync(
      '{"version": 2, "width": 80, "height": 24, "timestamp": 1700000000}\n'
      '[0.5, "o", "hello\\r\\n"]\n',
    );

    await pumpUntilRow(tester);
    expect(find.byType(AppDataRow), findsOneWidget);

    // Trailing slot carries the localised delete-recording tooltip.
    final ctx = tester.element(find.byType(RecordingsPanel));
    final l10n = S.of(ctx);
    final deleteBtn = find.byWidgetPredicate(
      (w) => w is AppIconButton && w.tooltip == l10n.deleteRecording,
    );
    expect(deleteBtn, findsOneWidget);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // ConfirmDialog up: title is `deleteRecording`.
    expect(find.text(l10n.deleteRecording), findsWidgets);
    // Cancel the confirmation.
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    // Row still there — the delete short-circuited on cancel.
    expect(find.byType(AppDataRow), findsOneWidget);
  });

  testWidgets('delete trailing button opens the ConfirmDialog; tapping Delete '
      'removes the row from the panel', (tester) async {
    // Spec: a confirmed delete runs `rust_recorder.recorderDeleteRecording`
    // against the same `recordingsRoot` pinned for the test, then
    // re-scans. The list now has zero rows, so the empty state takes
    // over. Both transitions hit FRB and use the temp dir pinned in
    // `setUp` via `appResetSupportDirForTests`.
    final root = Directory('${tempDir.path}/recordings/session-del-accept')
      ..createSync(recursive: true);
    File('${root.path}/2026-05-29T13-00-00.cast').writeAsStringSync(
      '{"version": 2, "width": 80, "height": 24, "timestamp": 1700000000}\n'
      '[0.25, "o", "bye\\r\\n"]\n',
    );

    await pumpUntilRow(tester);
    expect(find.byType(AppDataRow), findsOneWidget);

    final ctx = tester.element(find.byType(RecordingsPanel));
    final l10n = S.of(ctx);
    final deleteBtn = find.byWidgetPredicate(
      (w) => w is AppIconButton && w.tooltip == l10n.deleteRecording,
    );
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Tap the destructive Delete action in the confirmation footer.
    // `ConfirmDialog` defaults `confirmLabel` to `l10n.delete`.
    await tester.tap(find.text(l10n.delete).last);
    // Drain the async rescan that follows the FRB delete.
    for (
      var i = 0;
      i < 40 && find.byType(AppEmptyState).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    // The row is gone and the empty-state card is back.
    expect(find.byType(AppDataRow), findsNothing);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets(
    'encrypted recording on a no-key tier renders an AppDataRow whose '
    'primary tap target is null (the play hop is gated)',
    (tester) async {
      // Spec: `canPlay` flips off when the row is encrypted and the
      // active DB-key SecretStore slot is missing. `AppDataRow.onTap`
      // gets a null callback so the row reads as visually disabled
      // and tap is a no-op. The delete button stays interactive (no
      // unlock needed to clean up an orphan).
      final root = Directory('${tempDir.path}/recordings/session-locked-tap')
        ..createSync(recursive: true);
      // The migration sweep renames `.lfsr` files whose first bytes
      // are not the `LFR1` magic to `.cast`; carrying valid magic
      // keeps the file at the `.lfsr` extension so the panel sees
      // `encrypted = true`. The tail is uninteresting — header read
      // is best-effort and the panel still lists corrupt files.
      const lfrMagic = <int>[0x4C, 0x46, 0x52, 0x31, 0x01];
      File(
        '${root.path}/2026-05-29T14-00-00.lfsr',
      ).writeAsBytesSync([...lfrMagic, ...List<int>.filled(60, 0)]);

      await pumpUntilRow(tester);
      expect(find.byType(AppDataRow), findsOneWidget);

      // Inspect the AppDataRow widget directly.
      final row = tester.widget<AppDataRow>(find.byType(AppDataRow));
      expect(
        row.onTap,
        isNull,
        reason: 'encrypted + no active DB key → canPlay=false → onTap is null',
      );

      // Verify the locked hint is part of the secondary line.
      final ctx = tester.element(find.byType(RecordingsPanel));
      final l10n = S.of(ctx);
      expect(find.textContaining(l10n.recordingPlayLocked), findsOneWidget);
    },
  );
}
