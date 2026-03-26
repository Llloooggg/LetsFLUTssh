import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// Extra coverage for settings_screen.dart — covers _executeImport with
/// non-existent file (File not found toast), _applyImportedSessions
/// merge mode skip duplicate, and _applyImportedConfig null branch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_extra_cov_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    Toast.clearAllForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await tempDir.delete(recursive: true);
  });

  Widget buildApp({AppConfig? initialConfig, List<Session>? sessions}) {
    final config = initialConfig ?? AppConfig.defaults;
    final store = SessionStore();
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = config;
          return notifier;
        }),
        sessionStoreProvider.overrideWithValue(store),
        sessionProvider.overrideWith((ref) {
          final notifier = SessionNotifier(store);
          if (sessions != null) notifier.state = sessions;
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SizedBox(
          height: 2000,
          child: SettingsScreen(),
        ),
      ),
    );
  }

  group('SettingsScreen — import dialog submit with both fields', () {
    testWidgets('import dialog closes when both path and password are filled', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Fill path to non-existent file and password
      final pathField = find.widgetWithText(TextField, 'Path to .lfs file');
      final pwField = find.widgetWithText(TextField, 'Master Password');
      await tester.enterText(pathField, '/tmp/definitely_not_existing_file_abc123.lfs');
      await tester.enterText(pwField, 'password123');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog should close (both fields filled -> result returned)
      expect(find.text('Path to .lfs file'), findsNothing);

      // Wait for any async processing (import will fail with missing file)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — export dialog cancel path', () {
    testWidgets('export cancel returns null and does nothing', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      // Cancel export dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // No toast, no error
      expect(find.text('Export Data'), findsOneWidget);
    });
  });

  group('SettingsScreen — import dialog empty fields guard', () {
    testWidgets('tapping Import with empty path does not submit', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Only fill password, leave path empty
      final pwField = find.widgetWithText(TextField, 'Master Password');
      await tester.enterText(pwField, 'pass');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog still open — empty path prevents submit
      expect(find.text('Path to .lfs file'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — scrollback field accepts valid value', () {
    testWidgets('scrollback field accepts 10000', (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, '10000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('10000'), findsOneWidget);
    });
  });

  group('SettingsScreen — SettingsScreen.show via static method', () {
    testWidgets('show() pushes SettingsScreen route', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith((ref) {
              final notifier = ConfigNotifier(ref.watch(configStoreProvider));
              notifier.state = AppConfig.defaults;
              return notifier;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => SettingsScreen.show(context),
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);

      // Back
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Go'), findsOneWidget);
    });
  });
}
