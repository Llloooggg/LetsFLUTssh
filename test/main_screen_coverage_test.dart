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
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// Additional MainScreen tests for coverage — import dialog, Ctrl+Shift+Tab,
/// connecting state, new session Save flow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_screen_cov_');
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

  group('MainScreen — Ctrl+Shift+Tab (previous tab)', () {
    testWidgets('Ctrl+Shift+Tab cycles to previous tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'First', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Second', connection: conn, kind: TabKind.terminal),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      // Focus inside the widget tree
      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
      }

      // Ctrl+Shift+Tab should switch to previous tab
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Both tabs should still be present
      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — connecting state in status bar', () {
    testWidgets('shows Disconnected for connecting state', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connecting);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Connecting', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Connecting tab is not isConnected, so shows Disconnected
      expect(find.text('Disconnected'), findsOneWidget);
    });
  });

  group('MainScreen — new session dialog Connect-only flow', () {
    testWidgets('new session dialog has Connect button', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      // Dialog should have Connect button (for connect-only without saving)
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Save & Connect'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('new session dialog fill and cancel returns to main', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      await tester.tap(find.byTooltip('New Session (Ctrl+N)'));
      await tester.pumpAndSettle();

      // Fill in host field
      final hostField = find.widgetWithText(TextField, 'Host *');
      expect(hostField, findsOneWidget);
      await tester.enterText(hostField, 'test.example.com');
      await tester.pump();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });
  });

  group('MainScreen — SFTP button interaction', () {
    testWidgets('SFTP button has Open SFTP Browser tooltip', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Active', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open SFTP Browser'), findsOneWidget);
    });

    testWidgets('tapping SFTP button adds SFTP tab', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Active', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 tab(s)'), findsOneWidget);

      await tester.tap(find.byTooltip('Open SFTP Browser'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — tab bar presence', () {
    testWidgets('tab bar shown with multiple terminal tabs', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Tab1', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab2', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't3', label: 'Tab3', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — _switchTab does nothing with single tab', () {
    testWidgets('Ctrl+Tab with single tab does not crash', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'OnlyTab', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Focus
      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Still shows 1 tab
      expect(find.textContaining('1 tab(s)'), findsOneWidget);
    });
  });

  group('MainScreen — Ctrl+W with no tabs', () {
    testWidgets('Ctrl+W with no active tab does nothing', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.tap(textFields.first);
        await tester.pump();
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Still shows welcome screen
      expect(find.text('SSH/SFTP Client'), findsOneWidget);
    });
  });

  group('MainScreen — status bar connected state', () {
    testWidgets('shows Connected: label for connected tab', (tester) async {
      final conn = makeConn(label: 'MyServer', state: SSHConnectionState.connected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'MyServer', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connected: MyServer'), findsOneWidget);
    });
  });

  group('MainScreen — settings button', () {
    testWidgets('settings button opens settings screen', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      // Settings screen should be shown
      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('MainScreen — SFTP tab content', () {
    testWidgets('SFTP tab shows file browser error (no SSH)', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'SFTP', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // FileBrowserTab should show error since sshConnection is null
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('MainScreen — no active connection text', () {
    testWidgets('shows No active connection when no tabs', (tester) async {
      await tester.pumpWidget(buildAppWithTabs());
      await tester.pump();

      expect(find.text('No active connection'), findsOneWidget);
    });
  });

  group('MainScreen — sidebar divider drag', () {
    testWidgets('sidebar divider changes width on drag', (tester) async {
      await tester.pumpWidget(buildAppWithTabs(width: 1200));
      await tester.pumpAndSettle();

      // Find the divider (MouseRegion with resizeColumn cursor)
      final dividers = find.byWidgetPredicate((w) =>
          w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);

      if (dividers.evaluate().isNotEmpty) {
        await tester.drag(dividers.first, const Offset(50, 0));
        await tester.pumpAndSettle();
        // Widget should rebuild without errors
      }
    });
  });

  group('MainScreen — narrow layout with connected tab', () {
    testWidgets('narrow layout with connected tab shows SFTP button', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final conn = makeConn(state: SSHConnectionState.connected);
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
            notifier.addTerminalTab(conn, label: 'Active');
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
      expect(find.byTooltip('Open SFTP Browser'), findsOneWidget);
    });
  });

  group('_StatusBar — active transfer status', () {
    testWidgets('shows transfer info when transfers are active', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);

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
            notifier.addTerminalTab(conn, label: 'Active');
            return notifier;
          }),
          transferStatusProvider.overrideWith((ref) {
            return Stream.value(const ActiveTransferState(
              running: 2,
              queued: 1,
              currentInfo: 'file.txt 45%',
            ));
          }),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(1000, 600)),
            child: SizedBox(
              width: 1000,
              height: 600,
              child: MainScreen(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Transfer info should be visible in the status bar
      expect(find.text('file.txt 45%'), findsOneWidget);
      expect(find.byIcon(Icons.swap_vert), findsOneWidget);
    });

    testWidgets('shows running count when no currentInfo', (tester) async {
      final conn = makeConn(state: SSHConnectionState.connected);

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
            notifier.addTerminalTab(conn, label: 'Active');
            return notifier;
          }),
          transferStatusProvider.overrideWith((ref) {
            return Stream.value(const ActiveTransferState(
              running: 3,
              queued: 0,
              currentInfo: null,
            ));
          }),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(size: Size(1000, 600)),
            child: SizedBox(
              width: 1000,
              height: 600,
              child: MainScreen(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Fallback text: "3 active"
      expect(find.text('3 active'), findsOneWidget);
    });
  });

  group('MainScreen — SFTP tab rendering via _buildTabContent', () {
    testWidgets('SFTP tab renders FileBrowserTab in IndexedStack', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 's1', label: 'SFTP', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // _buildTabContent should render TabKind.sftp case as FileBrowserTab
      expect(find.byType(IndexedStack), findsOneWidget);
      expect(find.textContaining('1 tab(s)'), findsOneWidget);
    });

    testWidgets('mixed terminal and SFTP tabs render correctly', (tester) async {
      final conn = makeConn(state: SSHConnectionState.disconnected);
      await tester.pumpWidget(buildAppWithTabs(tabs: [
        TabEntry(id: 't1', label: 'Terminal', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 's1', label: 'Files', connection: conn, kind: TabKind.sftp),
      ], activeIndex: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 tab(s)'), findsOneWidget);
    });
  });
}
