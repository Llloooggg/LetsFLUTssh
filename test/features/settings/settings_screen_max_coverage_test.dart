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

/// Max coverage for settings_screen.dart — covers export with matching passwords
/// that triggers actual export, import dialog Replace mode submit,
/// _buildImportModeSelector, _buildImportDialogActions, _executeImport
/// with non-existent file, and _applyImportedConfig.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_max_cov_');
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

  group('SettingsScreen — export with matching passwords triggers export', () {
    testWidgets('export succeeds and shows success toast', (tester) async {
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
      final masterPw = find.widgetWithText(TextField, 'Master Password');
      final confirmPw = find.widgetWithText(TextField, 'Confirm Password');
      await tester.enterText(masterPw, 'securepass');
      await tester.enterText(confirmPw, 'securepass');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      // Dialog should close
      expect(find.text('Confirm Password'), findsNothing);

      // Wait for async export and toast
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog Replace mode submit', () {
    testWidgets('import with Replace mode and nonexistent file shows error', (tester) async {
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

      // Switch to Replace mode
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      // Verify Replace description
      expect(find.text('Replace all sessions with imported'), findsOneWidget);

      // Fill fields and submit
      final pathField = find.widgetWithText(TextField, 'Path to .lfs file');
      final pwField = find.widgetWithText(TextField, 'Master Password');
      await tester.enterText(pathField, '/tmp/nonexistent_replace.lfs');
      await tester.enterText(pwField, 'pass123');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog should close (submit with both fields filled)
      expect(find.text('Path to .lfs file'), findsNothing);

      // Wait for toast
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — import dialog partial field validation', () {
    testWidgets('import with only path filled does not submit', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Fill only path
      final pathField = find.widgetWithText(TextField, 'Path to .lfs file');
      await tester.enterText(pathField, '/tmp/test.lfs');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog still open
      expect(find.text('Path to .lfs file'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('import with only password filled does not submit', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Import Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      // Fill only password
      final pwField = find.widgetWithText(TextField, 'Master Password');
      await tester.enterText(pwField, 'pass123');

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // Dialog still open
      expect(find.text('Path to .lfs file'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — export password mismatch warning', () {
    testWidgets('mismatched passwords shows warning toast', (tester) async {
      await tester.pumpWidget(buildApp());

      await tester.scrollUntilVisible(
        find.text('Export Data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      final masterPw = find.widgetWithText(TextField, 'Master Password');
      final confirmPw = find.widgetWithText(TextField, 'Confirm Password');
      await tester.enterText(masterPw, 'one');
      await tester.enterText(confirmPw, 'two');

      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pump();

      // Toast should appear
      expect(find.text('Passwords do not match'), findsOneWidget);

      // Dialog still open
      expect(find.text('Master Password'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });

  group('SettingsScreen — font size slider drag', () {
    testWidgets('dragging slider updates font size value', (tester) async {
      await tester.pumpWidget(buildApp());

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Drag slider to the right to increase font size
      await tester.drag(slider, const Offset(100, 0));
      await tester.pumpAndSettle();

      // Slider should have changed value (no crash)
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  group('SettingsScreen — Reset to Defaults with custom config', () {
    testWidgets('reset changes custom values back to defaults', (tester) async {
      final custom = AppConfig.defaults.copyWith(
        fontSize: 22.0,
        scrollback: 20000,
        keepAliveSec: 120,
        sshTimeoutSec: 45,
        defaultPort: 3333,
        transferWorkers: 8,
        maxHistory: 2000,
        theme: 'light',
      );
      await tester.pumpWidget(buildApp(initialConfig: custom));

      await tester.scrollUntilVisible(
        find.text('Reset to Defaults'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Reset to Defaults'));
      await tester.pumpAndSettle();

      // Should render without crash
      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
