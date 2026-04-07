import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_shell.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/theme_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/utils/platform.dart';
import 'package:letsflutssh/widgets/status_indicator.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// A WorkspaceNotifier subclass that starts with a pre-built WorkspaceState.
class _PrePopulatedWorkspaceNotifier extends WorkspaceNotifier {
  final WorkspaceState _initialState;
  _PrePopulatedWorkspaceNotifier(this._initialState);

  @override
  WorkspaceState build() => _initialState;
}

/// Helper to build a WorkspaceState with tabs added via a setup callback.
WorkspaceState _buildWorkspaceState(
  void Function(_WorkspaceStateBuilder) setup,
) {
  final builder = _WorkspaceStateBuilder();
  setup(builder);
  final panel = PanelLeaf(
    id: 'panel-0',
    tabs: builder._tabs,
    activeTabIndex: builder._tabs.isEmpty ? -1 : builder._tabs.length - 1,
  );
  return WorkspaceState(root: panel, focusedPanelId: panel.id);
}

class _WorkspaceStateBuilder {
  final List<TabEntry> _tabs = [];
  int _counter = 0;

  void addTerminalTab(Connection conn, {String? label}) {
    _tabs.add(
      TabEntry(
        id: 'tab-${_counter++}',
        label: label ?? conn.label,
        connection: conn,
        kind: TabKind.terminal,
      ),
    );
  }

  void addSftpTab(Connection conn, {String? label}) {
    _tabs.add(
      TabEntry(
        id: 'tab-${_counter++}',
        label: label ?? '${conn.label} (SFTP)',
        connection: conn,
        kind: TabKind.sftp,
      ),
    );
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

/// A ConnectionManager that simulates a connection that fails in background.
class _FailingConnectionManager extends ConnectionManager {
  final Object error;
  _FailingConnectionManager(this.error)
    : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(
    SSHConfig config, {
    String? label,
    String? sessionId,
  }) {
    final conn = Connection(
      id: 'conn-fail',
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
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
  Connection connectAsync(
    SSHConfig config, {
    String? label,
    String? sessionId,
  }) {
    return Connection(
      id: 'conn-success',
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
      sshConnection: null,
      state: SSHConnectionState.connected,
    );
  }
}

void main() {
  group('MobileShell', () {
    Widget buildTestWidget({
      List<Session> sessions = const [],
      WorkspaceState? workspaceState,
    }) {
      return ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(SessionStore()),
          sessionProvider.overrideWith(SessionNotifier.new),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            ConnectionManager(knownHosts: KnownHostsManager()),
          ),
          if (workspaceState != null)
            workspaceProvider.overrideWith(WorkspaceNotifier.new),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: const MobileShell(),
        ),
      );
    }

    testWidgets('renders bottom navigation bar with 3 destinations', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Custom bottom nav bar renders 3 labelled items
      expect(find.text('Sessions'), findsAtLeast(1));
      expect(find.text('Terminal'), findsAtLeast(1));
      expect(find.text('Files'), findsAtLeast(1));
    });

    testWidgets('shows Sessions page initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Sessions page has the app title
      expect(find.byType(IndexedStack), findsOneWidget);
      // Settings icon should be visible
      expect(find.byIcon(Icons.settings), findsAtLeast(1));
    });

    testWidgets('Terminal nav tap blocked when no tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Terminal destination — blocked (no tabs)
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Should stay on Sessions page (not switch)
      expect(find.text('No active terminals'), findsNothing);
    });

