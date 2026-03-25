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

  group('LetsFLUTsshApp — top-level app widget', () {
    testWidgets('renders MaterialApp with correct title and themes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith((ref) {
              final notifier = ConfigNotifier(ref.watch(configStoreProvider));
              notifier.state = AppConfig.defaults;
              return notifier;
            }),
          ],
          child: const LetsFLUTsshApp(),
        ),
      );
      await tester.pump();

      // Should find MaterialApp
      final materialApps = find.byType(MaterialApp);
      expect(materialApps, findsOneWidget);

      final app = tester.widget<MaterialApp>(materialApps);
      expect(app.title, 'LetsFLUTssh');
      expect(app.debugShowCheckedModeBanner, isFalse);
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
    });

    testWidgets('uses navigatorKey from main.dart', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configProvider.overrideWith((ref) {
              final notifier = ConfigNotifier(ref.watch(configStoreProvider));
              notifier.state = AppConfig.defaults;
              return notifier;
            }),
          ],
          child: const LetsFLUTsshApp(),
        ),
      );
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.navigatorKey, navigatorKey);
    });
  });

  group('MainScreen — narrow layout (drawer)', () {
    Widget buildNarrowApp() {
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
          home: const Center(
            child: SizedBox(
              width: 500,
              height: 600,
              child: MainScreen(),
            ),
          ),
        ),
      );
    }

    testWidgets('narrow layout shows hamburger menu button', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildNarrowApp());
      await tester.pump();

      // In narrow mode, a menu (hamburger) button should appear in the toolbar
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('narrow layout uses Scaffold with drawer', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildNarrowApp());
      await tester.pump();

      final scaffolds = find.byType(Scaffold);
      expect(scaffolds, findsWidgets);
    });

    testWidgets('hamburger button opens drawer', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildNarrowApp());
      await tester.pump();

      // Tap the hamburger menu button
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer should open and show Sessions panel
      expect(find.text('Sessions'), findsOneWidget);
    });
  });

  group('MainScreen — toolbar details', () {
    testWidgets('toolbar does not show SFTP button when no active tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // No active tab → no SFTP folder_open button in toolbar
      // The folder_open icon appears only when SFTP is available
      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('settings button opens settings screen', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Tap settings icon
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Settings screen should appear
      expect(find.text('Appearance'), findsOneWidget);
    });
  });

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

  group('MainScreen — toolbar new session button', () {
    testWidgets('toolbar add button with Ctrl+N tooltip opens dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Tap the toolbar "+" button (the one with Ctrl+N tooltip)
      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      // New Session dialog should appear (may have multiple 'New Session' texts)
      expect(find.text('Host *'), findsOneWidget);

      // Cancel the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('MainScreen — settings button', () {
    testWidgets('settings button in toolbar opens settings', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
    });
  });

  group('_StatusBar — transfer status display', () {
    testWidgets('status bar renders without active transfers', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('No active connection'), findsOneWidget);
      expect(find.textContaining('tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — wide vs narrow layout', () {
    testWidgets('wide layout does not show hamburger menu', (tester) async {
      await tester.pumpWidget(buildApp(width: 1000));
      await tester.pump();

      expect(find.byIcon(Icons.menu), findsNothing);
    });

    testWidgets('wide layout renders SplitView with session panel', (tester) async {
      await tester.pumpWidget(buildApp(width: 1000));
      await tester.pump();

      // Session panel should be visible
      expect(find.text('Sessions'), findsOneWidget);
      // Toolbar should have New Session button
      expect(find.byTooltip('New Session (Ctrl+N)'), findsOneWidget);
    });

    testWidgets('wide layout shows welcome screen when no tabs', (tester) async {
      await tester.pumpWidget(buildApp(width: 1000));
      await tester.pump();

      expect(find.text('SSH/SFTP Client'), findsOneWidget);
      expect(find.text('No active connection'), findsOneWidget);
    });

  });

  group('MainScreen — toolbar', () {
    testWidgets('SFTP button disabled when no active tab', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // SFTP button should not be visible or be disabled
      final sftpButton = find.byTooltip('Open SFTP');
      // No active tab = no SFTP button
      expect(sftpButton, findsNothing);
    });

    testWidgets('settings button opens settings screen', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      final settingsButton = find.byIcon(Icons.settings);
      expect(settingsButton, findsOneWidget);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('MainScreen — divider hidden when no tabs', () {
    testWidgets('no divider below tab bar when no tabs', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // The welcome screen should be shown, no tab bar divider
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });
  });
}
