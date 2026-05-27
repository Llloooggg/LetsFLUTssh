/// Widget test for [RecordingsPanel] — the recordings manager shell.
/// The recording reader / playback / list-logic are covered by
/// recording_reader_test, recording_playback_dialog_test and
/// recordings_logic_test; this covers the panel's scan→render glue:
/// a fresh-install recordings root (no directory) resolves to the
/// empty state rather than an error.
///
/// FRB + the config-store actor are needed because the panel resolves
/// `<appSupport>/recordings` through the Rust recorder and walks it. No
/// DB rows are touched, so no `frb_global_store` isolation is required.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/recordings/recordings_browser.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
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
}
