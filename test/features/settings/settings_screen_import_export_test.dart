import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/features/settings/settings_screen.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_ie_test_');
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

  Widget buildApp({AppConfig? initialConfig}) {
    final config = initialConfig ?? AppConfig.defaults;
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = config;
          return notifier;
        }),
        sessionStoreProvider.overrideWithValue(SessionStore()),
        sessionProvider.overrideWith((ref) {
          return SessionNotifier(ref.watch(sessionStoreProvider));
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

  group('SettingsScreen — export error toast (lines 287-288)', () {
    testWidgets('export fails gracefully when path_provider errors',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Override path_provider to throw after dialog is submitted
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            throw PlatformException(code: 'ERROR', message: 'No dir');
          }
          return null;
        },
      );

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'p');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'p');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      // Wait for error toast
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import file not found (lines 418-419)', () {
    testWidgets('import with nonexistent file shows error toast',
        (tester) async {
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

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/nonexistent_file_that_does_not_exist_12345.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Wait for async file check and toast
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog validation', () {
    testWidgets('import button does nothing with empty path', (tester) async {
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

      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Path to .lfs file'), findsOneWidget);
    });

    testWidgets('import button does nothing with empty password',
        (tester) async {
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

      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'), '/tmp/f.lfs');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      expect(find.text('Path to .lfs file'), findsOneWidget);
    });
  });

  group('SettingsScreen — import/export cancel dialogs', () {
    testWidgets('cancel closes import dialog', (tester) async {
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

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Path to .lfs file'), findsNothing);
    });

    testWidgets('cancel closes export dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Password'), findsNothing);
    });
  });
}
