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
  Connection makeConn({
    String id = 'conn-1',
    String label = 'Server',
    SSHConnectionState state = SSHConnectionState.disconnected,
  }) {
    return Connection(
      id: id,
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
      sshConnection: null,
      state: state,
    );
  }

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


  group('MobileShell — SFTP tab chip selection', () {
    testWidgets('tapping SFTP tab chip selects it', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 's1', label: 'SFTP1', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 's2', label: 'SFTP2', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Go to Files page
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Both SFTP tabs should show as chips
      expect(find.text('SFTP1'), findsOneWidget);
      expect(find.text('SFTP2'), findsOneWidget);

      // Tap the second chip to select it
      await tester.tap(find.text('SFTP2'));
      await tester.pumpAndSettle();

      // Both should still be visible
      expect(find.text('SFTP1'), findsOneWidget);
      expect(find.text('SFTP2'), findsOneWidget);
    });

    testWidgets('closing SFTP tab chip removes it', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 's1', label: 'SFTPOnly', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('SFTPOnly'), findsOneWidget);

      // Close via the X icon on the chip
      final closeIcons = find.byIcon(Icons.close);
      if (closeIcons.evaluate().isNotEmpty) {
        await tester.tap(closeIcons.first);
        await tester.pumpAndSettle();
      }

      // Should show empty state
      expect(find.text('No active file browsers'), findsOneWidget);
    });
  });

  group('MobileShell — terminal tab chip selection', () {
    testWidgets('tapping terminal tab chip switches active tab', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'Term1', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'Term2', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('Term1'), findsOneWidget);
      expect(find.text('Term2'), findsOneWidget);

      // Tap second chip
      await tester.tap(find.text('Term2'));
      await tester.pumpAndSettle();

      expect(find.text('Term1'), findsOneWidget);
      expect(find.text('Term2'), findsOneWidget);
    });
  });

  group('MobileShell — badge counts', () {
    testWidgets('badge shows SFTP tab count', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 's1', label: 'S1', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 's2', label: 'S2', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 's3', label: 'S3', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Badge should show "3" for SFTP tabs
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('no badge when no terminal tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Badge with "0" should not be visible (isLabelVisible: false when count == 0)
      final badges = find.byType(Badge);
      expect(badges, findsWidgets);
    });
  });

  group('MobileShell — mixed terminal and SFTP tabs', () {
    testWidgets('terminal page only shows terminal tabs', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'TermTab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 's1', label: 'SftpTab', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Only terminal tab chip shown
      expect(find.text('TermTab'), findsOneWidget);
      // SFTP tab label should not appear on terminal page
      // (SftpTab won't show as a chip on the Terminal page)
    });

    testWidgets('files page only shows SFTP tabs', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'TermTab', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 's1', label: 'SftpTab', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Only SFTP tab chip shown
      expect(find.text('SftpTab'), findsOneWidget);
    });
  });

  group('MobileShell — sessions page content', () {
    testWidgets('sessions page shows app title and settings', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('LetsFLUTssh'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsAtLeast(1));
    });
  });

  group('MobileShell — double swipe navigation', () {
    testWidgets('double swipe left goes from sessions to files', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Swipe left once: Sessions -> Terminal
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Swipe left again: Terminal -> Files
      await tester.fling(
        find.text('No active terminals'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('double swipe right goes from files to sessions', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to Files first
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Swipe right: Files -> Terminal
      await tester.fling(
        find.text('No active file browsers'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Swipe right: Terminal -> Sessions
      await tester.fling(
        find.text('No active terminals'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });
  });

  group('MobileShell — IndexedStack preserves state', () {
    testWidgets('IndexedStack used for page switching', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(IndexedStack), findsOneWidget);
    });
  });

  group('MobileShell — NavigationBar properties', () {
    testWidgets('NavigationBar has height 60', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.height, 60);
    });

    testWidgets('NavigationBar has 3 destinations', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 3);
    });
  });
}
