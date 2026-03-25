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
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  group('MobileShell', () {
    Widget buildTestWidget({
      List<Session> sessions = const [],
      TabState? tabState,
    }) {
      return ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(SessionStore()),
          sessionProvider.overrideWith((ref) {
            final notifier = SessionNotifier(ref.watch(sessionStoreProvider));
            return notifier;
          }),
          knownHostsProvider.overrideWithValue(KnownHostsManager()),
          connectionManagerProvider.overrideWithValue(
            ConnectionManager(knownHosts: KnownHostsManager()),
          ),
          if (tabState != null)
            tabProvider.overrideWith((ref) {
              final notifier = TabNotifier();
              return notifier;
            }),
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
        sshConfig: const SSHConfig(host: 'example.com', user: 'root'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith((ref) {
              return SessionNotifier(ref.watch(sessionStoreProvider));
            }),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith((ref) {
              final notifier = TabNotifier();
              // Pre-add a terminal tab
              notifier.addTerminalTab(conn);
              return notifier;
            }),
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
        sshConfig: const SSHConfig(host: 'sftp.example.com', user: 'admin'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith((ref) {
              return SessionNotifier(ref.watch(sessionStoreProvider));
            }),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith((ref) {
              final notifier = TabNotifier();
              notifier.addSftpTab(conn);
              return notifier;
            }),
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

    testWidgets('badge shows terminal tab count', (tester) async {
      final conn = Connection(
        id: 'conn-3',
        label: 'Server',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStoreProvider.overrideWithValue(SessionStore()),
            sessionProvider.overrideWith((ref) {
              return SessionNotifier(ref.watch(sessionStoreProvider));
            }),
            knownHostsProvider.overrideWithValue(KnownHostsManager()),
            connectionManagerProvider.overrideWithValue(
              ConnectionManager(knownHosts: KnownHostsManager()),
            ),
            tabProvider.overrideWith((ref) {
              final notifier = TabNotifier();
              notifier.addTerminalTab(conn, label: 'Tab 1');
              notifier.addTerminalTab(conn, label: 'Tab 2');
              return notifier;
            }),
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
