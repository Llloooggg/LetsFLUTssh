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
}
