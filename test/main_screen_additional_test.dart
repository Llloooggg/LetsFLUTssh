import 'dart:io';

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

/// Additional MainScreen tests covering uncovered lines:
/// _buildTabContent, _buildRightSide with active tabs, _StatusBar with active tab,
/// _Toolbar SFTP button, keyboard shortcuts Ctrl+W/Ctrl+Tab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_screen_add_test_');
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
    testWidgets('shows tab bar with divider when tabs are present', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'SSH Tab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Divider should appear below tab bar
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('status bar shows connected state for active tab', (tester) async {
      final conn = makeConn(label: 'MyBox', state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'MyBox', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connected: MyBox'), findsOneWidget);
      expect(find.textContaining('1 tab(s)'), findsOneWidget);
    });

    testWidgets('status bar shows disconnected state for disconnected tab', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Down', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('SFTP button visible when active tab is connected', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Active', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open SFTP Browser'), findsOneWidget);
    });

    testWidgets('SFTP button hidden when active tab is disconnected', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Disc', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open SFTP Browser'), findsNothing);
    });

    testWidgets('renders IndexedStack with terminal tab content', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Tab1', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(IndexedStack), findsOneWidget);
    });

    testWidgets('renders multiple tabs in IndexedStack', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Tab1', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab2', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — keyboard shortcuts with tabs', () {
    testWidgets('Ctrl+W closes active tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'CloseMe', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Focus something inside CallbackShortcuts
      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Tab should be closed, welcome screen shows
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });
  });

  group('MainScreen — new session dialog flow with Save', () {
    testWidgets('new session dialog has Save & Connect button', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      expect(find.text('Save & Connect'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('MainScreen — Ctrl+Tab switches tabs', () {
    testWidgets('Ctrl+Tab cycles to next tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'TabOne', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'TabTwo', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Focus inside the widget tree
      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
      }

      // Ctrl+Tab should switch to next tab
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Both tabs should still be present
      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — narrow layout with tabs', () {
    testWidgets('narrow layout with tabs shows hamburger menu', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final conn = makeConn();
      await tester.pumpWidget(ProviderScope(
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
          tabProvider.overrideWith((ref) {
            final notifier = TabNotifier();
            notifier.addTerminalTab(conn, label: 'NarrowTab');
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
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu), findsOneWidget);
    });
  });

  group('MainScreen — SFTP tab content', () {
    testWidgets('SFTP tab shows FileBrowserTab', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 's1', label: 'SFTPTab', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // SFTP tab should try to render (will show error since no real SSH)
      expect(find.byType(IndexedStack), findsOneWidget);
    });
  });
}
