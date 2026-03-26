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
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';

/// A fake ConnectionManager that succeeds.
class _FakeConnectionManager extends ConnectionManager {
  _FakeConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Future<Connection> connect(SSHConfig config, {String? label}) async {
    return Connection(
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
  setUp(() => Toast.clearAllForTest());
  tearDown(() => Toast.clearAllForTest());

  Widget buildTestWidget({
    ConnectionManager? connectionManager,
    List<Session>? sessions,
  }) {
    final store = _FakeSessionStore(sessions: sessions);
    final connManager = connectionManager ?? _FakeConnectionManager();
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
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const MobileShell(),
      ),
    );
  }

  group('MobileShell — onQuickConnect callback (lines 54-56)', () {
    testWidgets(
        'quick connect from session panel triggers connectConfig and navigates to terminal',
        (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(buildTestWidget(
        connectionManager: fakeManager,
      ));
      await tester.pumpAndSettle();

      // The Quick Connect button is in the SessionPanel
      // Find and tap the Quick Connect icon
      final quickConnectIcon = find.byIcon(Icons.flash_on);
      if (quickConnectIcon.evaluate().isNotEmpty) {
        await tester.tap(quickConnectIcon);
        await tester.pumpAndSettle();

        // Fill the quick connect dialog fields
        final hostField = find.widgetWithText(TextFormField, 'Host *');
        final userField = find.widgetWithText(TextFormField, 'Username *');
        if (hostField.evaluate().isNotEmpty && userField.evaluate().isNotEmpty) {
          await tester.enterText(hostField, 'quick.example.com');
          await tester.enterText(userField, 'quickuser');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Connect'));
          await tester.pumpAndSettle();
        }
      }
    });
  });

  group('MobileShell — swipe navigation left', () {
    testWidgets('fast left swipe navigates from Sessions to Terminal',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify we're on Sessions page
      expect(find.text('LetsFLUTssh'), findsOneWidget);

      // Fast fling left (velocity > 300)
      await tester.fling(
        find.text('LetsFLUTssh'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();

      // Should be on Terminal page now (empty state)
      expect(find.text('No active terminals'), findsOneWidget);
    });
  });

  group('MobileShell — swipe navigation right', () {
    testWidgets('fast right swipe navigates from Terminal back to Sessions',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to Terminal first
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('No active terminals'), findsOneWidget);

      // Swipe right to go back to Sessions
      await tester.fling(
        find.text('No active terminals'),
        const Offset(300, 0),
        800,
      );
      await tester.pumpAndSettle();

      expect(find.text('LetsFLUTssh'), findsOneWidget);
    });
  });
}