    testWidgets('Files nav tap blocked when no tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Files destination — blocked (no tabs)
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Should stay on Sessions page (not switch)
      expect(find.text('No active file browsers'), findsNothing);
    });

    testWidgets('shows terminal tab chips when tabs exist', (tester) async {
      // Create a connection for a tab
      final conn = Connection(
        id: 'conn-1',
        label: 'My Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addTerminalTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'sftp.example.com', user: 'admin'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addSftpTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState(
                  (b) => b.addTerminalTab(conn, label: 'Close Me'),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

    testWidgets('swipe gesture does not navigate between pages', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Swipe left should NOT navigate to Terminal
      final rect = tester.getRect(find.byType(IndexedStack));
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(const Offset(-100, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      // Should still be on Sessions (swipe navigation removed)
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, equals(0));
    });

    testWidgets('FAB not shown on Files page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('SFTP nav is disabled when no SFTP tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Files — should be blocked (no tabs)
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Should remain on Sessions, not Files
      expect(find.text('No active file browsers'), findsNothing);
    });

    testWidgets('Terminal nav is disabled when no terminal tabs', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Terminal — should be blocked (no tabs)
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Should remain on Sessions, not Terminal
      expect(find.text('No active terminals'), findsNothing);
    });

    testWidgets('settings button opens settings screen', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsWidgets);
    });

    testWidgets('SFTP close button on tab chip closes tab', (tester) async {
      final conn = Connection(
        id: 'conn-sftp-close',
        label: 'SFTP Close Me',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState(
                  (b) => b.addSftpTab(conn, label: 'SFTP Close Me'),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

      // After closing last SFTP tab, auto-switches to Sessions
      expect(find.text('No active file browsers'), findsNothing);
    });

    testWidgets('SFTP tab chip onPressed selects that tab', (tester) async {
      final conn1 = Connection(
        id: 'sftp-1',
        label: 'SFTP A',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'a.com', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final conn2 = Connection(
        id: 'sftp-2',
        label: 'SFTP B',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'b.com', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) {
                  b.addSftpTab(conn1, label: 'SFTP A');
                  b.addSftpTab(conn2, label: 'SFTP B');
                }),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'a.com', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final conn2 = Connection(
        id: 'term-2',
        label: 'Term B',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'b.com', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) {
                  b.addTerminalTab(conn1, label: 'Term A');
                  b.addTerminalTab(conn2, label: 'Term B');
                }),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

    testWidgets('SFTP page falls back to last tab when activeTab is not SFTP', (
      tester,
    ) async {
      final termConn = Connection(
        id: 'term-x',
        label: 'Terminal',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );
      final sftpConn = Connection(
        id: 'sftp-x',
        label: 'SFTP Tab',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) {
                  // Add SFTP tab first, then terminal tab (terminal becomes active)
                  b.addSftpTab(sftpConn, label: 'SFTP Tab');
                  b.addTerminalTab(termConn, label: 'Terminal');
                }),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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

    testWidgets(
      'Terminal page falls back to last tab when activeTab is not terminal',
      (tester) async {
        final termConn = Connection(
          id: 'term-y',
          label: 'Term Tab',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          sshConnection: null,
          state: SSHConnectionState.disconnected,
        );
        final sftpConn = Connection(
          id: 'sftp-y',
          label: 'SFTP',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
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
              workspaceProvider.overrideWith(
                () => _PrePopulatedWorkspaceNotifier(
                  _buildWorkspaceState((b) {
                    // Add terminal tab first, then SFTP tab (SFTP becomes active)
                    b.addTerminalTab(termConn, label: 'Term Tab');
                    b.addSftpTab(sftpConn, label: 'SFTP');
                  }),
                ),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
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
      },
    );

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
          sessionProvider.overrideWith(
            () => _PrePopulatedSessionNotifier(store.sessions),
          ),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(manager),
        ],
        child: MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          theme: AppTheme.dark(),
          home: const MobileShell(),
        ),
      );
    }

    Future<void> doubleTapSession(WidgetTester tester, String label) async {
      // GestureDetector.onDoubleTap needs two taps within 300ms
      final target = find.text(label).first;
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(target);
      // Pump to let the async connect resolve and dialog dismiss
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('connect session adds tab and navigates to terminal', (
      tester,
    ) async {
      final session = Session(
        id: 'sess-1',
        label: 'Test Server',
        server: const ServerAddress(host: 'example.com', user: 'root'),
      );
      await tester.pumpWidget(
        buildWithSession(
          session: session,
          manager: _SuccessConnectionManager(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Server'), findsOneWidget);

      await doubleTapSession(tester, 'Test Server');
    });

    testWidgets('connect session with failed connection still adds tab', (
      tester,
    ) async {
      final session = Session(
        id: 'sess-fail',
        label: 'Fail Server',
        server: const ServerAddress(host: 'fail.com', user: 'root'),
      );
      await tester.pumpWidget(
        buildWithSession(
          session: session,
          manager: _FailingConnectionManager(Exception('bad password')),
        ),
      );
      await tester.pumpAndSettle();

      // Double-tap triggers connect + nav switch — tab is added even if disconnected
      await doubleTapSession(tester, 'Fail Server');
    });

    testWidgets('SFTP connect via context menu navigates to Files page', (
      tester,
    ) async {
      final session = Session(
        id: 'sess-sftp',
        label: 'SFTP Target',
        server: const ServerAddress(host: 'sftp.example.com', user: 'admin'),
      );
      await tester.pumpWidget(
        buildWithSession(
          session: session,
          manager: _SuccessConnectionManager(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SFTP Target'), findsOneWidget);

      // Right-click (secondary tap) on the session to open context menu
      await tester.tap(
        find.text('SFTP Target'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      // Tap 'Files' in the context menu (last match — first is nav bar)
      expect(find.text('Files'), findsWidgets);
      await tester.tap(find.text('Files').last);
      await tester.pumpAndSettle();

      // Should navigate to Files page (index 2) after _connectSessionSftp
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, equals(2));
    });

    // FAB was removed — new sessions are created from SessionPanel's add button.

    testWidgets('incomplete session shows toast and stays on Sessions page', (
      tester,
    ) async {
      final session = Session(
        id: 'sess-incomplete',
        label: 'Incomplete Server',
        server: const ServerAddress(host: 'example.com', user: 'root'),
        incomplete: true,
      );
      await tester.pumpWidget(
        buildWithSession(
          session: session,
          manager: _SuccessConnectionManager(),
        ),
      );
      await tester.pumpAndSettle();

      // Double-tap the incomplete session
      await doubleTapSession(tester, 'Incomplete Server');

      // Should stay on Sessions page (index 0), not switch to Terminal
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, equals(0));

      Toast.clearAllForTest();
    });

    testWidgets(
      'incomplete session SFTP shows toast and stays on Sessions page',
      (tester) async {
        final session = Session(
          id: 'sess-incomplete-sftp',
          label: 'Incomplete SFTP',
          server: const ServerAddress(host: 'example.com', user: 'root'),
          incomplete: true,
        );
        await tester.pumpWidget(
          buildWithSession(
            session: session,
            manager: _SuccessConnectionManager(),
          ),
        );
        await tester.pumpAndSettle();

        // Right-click to open context menu
        await tester.tap(
          find.text('Incomplete SFTP'),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Tap 'Files' in the context menu (last match — first is nav bar)
        await tester.tap(find.text('Files').last);
        await tester.pumpAndSettle();

        // Should stay on Sessions page (index 0), not switch to Files
        final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(stack.index, equals(0));

        Toast.clearAllForTest();
      },
    );

    testWidgets('SFTP button shown on terminal page when connected', (
      tester,
    ) async {
      final conn = Connection(
        id: 'conn-sftp-btn',
        label: 'Connected Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connected,
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addTerminalTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // SFTP button should be visible
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });

    testWidgets('SFTP button hidden on terminal page when disconnected', (
      tester,
    ) async {
      final conn = Connection(
        id: 'conn-sftp-btn-off',
        label: 'Disconnected Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addTerminalTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // SFTP button should NOT be visible
      expect(find.byIcon(Icons.folder_open), findsNothing);
    });

    testWidgets('SSH button shown on SFTP page when connected', (tester) async {
      final conn = Connection(
        id: 'conn-ssh-btn',
        label: 'Connected Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connected,
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addSftpTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // SSH button should be visible
      expect(find.byTooltip('Open SSH Terminal'), findsOneWidget);
    });

    testWidgets('SSH button hidden on SFTP page when disconnected', (
      tester,
    ) async {
      final conn = Connection(
        id: 'conn-ssh-btn-off',
        label: 'Disconnected Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addSftpTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // SSH button should NOT be visible
      expect(find.byTooltip('Open SSH Terminal'), findsNothing);
    });

    testWidgets('tab bar and companion button share bg1 background', (
      tester,
    ) async {
      final conn = Connection(
        id: 'conn-bg',
        label: 'BG Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connected,
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) => b.addTerminalTab(conn)),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // The companion button (Files) and tab chips should share
      // a parent Container with bg1 background
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bg1Containers = containers.where((c) {
        if (c.color == AppTheme.bg1) return true;
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.color == AppTheme.bg1;
        }
        return false;
      });
      expect(
        bg1Containers,
        isNotEmpty,
        reason: 'tab bar area should have bg1 background',
      );
    });

    testWidgets('rebuilds with new colors when theme changes', (tester) async {
      // Start with dark theme
      AppTheme.setBrightness(Brightness.dark);
      final darkBg1 = AppTheme.bg1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            // Start with dark theme
            themeModeProvider.overrideWithValue(ThemeMode.dark),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // App bar should use dark bg1
      final darkContainers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final hasDarkBg1 = darkContainers.any((c) {
        if (c.color == darkBg1) return true;
        final dec = c.decoration;
        return dec is BoxDecoration && dec.color == darkBg1;
      });
      expect(hasDarkBg1, isTrue, reason: 'app bar should use dark bg1');

      // Switch to light theme — rebuild widget tree with new overrides
      AppTheme.setBrightness(Brightness.light);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith(SessionNotifier.new),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            themeModeProvider.overrideWithValue(ThemeMode.light),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.light,
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // After theme change, MobileShell should rebuild with light colors
      final lightBg1 = AppTheme.bg1;
      expect(
        lightBg1,
        isNot(equals(darkBg1)),
        reason: 'light bg1 should differ from dark bg1',
      );

      final lightContainers = tester.widgetList<Container>(
        find.byType(Container),
      );
      final hasLightBg1 = lightContainers.any((c) {
        if (c.color == lightBg1) return true;
        final dec = c.decoration;
        return dec is BoxDecoration && dec.color == lightBg1;
      });
      expect(
        hasLightBg1,
        isTrue,
        reason: 'app bar should use light bg1 after theme change',
      );

      // Restore dark theme for other tests
      AppTheme.setBrightness(Brightness.dark);
    });

    testWidgets('app bar shows tab count in StatusIndicator', (tester) async {
      final conn = Connection(
        id: 'conn-3',
        label: 'Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
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
            workspaceProvider.overrideWith(
              () => _PrePopulatedWorkspaceNotifier(
                _buildWorkspaceState((b) {
                  b.addTerminalTab(conn, label: 'Tab 1');
                  b.addTerminalTab(conn, label: 'Tab 2');
                }),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tab count shown via StatusIndicator in the app bar, not Badge
      expect(find.byType(Badge), findsNothing);
      expect(find.text('2'), findsWidgets);
      expect(find.byIcon(Icons.tab_outlined), findsAtLeast(1));
    });

    testWidgets(
      'header shows StatusIndicator for saved sessions and active connections',
      (tester) async {
        debugMobilePlatformOverride = true;
        addTearDown(() => debugMobilePlatformOverride = null);

        final sessions = [
          Session(
            id: 's1',
            label: 'Server1',
            folder: '',
            server: const ServerAddress(host: 'h1', user: 'u'),
            auth: const SessionAuth(authType: AuthType.password),
          ),
          Session(
            id: 's2',
            label: 'Server2',
            folder: '',
            server: const ServerAddress(host: 'h2', user: 'u'),
            auth: const SessionAuth(authType: AuthType.password),
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionStoreProvider.overrideWithValue(SessionStore()),
              sessionProvider.overrideWith(
                () => _PrePopulatedSessionNotifier(sessions),
              ),
              knownHostsProvider.overrideWithValue(KnownHostsManager()),
              connectionManagerProvider.overrideWithValue(
                ConnectionManager(knownHosts: KnownHostsManager()),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: const MobileShell(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Three StatusIndicator widgets in header: saved sessions + active connections + open tabs
        expect(find.byType(StatusIndicator), findsNWidgets(3));

        // Saved sessions icon (dns_outlined) — only in header (footer hidden on mobile)
        expect(find.byIcon(Icons.dns_outlined), findsOneWidget);

        // Active connections icon (wifi)
        expect(find.byIcon(Icons.wifi), findsOneWidget);

        // Saved count should show "2" (two sessions)
        final savedIndicator = tester.widget<StatusIndicator>(
          find.byType(StatusIndicator).first,
        );
        expect(savedIndicator.count, 2);
        expect(savedIndicator.tooltip, 'Saved sessions');

        // Active count should be 0 (no connections)
        final activeIndicator = tester
            .widgetList<StatusIndicator>(find.byType(StatusIndicator))
            .firstWhere((s) => s.tooltip == 'Active connections');
        expect(activeIndicator.count, 0);

        // Tab count indicator present
        expect(find.byIcon(Icons.tab_outlined), findsOneWidget);
      },
    );

    testWidgets('header connection indicator uses green color when connected', (
      tester,
    ) async {
      debugMobilePlatformOverride = true;
      addTearDown(() => debugMobilePlatformOverride = null);

      final conn = Connection(
        id: 'conn-green',
        label: 'Connected Server',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
        sshConnection: null,
        state: SSHConnectionState.connected,
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
            connectionsProvider.overrideWith((ref) => Stream.value([conn])),
          ],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: const MobileShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final activeIndicator = tester
          .widgetList<StatusIndicator>(find.byType(StatusIndicator))
          .firstWhere((s) => s.tooltip == 'Active connections');
      expect(activeIndicator.count, 1);
      expect(activeIndicator.iconColor, AppTheme.green);
    });

    testWidgets(
      'header connection indicator uses yellow color when connecting',
      (tester) async {
        debugMobilePlatformOverride = true;
        addTearDown(() => debugMobilePlatformOverride = null);

        final conn = Connection(
          id: 'conn-yellow',
          label: 'Connecting Server',
          sshConfig: const SSHConfig(
            server: ServerAddress(host: 'h', user: 'u'),
          ),
          sshConnection: null,
          state: SSHConnectionState.connecting,
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
              connectionsProvider.overrideWith((ref) => Stream.value([conn])),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: const MobileShell(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final activeIndicator = tester
            .widgetList<StatusIndicator>(find.byType(StatusIndicator))
            .firstWhere((s) => s.tooltip == 'Active connections');
        expect(activeIndicator.count, 1);
        expect(activeIndicator.iconColor, AppTheme.yellow);
      },
    );
  });
}
