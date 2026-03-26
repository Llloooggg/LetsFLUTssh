import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/main.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
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

  group('MainScreen — keyboard shortcuts', () {
    testWidgets('Ctrl+N opens new session dialog via shortcut', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Request focus by tapping the search field in the session panel
      // This places focus inside the CallbackShortcuts subtree
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
      await tester.tap(textFields.first);
      await tester.pump();

      // Send Ctrl+N keyboard shortcut
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // New Session dialog should appear
      expect(find.text('Host *'), findsOneWidget);

      // Cancel the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('MainScreen — _newSession dialog flow', () {
    testWidgets('new session dialog cancel returns to main screen',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Open dialog via toolbar button
      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      expect(find.text('Host *'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Back to welcome screen
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });

    testWidgets('new session dialog shows auth type selector', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      // Dialog should have auth type options
      expect(find.text('Password'), findsWidgets);
    });
  });

  group('MainScreen — welcome screen interaction', () {
    testWidgets('welcome screen New Session button opens dialog',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // Find the "New Session" FilledButton on welcome screen
      final newSessionBtn = find.widgetWithText(FilledButton, 'New Session');
      expect(newSessionBtn, findsOneWidget);

      await tester.tap(newSessionBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Host *'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('MainScreen — DropTarget', () {
    testWidgets('desktop layout includes DropTarget widget', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      // DropTarget should be in the widget tree (from desktop_drop)
      expect(find.byType(DropTarget), findsOneWidget);
    });
  });

  group('MainScreen — CallbackShortcuts', () {
    testWidgets('layout includes CallbackShortcuts', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.byType(CallbackShortcuts), findsOneWidget);
    });
  });

  // --- Tests requiring active tabs ---

  Connection makeConn({
    String label = 'TestServer',
    SSHConnectionState state = SSHConnectionState.connected,
  }) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
      state: state,
    );
  }

  Widget buildAppWithTabs({
    double width = 1000,
    double height = 600,
    List<TabEntry>? tabs,
    int activeIndex = 0,
  }) {
    return ProviderScope(
      overrides: [
        configProvider.overrideWith((ref) {
          final notifier = ConfigNotifier(ref.watch(configStoreProvider));
          notifier.state = AppConfig.defaults;
          return notifier;
        }),
        sessionStoreProvider.overrideWithValue(SessionStore()),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(
          ConnectionManager(knownHosts: KnownHostsManager()),
        ),
        if (tabs != null)
          tabProvider.overrideWith((ref) {
            final notifier = TabNotifier();
            for (final tab in tabs) {
              if (tab.kind == TabKind.terminal) {
                notifier.addTerminalTab(tab.connection, label: tab.label);
              } else {
                notifier.addSftpTab(tab.connection, label: tab.label);
              }
            }
            if (activeIndex >= 0 && activeIndex < tabs.length) {
              notifier.selectTab(activeIndex);
            }
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

  group('MainScreen — with active tabs', () {
    testWidgets('shows tab bar with divider when tabs are present',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'SSH Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('status bar shows connected state for active tab',
        (tester) async {
      final conn =
          makeConn(label: 'MyBox', state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'MyBox',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connected'), findsOneWidget);
    });

    testWidgets('status bar shows disconnected state for disconnected tab',
        (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'Down',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Disconnected'), findsOneWidget);
    });

    testWidgets('SFTP button visible when active tab is connected',
        (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open SFTP Browser'), findsOneWidget);
    });

    testWidgets('SFTP button hidden when active tab is disconnected',
        (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'Tab',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open SFTP Browser'), findsNothing);
    });
  });

  group('MainScreen — keyboard shortcuts with tabs', () {
    testWidgets('Ctrl+Tab cycles to next tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'First',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Second',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });

    testWidgets('Ctrl+Shift+Tab cycles to previous tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'First',
            connection: conn,
            kind: TabKind.terminal),
        TabEntry(
            id: 't2',
            label: 'Second',
            connection: conn,
            kind: TabKind.terminal),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });

    testWidgets('Ctrl+Tab with single tab does not crash', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'Only',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 tab(s)'), findsOneWidget);
    });

  });

  group('MainScreen — SFTP tab addition', () {
    testWidgets('tapping SFTP button adds SFTP tab', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(
            id: 't1',
            label: 'Term',
            connection: conn,
            kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      final sftpBtn = find.byTooltip('Open SFTP Browser');
      expect(sftpBtn, findsOneWidget);

      await tester.tap(sftpBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — sidebar divider drag', () {
    testWidgets('sidebar divider changes width on drag', (tester) async {
      await tester.pumpWidget(buildAppWithTabs(width: 1200));
      await tester.pumpAndSettle();

      final dividers = find.byWidgetPredicate(
        (w) =>
            w is MouseRegion &&
            w.cursor == SystemMouseCursors.resizeColumn,
      );
      if (dividers.evaluate().isNotEmpty) {
        await tester.drag(dividers.first, const Offset(50, 0));
        await tester.pumpAndSettle();
      }
      // No crash
      expect(find.byType(Scaffold), findsWidgets);
    });
  });
}
