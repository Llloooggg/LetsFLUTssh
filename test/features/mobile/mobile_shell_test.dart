import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_shell.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// A TabNotifier subclass that starts with a pre-built TabState.
class _PrePopulatedTabNotifier extends TabNotifier {
  final TabState _initialState;
  _PrePopulatedTabNotifier(this._initialState);

  @override
  TabState build() => _initialState;
}

/// Helper to build a TabState with tabs added via a setup callback.
TabState _buildTabState(void Function(_TabStateBuilder) setup) {
  final builder = _TabStateBuilder();
  setup(builder);
  return TabState(
    tabs: builder._tabs,
    activeIndex: builder._tabs.isEmpty ? -1 : builder._tabs.length - 1,
  );
}

class _TabStateBuilder {
  final List<TabEntry> _tabs = [];
  int _counter = 0;

  void addTerminalTab(Connection conn, {String? label}) {
    _tabs.add(TabEntry(
      id: 'tab-${_counter++}',
      label: label ?? conn.label,
      connection: conn,
      kind: TabKind.terminal,
    ));
  }

  void addSftpTab(Connection conn, {String? label}) {
    _tabs.add(TabEntry(
      id: 'tab-${_counter++}',
      label: label ?? '${conn.label} (SFTP)',
      connection: conn,
      kind: TabKind.sftp,
    ));
  }
}

/// A SessionNotifier subclass that starts with pre-populated sessions.
class _PrePopulatedSessionNotifier extends SessionNotifier {
  final List<Session> _initialSessions;
  _PrePopulatedSessionNotifier(this._initialSessions);

  @override
  List<Session> build() {
    super.build();
    state = _initialSessions;
    return state;
  }
}

/// A SessionNotifier that stores in-memory only (no disk I/O).
class _InMemorySessionNotifier extends SessionNotifier {
  @override
  List<Session> build() => [];

  @override
  Future<void> add(Session session) async {
    state = [...state, session];
  }
}

/// A ConnectionManager that simulates a connection that fails in background.
class _FailingConnectionManager extends ConnectionManager {
  final Object error;
  _FailingConnectionManager(this.error)
      : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(SSHConfig config, {String? label}) {
    final conn = Connection(
      id: 'conn-fail',
      label: label ?? config.displayName,
      sshConfig: config,
      state: SSHConnectionState.disconnected,
      connectionError: error.toString(),
    );
    return conn;
  }
}

/// A ConnectionManager that returns a connected connection (simulates success).
class _SuccessConnectionManager extends ConnectionManager {
  _SuccessConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(SSHConfig config, {String? label}) {
    return Connection(
      id: 'conn-success',
      label: label ?? config.displayName,
      sshConfig: config,
      sshConnection: null,
      state: SSHConnectionState.connected,
    );
  }
}

