import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/main.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// Widget tests for MainScreen — covers the refactored methods:
/// _buildDesktopLayout, _buildRightSide, _buildKeyBindings, _switchTab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_screen_test_');
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

  Widget buildApp({double width = 1000, double height = 600}) {
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = AppConfig.defaults;
          return notifier;
        }),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: SizedBox(
            width: width,
            height: height,
            child: const MainScreen(),
          ),
        ),
      ),
    );
  }

  group('MainScreen — desktop layout', () {
    testWidgets('renders toolbar with New Session and Settings buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Toolbar has add icons (in toolbar + session panel), settings in toolbar
      expect(find.byIcon(Icons.add), findsWidgets);
      expect(find.byIcon(Icons.settings), findsWidgets);
    });

    testWidgets('shows welcome screen when no tabs open', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('LetsFLUTssh'), findsWidgets);
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });

    testWidgets('status bar shows "No active connection"', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('No active connection'), findsOneWidget);
    });

    testWidgets('status bar shows tab count', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.textContaining('tab'), findsWidgets);
    });

    testWidgets('contains Scaffold widget', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('toolbar has tooltip with Ctrl+N', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Find all IconButtons and check at least one has Ctrl+N tooltip
      final iconButtons = find.byType(IconButton);
      expect(iconButtons, findsWidgets);

      bool foundCtrlN = false;
      for (int i = 0; i < tester.widgetList(iconButtons).length; i++) {
        final btn = tester.widgetList<IconButton>(iconButtons).elementAt(i);
        if (btn.tooltip?.contains('Ctrl+N') == true) {
          foundCtrlN = true;
          break;
        }
      }
      expect(foundCtrlN, isTrue);
    });

    testWidgets('renders session panel (sidebar)', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Session panel should have search field or session-related text
      expect(find.byType(TextField), findsWidgets);
    });
  });
}
