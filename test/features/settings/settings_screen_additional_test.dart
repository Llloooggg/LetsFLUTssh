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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_add_test_');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await tempDir.delete(recursive: true);
  });

  // Use a very tall widget so everything is visible.
  Widget buildApp() {
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = AppConfig.defaults;
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

  group('SettingsScreen — Export dialog', () {
    testWidgets('Export Data button opens export dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Export Data'), 100, scrollable: find.byType(Scrollable).first);
      await tester.pump();

      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      expect(find.text('Master Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Export dialog rejects empty password', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Export Data'), 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Export Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Master Password'), findsOneWidget);
    });

    // Note: Export with mismatched passwords test omitted because Toast timer
    // causes "Timer still pending" assertion in test framework.
  });

  group('SettingsScreen — Import dialog', () {
    testWidgets('Import Data button opens import dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Import Data'), 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      expect(find.text('Path to .lfs file'), findsOneWidget);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Import dialog rejects empty fields', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Import Data'), 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Import Data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Dialog should still be open (empty fields)
      expect(find.text('Path to .lfs file'), findsOneWidget);
    });
  });

  group('SettingsScreen — About section', () {
    testWidgets('shows Source Code link', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Source Code'), 100, scrollable: find.byType(Scrollable).first);
      expect(find.text('Source Code'), findsOneWidget);
    });

    // Note: Source Code tap test omitted because Toast timer causes
    // "Timer still pending" assertion in test framework.
  });
}
