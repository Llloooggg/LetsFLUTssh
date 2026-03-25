import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_shell.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  Widget buildTestWidget({List<TabEntry>? initialTabs}) {
    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(SessionStore()),
        sessionProvider.overrideWith((ref) {
          return SessionNotifier(ref.watch(sessionStoreProvider));
        }),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(
          ConnectionManager(knownHosts: KnownHostsManager()),
        ),
        if (initialTabs != null)
          tabProvider.overrideWith((ref) {
            final notifier = TabNotifier();
            for (final tab in initialTabs) {
              if (tab.kind == TabKind.terminal) {
                notifier.addTerminalTab(tab.connection, label: tab.label);
              } else {
                notifier.addSftpTab(tab.connection, label: tab.label);
              }
            }
            return notifier;
          }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const MobileShell(),
      ),
    );
  }

  group('MobileShell — FAB opens new session dialog', () {
    testWidgets('FAB on sessions page opens session edit dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Session edit dialog should appear
      expect(find.text('Host *'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });

  group('MobileShell — swipe navigation edge cases', () {
    testWidgets('swipe left from sessions goes to terminal', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Start on Sessions page
      expect(find.text('LetsFLUTssh'), findsOneWidget);

      // Swipe left
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('No active terminals'), findsOneWidget);
    });

    testWidgets('swipe left from terminal goes to files', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Go to Terminal
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Swipe left to go to Files
      await tester.fling(
        find.text('No active terminals'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('swipe right from files goes to terminal', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Go to Files
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Swipe right
      await tester.fling(
        find.text('No active file browsers'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('No active terminals'), findsOneWidget);
    });

    testWidgets('swipe right from sessions does nothing (already at leftmost)', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Swipe right at leftmost - should stay on sessions
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });

    testWidgets('swipe left from files does nothing (already at rightmost)', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      await tester.fling(
        find.text('No active file browsers'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('No active file browsers'), findsOneWidget);
    });
  });

  group('MobileShell — terminal page with multiple tabs', () {
    testWidgets('multiple terminal tabs show as chips', (tester) async {
      final conn = Connection(
        id: 'c1',
        label: 'Server',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'Tab1', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Tab2', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('Tab1'), findsOneWidget);
      expect(find.text('Tab2'), findsOneWidget);
    });
  });

  group('MobileShell — SFTP page with multiple tabs', () {
    testWidgets('multiple SFTP tabs show as chips', (tester) async {
      final conn = Connection(
        id: 'c1',
        label: 'Server',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 's1', label: 'SFTP1', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 's2', label: 'SFTP2', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('SFTP1'), findsOneWidget);
      expect(find.text('SFTP2'), findsOneWidget);
    });
  });

  group('MobileShell — NavigationBar destination selection', () {
    testWidgets('tapping Sessions nav shows sessions page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Go to terminal first
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Go back to sessions
      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();

      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
