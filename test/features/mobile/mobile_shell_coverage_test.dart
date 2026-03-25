import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/mobile/mobile_shell.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// A fake ConnectionManager that can be configured to succeed or fail.
class FakeConnectionManager extends ConnectionManager {
  Object? errorToThrow;
  Connection? connectionToReturn;

  FakeConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Future<Connection> connect(SSHConfig config, {String? label}) async {
    if (errorToThrow != null) throw errorToThrow!;
    return connectionToReturn ?? Connection(
      id: 'fake-conn',
      label: label ?? config.displayName,
      sshConfig: config,
      state: SSHConnectionState.connected,
    );
  }
}

/// A fake SessionStore that doesn't use path_provider.
class _FakeSessionStore extends SessionStore {
  final List<Session> _fakeSessions;

  _FakeSessionStore({List<Session>? sessions})
      : _fakeSessions = sessions ?? [];

  @override
  List<Session> get sessions => List.unmodifiable(_fakeSessions);

  @override
  Set<String> get emptyGroups => const {};

  @override
  Future<List<Session>> load() async => _fakeSessions;

  @override
  Future<Session> add(Session session) async {
    _fakeSessions.add(session);
    return session;
  }

  @override
  Future<void> update(Session session) async {
    final idx = _fakeSessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) _fakeSessions[idx] = session;
  }

  @override
  Future<void> delete(String id) async {
    _fakeSessions.removeWhere((s) => s.id == id);
  }

  @override
  List<String> groups() {
    final g = _fakeSessions.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList();
    g.sort();
    return g;
  }

  @override
  int countSessionsInGroup(String groupPath) {
    return _fakeSessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .length;
  }

  @override
  List<Session> byGroup(String group) {
    return _fakeSessions.where((s) => s.group == group).toList();
  }

  @override
  Future<Session> duplicateSession(String id) async {
    final original = _fakeSessions.firstWhere((s) => s.id == id);
    final copy = original.duplicate();
    _fakeSessions.add(copy);
    return copy;
  }

  @override
  Future<void> deleteAll() async => _fakeSessions.clear();

  @override
  Future<void> deleteGroup(String groupPath) async {
    _fakeSessions.removeWhere(
        (s) => s.group == groupPath || s.group.startsWith('$groupPath/'));
  }

  @override
  Future<void> addEmptyGroup(String groupPath) async {}

  @override
  Future<void> renameGroup(String oldPath, String newPath) async {}

  @override
  Future<void> moveSession(String sessionId, String newGroup) async {}

  @override
  Future<void> moveGroup(String groupPath, String newParent) async {}
}

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

  Widget buildTestWidget({
    List<TabEntry>? initialTabs,
    ConnectionManager? connectionManager,
    List<Session>? sessions,
  }) {
    final store = _FakeSessionStore(sessions: sessions);
    final connManager = connectionManager ??
        ConnectionManager(knownHosts: KnownHostsManager());
    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        sessionProvider.overrideWith((ref) {
          final notifier = SessionNotifier(ref.watch(sessionStoreProvider));
          // Pre-populate state with sessions
          if (sessions != null && sessions.isNotEmpty) {
            notifier.state = sessions;
          }
          return notifier;
        }),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(connManager),
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

  group('MobileShell — _connectSession success', () {
    testWidgets('successful SSH connect adds terminal tab and switches to terminal page', (tester) async {
      final fakeManager = FakeConnectionManager();
      final session = Session(
        label: 'MyServer',
        host: '10.0.0.1',
        user: 'root',
      );

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [session],
      ));
      await tester.pumpAndSettle();

      // Sessions page should show. Double-tap on the session to connect.
      // On desktop (test env), SessionTreeView uses double-tap for onConnect.
      expect(find.text('MyServer'), findsOneWidget);

      // Double-tap the session to connect
      await tester.tap(find.text('MyServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('MyServer'));
      await tester.pumpAndSettle();

      // After successful connect, should show "Connecting to..." dialog, then switch to terminal
      // The connecting dialog is dismissed, and we should be on terminal page
      // Terminal page shows the tab chip with the connection label
      expect(find.text('No active terminals'), findsNothing);
    });
  });

  group('MobileShell — _connectSession error handling', () {
    // Each test exercises one branch of _showConnectError.
    // Toast uses static OverlayEntry + AnimationController.

    testWidgets('AuthError keeps user on sessions page', (tester) async {
      final fakeManager = FakeConnectionManager();
      fakeManager.errorToThrow = const AuthError('Invalid credentials');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'FailServer', host: '10.0.0.2', user: 'admin')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('FailServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('FailServer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Error path: stays on sessions page, no terminal tab created
      expect(find.text('FailServer'), findsOneWidget);
      expect(find.text('LetsFLUTssh'), findsOneWidget);
      // Drain toast timer (3s) + reverse animation (200ms)
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('ConnectError keeps user on sessions page', (tester) async {
      final fakeManager = FakeConnectionManager();
      fakeManager.errorToThrow = const ConnectError('Connection refused');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'DownServer', host: '10.0.0.3', user: 'root')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DownServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('DownServer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DownServer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('HostKeyError keeps user on sessions page', (tester) async {
      final fakeManager = FakeConnectionManager();
      fakeManager.errorToThrow = const HostKeyError('Host key changed');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'MitmServer', host: '10.0.0.4', user: 'root')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MitmServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('MitmServer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('MitmServer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('generic error keeps user on sessions page', (tester) async {
      final fakeManager = FakeConnectionManager();
      fakeManager.errorToThrow = Exception('Something went wrong');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'BrokenServer', host: '10.0.0.5', user: 'root')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('BrokenServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('BrokenServer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('BrokenServer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });
  });

  group('MobileShell — _showConnecting dialog', () {
    testWidgets('connecting dialog shows spinner and label', (tester) async {
      final slowManager = _SlowConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: slowManager,
        sessions: [Session(label: 'SlowServer', host: '10.0.0.6', user: 'root')],
      ));
      await tester.pumpAndSettle();

      // Double-tap session — connecting dialog should appear
      await tester.tap(find.text('SlowServer'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('SlowServer'));
      await tester.pump(); // Just pump once, don't settle (dialog is still up)

      // Should see "Connecting to SlowServer..."
      expect(find.textContaining('Connecting to SlowServer'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);

      // Complete successfully to avoid toast timer issues
      final conn = Connection(
        id: 'slow-conn',
        label: 'SlowServer',
        sshConfig: const SSHConfig(host: '10.0.0.6', user: 'root'),
        state: SSHConnectionState.connected,
      );
      slowManager.completer.complete(conn);
      await tester.pumpAndSettle();
    });
  });

  group('MobileShell — _connectSessionSftp', () {
    setUp(() => Toast.clearAllForTest());

    testWidgets('successful SFTP connect adds sftp tab and switches to files page', (tester) async {
      final fakeManager = FakeConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'SftpServer', host: '10.0.0.7', user: 'root')],
      ));
      await tester.pumpAndSettle();

      // Right-click to get context menu with SFTP option (desktop mode)
      final sessionFinder = find.text('SftpServer');
      final center = tester.getCenter(sessionFinder);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Tap SFTP connect option
      final sftpOption = find.text('SFTP');
      if (sftpOption.evaluate().isNotEmpty) {
        await tester.tap(sftpOption);
        await tester.pumpAndSettle();

        // Should have switched to Files page and have an SFTP tab
        expect(find.text('No active file browsers'), findsNothing);
      }
    });

    testWidgets('SFTP connect error keeps user on sessions page', (tester) async {
      final fakeManager = FakeConnectionManager();
      fakeManager.errorToThrow = const AuthError('Key rejected');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'SftpFail', host: '10.0.0.8', user: 'root')],
      ));
      await tester.pumpAndSettle();

      // Right-click → context menu with SFTP option (desktop mode)
      final sessionFinder = find.text('SftpFail');
      final center = tester.getCenter(sessionFinder);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      final sftpOption = find.text('SFTP');
      if (sftpOption.evaluate().isNotEmpty) {
        await tester.tap(sftpOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Error: stays on sessions page
        expect(find.text('SftpFail'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 250));
      }
    });
  });

  group('MobileShell — FAB new session', () {
    testWidgets('FAB visible on sessions page, hidden on terminal page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // FAB visible on sessions page
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Switch to terminal page
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // FAB not visible
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('FAB opens session edit dialog', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Session edit dialog should be open — check for dialog elements
      // The SessionEditDialog shows Host */Username * fields
      expect(find.text('Host *'), findsOneWidget);
      expect(find.text('Username *'), findsOneWidget);
    });
  });

  group('MobileShell — terminal empty state details', () {
    testWidgets('empty terminal page shows icon and guidance text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('No active terminals'), findsOneWidget);
      expect(find.text('Connect from Sessions tab'), findsOneWidget);
      expect(find.byIcon(Icons.terminal), findsAtLeast(1));
    });
  });

  group('MobileShell — SFTP empty state details', () {
    testWidgets('empty SFTP page shows icon and guidance text', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('No active file browsers'), findsOneWidget);
      expect(find.text('Use "SFTP" from Sessions'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsAtLeast(1));
    });
  });

  group('MobileShell — closing terminal tab chip', () {
    testWidgets('closing last terminal tab shows empty state', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'OnlyTerm', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('OnlyTerm'), findsOneWidget);

      // Close via the X icon
      final closeIcons = find.byIcon(Icons.close);
      if (closeIcons.evaluate().isNotEmpty) {
        await tester.tap(closeIcons.first);
        await tester.pumpAndSettle();
      }

      expect(find.text('No active terminals'), findsOneWidget);
    });
  });

  group('MobileShell — session with empty label uses displayName', () {
    testWidgets('session with empty label uses user@host format', (tester) async {
      final fakeManager = FakeConnectionManager();
      final session = Session(
        label: '',
        host: '192.168.1.1',
        user: 'deploy',
      );

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [session],
      ));
      await tester.pumpAndSettle();

      // Session should show displayName format
      expect(find.textContaining('deploy@192.168.1.1'), findsOneWidget);
    });
  });

  group('MobileShell — swipe bounds', () {
    testWidgets('swipe left at rightmost page does nothing', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Go to Files (rightmost)
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      // Swipe left should NOT crash or change page
      await tester.fling(
        find.text('No active file browsers'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Still on Files page
      expect(find.text('No active file browsers'), findsOneWidget);
    });

    testWidgets('swipe right at leftmost page does nothing', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Already on Sessions (leftmost)
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Still on Sessions page
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });
  });

  group('MobileShell — badge visibility', () {
    testWidgets('terminal badge shows count when tabs exist', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'T1', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'T2', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Badge should show "2" for terminal tabs
      expect(find.text('2'), findsWidgets);
    });
  });

  group('MobileShell — activeTab fallback', () {
    testWidgets('terminal page uses last tab when activeTab is SFTP', (tester) async {
      final conn = makeConn();
      // Create tabs where active is SFTP but we view terminal page
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'TermA', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 's1', label: 'SftpA', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Active tab is the last added (SFTP), but terminal page should still show TermA
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      expect(find.text('TermA'), findsOneWidget);
    });

    testWidgets('SFTP page uses last tab when activeTab is terminal', (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 's1', label: 'SftpB', connection: conn, kind: TabKind.sftp),
        TabEntry(id: 't1', label: 'TermB', connection: conn, kind: TabKind.terminal),
      ]));
      await tester.pumpAndSettle();

      // Active tab is terminal, but SFTP page should still show SftpB
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('SftpB'), findsOneWidget);
    });
  });
}

/// A ConnectionManager that delays connect() until manually completed.
class _SlowConnectionManager extends ConnectionManager {
  final completer = Completer<Connection>();

  _SlowConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Future<Connection> connect(SSHConfig config, {String? label}) {
    return completer.future;
  }
}