void main() {
  group('MobileShell', () {
    Widget buildTestWidget({
      List<Session> sessions = const [],
      TabState? tabState,
    }) {
      return ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(SessionStore()),
          sessionProvider.overrideWith(SessionNotifier.new),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            ConnectionManager(knownHosts: KnownHostsManager()),
          ),
          if (tabState != null)
            tabProvider.overrideWith(TabNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MobileShell(),
        ),
      );
    }

    testWidgets('renders bottom navigation bar with 3 destinations', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      // "Sessions" appears in both nav bar and session panel header
      expect(find.text('Sessions'), findsAtLeast(1));
      expect(find.text('Terminal'), findsAtLeast(1));
      expect(find.text('Files'), findsAtLeast(1));
    });

    testWidgets('shows Sessions page initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Sessions page has the app title
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      // Settings icon should be visible
      expect(find.byIcon(Icons.settings), findsAtLeast(1));
    });

    testWidgets('shows FAB on sessions page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('switches to Terminal page on nav tap', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Terminal destination
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Terminal empty state
      expect(find.text('No active terminals'), findsOneWidget);
      expect(find.text('Connect from Sessions tab'), findsOneWidget);

      // FAB should not be visible on terminal page
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('switches to Files page on nav tap', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Files destination
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // SFTP empty state
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('navigates back to Sessions from Terminal', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Go to Terminal
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Go back to Sessions
      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });

    testWidgets('shows terminal tab chips when tabs exist', (tester) async {
      // Create a connection for a tab
      final conn = Connection(
        id: 'conn-1',
        label: 'My Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'example.com', user: 'root')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) => b.addTerminalTab(conn)),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Should show the tab chip with the connection label
      expect(find.text('My Server'), findsOneWidget);
    });

    testWidgets('shows SFTP tab chips when tabs exist', (tester) async {
      final conn = Connection(
        id: 'conn-2',
        label: 'SFTP Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'sftp.example.com', user: 'admin')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) => b.addSftpTab(conn)),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Should show the SFTP tab chip
      expect(find.text('SFTP Server (SFTP)'), findsOneWidget);
    });

    testWidgets('close button on terminal tab chip closes tab', (tester) async {
      final conn = Connection(
        id: 'conn-close',
        label: 'Close Me',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) => b.addTerminalTab(conn, label: 'Close Me')),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('Close Me'), findsOneWidget);

      // Find and tap the close icon on the InputChip
      final closeIcons = find.byIcon(Icons.close);
      if (closeIcons.evaluate().isNotEmpty) {
        await tester.tap(closeIcons.first);
        await tester.pumpAndSettle();
      }
    });

    testWidgets('swipe right navigates to previous tab', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to Terminal first
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Swipe right (positive velocity) to go back to Sessions
      await tester.fling(
        find.text('No active terminals'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Should be back on Sessions
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });

    testWidgets('swipe left navigates to next tab', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Start on Sessions, swipe left to go to Terminal
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Should be on Terminal page
      expect(find.text('No active terminals'), findsOneWidget);
    });

    testWidgets('FAB not shown on Files page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('SFTP page shows empty state with hint text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('No active file browsers'), findsOneWidget);
      expect(find.text('Use "SFTP" from Sessions'), findsOneWidget);
    });

    testWidgets('terminal page shows empty state with hint text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('No active terminals'), findsOneWidget);
      expect(find.text('Connect from Sessions tab'), findsOneWidget);
    });

    testWidgets('settings button opens settings screen', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('SFTP close button on tab chip closes tab', (tester) async {
      final conn = Connection(
        id: 'conn-sftp-close',
        label: 'SFTP Close Me',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) => b.addSftpTab(conn, label: 'SFTP Close Me')),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('SFTP Close Me'), findsOneWidget);

      // Tap the close icon on the SFTP InputChip
      final closeIcons = find.byIcon(Icons.close);
      if (closeIcons.evaluate().isNotEmpty) {
        await tester.tap(closeIcons.first);
        await tester.pumpAndSettle();
      }

      // After closing, should show empty state
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('SFTP tab chip onPressed selects that tab', (tester) async {
      final conn1 = Connection(
        id: 'sftp-1',
        label: 'SFTP A',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'a.com', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final conn2 = Connection(
        id: 'sftp-2',
        label: 'SFTP B',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'b.com', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) {
                b.addSftpTab(conn1, label: 'SFTP A');
                b.addSftpTab(conn2, label: 'SFTP B');
              }),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Both SFTP tabs should show
      expect(find.text('SFTP A'), findsOneWidget);
      expect(find.text('SFTP B'), findsOneWidget);

      // Tap on the first chip to select it
      await tester.tap(find.text('SFTP A'));
      await tester.pumpAndSettle();
    });

    testWidgets('terminal tab chip onPressed selects that tab', (tester) async {
      final conn1 = Connection(
        id: 'term-1',
        label: 'Term A',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'a.com', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final conn2 = Connection(
        id: 'term-2',
        label: 'Term B',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'b.com', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) {
                b.addTerminalTab(conn1, label: 'Term A');
                b.addTerminalTab(conn2, label: 'Term B');
              }),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Both terminal tabs should show
      expect(find.text('Term A'), findsOneWidget);
      expect(find.text('Term B'), findsOneWidget);

      // Tap on the first chip to select it
      await tester.tap(find.text('Term A'));
      await tester.pumpAndSettle();
    });

    testWidgets('SFTP page falls back to last tab when activeTab is not SFTP', (tester) async {
      final termConn = Connection(
        id: 'term-x',
        label: 'Terminal',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final sftpConn = Connection(
        id: 'sftp-x',
        label: 'SFTP Tab',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) {
                // Add SFTP tab first, then terminal tab (terminal becomes active)
                b.addSftpTab(sftpConn, label: 'SFTP Tab');
                b.addTerminalTab(termConn, label: 'Terminal');
              }),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page — activeTab is terminal, so SFTP page should fall back to last sftp tab
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('SFTP Tab'), findsOneWidget);
    });

    testWidgets('Terminal page falls back to last tab when activeTab is not terminal', (tester) async {
      final termConn = Connection(
        id: 'term-y',
        label: 'Term Tab',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final sftpConn = Connection(
        id: 'sftp-y',
        label: 'SFTP',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) {
                // Add terminal tab first, then SFTP tab (SFTP becomes active)
                b.addTerminalTab(termConn, label: 'Term Tab');
                b.addSftpTab(sftpConn, label: 'SFTP');
              }),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page — activeTab is SFTP, so terminal page should fall back
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('Term Tab'), findsOneWidget);
    });

    testWidgets('swipe does not go below index 0', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Already at index 0 (Sessions), swipe right should not change
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Should still be on Sessions
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });

    testWidgets('swipe does not go above index 2', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to Files (index 2) first
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Swipe left should not change (already at max)
      await tester.fling(
        find.text('No active file browsers'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Should still be on Files
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('double swipe from Sessions reaches Files', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Swipe left to Terminal
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Swipe left to Files
      await tester.fling(
        find.text('No active terminals'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    // Helper to build widget with a session and custom ConnectionManager
    Widget buildWithSession({
      required Session session,
      required ConnectionManager manager,
    }) {
      final store = SessionStore();
      store.add(session);
      return ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          sessionProvider.overrideWith(() =>
              _PrePopulatedSessionNotifier(store.sessions)),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(manager),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MobileShell(),
        ),
      );
    }

    Future<void> doubleTapSession(WidgetTester tester, String label) async {
      // GestureDetector.onDoubleTap needs two taps within 300ms
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(label));
      // Pump to let the async connect resolve and dialog dismiss
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('connect session adds tab and navigates to terminal', (tester) async {
      final session = Session(id: 'sess-1', label: 'Test Server', server: const ServerAddress(host: 'example.com', user: 'root'));
      await tester.pumpWidget(buildWithSession(
        session: session,
        manager: _SuccessConnectionManager(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Test Server'), findsOneWidget);

      await doubleTapSession(tester, 'Test Server');
    });

    testWidgets('connect session with failed connection still adds tab', (tester) async {
      final session = Session(id: 'sess-fail', label: 'Fail Server', server: const ServerAddress(host: 'fail.com', user: 'root'));
      await tester.pumpWidget(buildWithSession(
        session: session,
        manager: _FailingConnectionManager(Exception('bad password')),
      ));
      await tester.pumpAndSettle();

      // Double-tap triggers connect + nav switch — tab is added even if disconnected
      await doubleTapSession(tester, 'Fail Server');
    });

    testWidgets('SFTP connect via context menu navigates to Files page',
        (tester) async {
      final session = Session(
        id: 'sess-sftp',
        label: 'SFTP Target',
        server: const ServerAddress(host: 'sftp.example.com', user: 'admin'),
      );
      await tester.pumpWidget(buildWithSession(
        session: session,
        manager: _SuccessConnectionManager(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SFTP Target'), findsOneWidget);

      // Right-click (secondary tap) on the session to open context menu
      await tester.tap(
        find.text('SFTP Target'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Tap 'SFTP' in the context menu
      expect(find.text('SFTP'), findsOneWidget);
      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      // Should navigate to Files page (index 2) after _connectSessionSftp
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(2));
    });

    testWidgets('FAB opens New Session dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // New Session dialog should appear
      expect(find.text('New Session'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('FAB new session — Connect Only navigates to Terminal',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the FAB to open dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill in required fields (Host and Username)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host *'),
        'quick.example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username *'),
        'quickuser',
      );
      await tester.pumpAndSettle();

      // Tap "Connect" button (ConnectOnlyResult path)
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Should navigate to Terminal page (index 1) via _newSession ConnectOnlyResult
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(1));
    });

    testWidgets('FAB new session — Save & Connect saves and navigates to Terminal',
        (tester) async {
      // Use in-memory session notifier to avoid disk I/O in SessionStore.add()
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(_InMemorySessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the FAB to open dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill in required fields
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Host *'),
        'save.example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username *'),
        'saveuser',
      );
      await tester.pumpAndSettle();

      // Tap "Save & Connect" button (SaveResult with connect=true path)
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Should navigate to Terminal page (index 1) via _newSession SaveResult
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(1));
    });

    testWidgets('FAB new session — Cancel does not navigate', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap the FAB to open dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap "Cancel"
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Should still be on Sessions page (index 0)
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(0));
    });

    testWidgets('badge shows terminal tab count', (tester) async {
      final conn = Connection(
        id: 'conn-3',
        label: 'Server',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith(() => _PrePopulatedTabNotifier(
              _buildTabState((b) {
                b.addTerminalTab(conn, label: 'Tab 1');
                b.addTerminalTab(conn, label: 'Tab 2');
              }),
            )),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Badge should show "2" for terminal tabs
      expect(find.text('2'), findsWidgets);
    });
  });
}
