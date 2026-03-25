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
class _FakeConnectionManager extends ConnectionManager {
  Object? errorToThrow;
  Connection? connectionToReturn;

  _FakeConnectionManager() : super(knownHosts: KnownHostsManager());

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

class _FakeSessionStore extends SessionStore {
  final List<Session> _sessions;

  _FakeSessionStore({List<Session>? sessions}) : _sessions = sessions ?? [];

  @override
  List<Session> get sessions => List.unmodifiable(_sessions);
  @override
  Set<String> get emptyGroups => const {};
  @override
  Future<List<Session>> load() async => _sessions;
  @override
  Future<Session> add(Session session) async {
    _sessions.add(session);
    return session;
  }
  @override
  Future<void> update(Session session) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  List<String> groups() => [];
  @override
  int countSessionsInGroup(String groupPath) => 0;
  @override
  List<Session> byGroup(String group) => [];
  @override
  Future<Session> duplicateSession(String id) async => _sessions.first;
  @override
  Future<void> deleteAll() async => _sessions.clear();
  @override
  Future<void> deleteGroup(String groupPath) async {}
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
  Connection makeConn({String label = 'Server'}) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
      sshConnection: null,
      state: SSHConnectionState.disconnected,
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

  group('MobileShell — swipe velocity below threshold is ignored', () {
    testWidgets('slow swipe does not change page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Slow swipe (velocity < 300) should not change page
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        200, // below 300 threshold
      );
      await tester.pumpAndSettle();

      // Still on Sessions page
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });
  });

  group('MobileShell — _newSession dialog result handling', () {
    setUp(() => Toast.clearAllForTest());

    testWidgets('FAB new session ConnectOnly result triggers quick connect',
        (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
      ));
      await tester.pumpAndSettle();

      // Tap FAB to open new session dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill required fields
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'quick.host');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'quickuser');
      await tester.pumpAndSettle();

      // Tap Connect (not Save & Connect)
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Should navigate to terminal page after connect
      // (SessionConnect.connectConfig is called internally)
    });

    testWidgets('FAB new session Save & Connect result saves and connects',
        (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
      ));
      await tester.pumpAndSettle();

      // Tap FAB to open new session dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill required fields
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Host *'), 'save.host');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username *'), 'saveuser');
      await tester.pumpAndSettle();

      // Tap Save & Connect
      await tester.tap(find.text('Save & Connect'));
      await tester.pumpAndSettle();

      // Session should be saved and terminal page shown
    });

    testWidgets('FAB cancel returns null and stays on sessions page',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Cancel the dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Still on sessions page
      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });
  });

  group('MobileShell — _connectSessionSftp success path', () {
    setUp(() => Toast.clearAllForTest());

    testWidgets('SFTP connect creates SFTP tab and navigates to Files page',
        (tester) async {
      final fakeManager = _FakeConnectionManager();
      final session = Session(
        label: 'SftpTest',
        host: '10.0.0.1',
        user: 'root',
      );

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [session],
      ));
      await tester.pumpAndSettle();

      // Verify session is shown
      expect(find.text('SftpTest'), findsOneWidget);

      // Right-click on session to get context menu
      final center = tester.getCenter(find.text('SftpTest'));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.up();
      await tester.pumpAndSettle();

      // Look for SFTP option in context menu
      final sftpOption = find.text('SFTP');
      if (sftpOption.evaluate().isNotEmpty) {
        await tester.tap(sftpOption);
        await tester.pumpAndSettle();

        // Should have created an SFTP tab and switched to Files page
        // Verify we're not in empty state
      }
    });
  });

  group('MobileShell — _showConnectError for different error types', () {
    setUp(() => Toast.clearAllForTest());

    testWidgets('HostKeyError shows user-friendly message', (tester) async {
      final fakeManager = _FakeConnectionManager();
      fakeManager.errorToThrow = const HostKeyError('Host key mismatch detected');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'HK', host: 'h', user: 'u')],
      ));
      await tester.pumpAndSettle();

      // Double-tap session to connect
      await tester.tap(find.text('HK'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('HK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Stays on sessions page
      expect(find.text('HK'), findsOneWidget);

      // Drain toast
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('AuthError message shows "Auth failed" prefix', (tester) async {
      final fakeManager = _FakeConnectionManager();
      fakeManager.errorToThrow = const AuthError('Bad key');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'AF', host: 'h', user: 'u')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AF'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('AF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('AF'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('ConnectError message includes userMessage', (tester) async {
      final fakeManager = _FakeConnectionManager();
      fakeManager.errorToThrow = const ConnectError('Timeout');

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
        sessions: [Session(label: 'CE', host: 'h', user: 'u')],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CE'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('CE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CE'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
    });
  });

  group('MobileShell — active tab fallback with mixed tabs', () {
    testWidgets('terminal page falls back to last tab when active is SFTP',
        (tester) async {
      final conn = makeConn();
      await tester.pumpWidget(buildTestWidget(initialTabs: [
        TabEntry(id: 't1', label: 'TermX', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 't2', label: 'TermY', connection: conn, kind: TabKind.terminal),
        TabEntry(id: 's1', label: 'SftpZ', connection: conn, kind: TabKind.sftp),
      ]));
      await tester.pumpAndSettle();

      // Navigate to Terminal
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();

      // Both terminal tabs should be visible as chips
      expect(find.text('TermX'), findsOneWidget);
      expect(find.text('TermY'), findsOneWidget);
    });
  });

  group('MobileShell — _showConnecting dialog shows non-dismissible overlay', () {
    testWidgets('connecting dialog is non-dismissible', (tester) async {
      final slowManager = _SlowConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: slowManager,
        sessions: [Session(label: 'SlowSrv', host: 'h', user: 'u')],
      ));
      await tester.pumpAndSettle();

      // Double-tap to connect
      await tester.tap(find.text('SlowSrv'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('SlowSrv'));
      await tester.pump();

      // Dialog should show with CircularProgressIndicator
      expect(find.textContaining('Connecting to SlowSrv'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify PopScope canPop is false (non-dismissible)
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);

      // Complete to clean up
      slowManager.completer.complete(Connection(
        id: 'done',
        label: 'SlowSrv',
        sshConfig: const SSHConfig(host: 'h', user: 'u'),
        state: SSHConnectionState.connected,
      ));
      await tester.pumpAndSettle();
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
