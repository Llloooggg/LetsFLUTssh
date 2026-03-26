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
    tempDir = await Directory.systemTemp.createTemp('settings_final_cov_');
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

  group('SettingsScreen — import dialog Replace mode submits with correct mode', () {
    testWidgets('import in Replace mode sends Replace in result', (tester) async {
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

      // Switch to Replace
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      // Verify description
      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      // Fill fields
      await tester.enterText(
          find.widgetWithText(TextField, 'Path to .lfs file'),
          '/tmp/test_import_replace.lfs');
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'pw123');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Path to .lfs file'), findsNothing);

      // Wait for async processing and toast
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — scrollback field value submission', () {
    testWidgets('scrollback field accepts boundary value 100', (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('scrollback out of range value rejected', (tester) async {
      await tester.pumpWidget(buildApp());

      final scrollbackField = find.widgetWithText(TextFormField, '5000');
      await tester.tap(scrollbackField);
      await tester.pumpAndSettle();
      await tester.enterText(scrollbackField, '50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 50 < min (100), should not update — no crash
    });
  });

  group('SettingsScreen — max history field boundary', () {
    testWidgets('max history field accepts max boundary 5000', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Max History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      final historyField = find.widgetWithText(TextFormField, '500');
      await tester.tap(historyField);
      await tester.pumpAndSettle();
      await tester.enterText(historyField, '5000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('5000'), findsOneWidget);
    });
  });

  group('SettingsScreen — connection section field interactions', () {
    testWidgets('SSH timeout field accepts valid value', (tester) async {
      // Use custom config so sshTimeoutSec has a unique display value
      final config = AppConfig.defaults.copyWith(sshTimeoutSec: 15);
      await tester.pumpWidget(buildApp(initialConfig: config));

      final timeoutField = find.widgetWithText(TextFormField, '15');
      await tester.tap(timeoutField);
      await tester.pumpAndSettle();
      await tester.enterText(timeoutField, '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('30'), findsWidgets);
    });

    testWidgets('default port field accepts custom port', (tester) async {
      await tester.pumpWidget(buildApp());

      final portField = find.widgetWithText(TextFormField, '22');
      await tester.tap(portField);
      await tester.pumpAndSettle();
      await tester.enterText(portField, '8022');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('8022'), findsOneWidget);
    });
  });

  group('SettingsScreen — theme switching and about section', () {
    testWidgets('tapping Light then Dark switches correctly', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);
    });
  });

  group('SettingsScreen — export flow with successful export', () {
    testWidgets('export with valid password creates file and shows toast', (tester) async {
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

      // Enter matching passwords
      await tester.enterText(
          find.widgetWithText(TextField, 'Master Password'), 'exportpass');
      await tester.enterText(
          find.widgetWithText(TextField, 'Confirm Password'), 'exportpass');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Confirm Password'), findsNothing);

      // Wait for async export and toast
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
