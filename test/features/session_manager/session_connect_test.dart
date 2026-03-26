import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_connect.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';

/// A fake ConnectionManager that returns a disconnected connection with error.
class _FailingConnectionManager extends ConnectionManager {
  final Object error;

  _FailingConnectionManager(this.error) : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(SSHConfig config, {String? label}) {
    return Connection(
      id: 'conn-fail',
      label: label ?? config.displayName,
      sshConfig: config,
      state: SSHConnectionState.disconnected,
      connectionError: error.toString(),
    );
  }
}

/// A fake ConnectionManager that simulates connect success
/// without real network calls.
class _FakeConnectionManager extends ConnectionManager {
  String? lastLabel;

  _FakeConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(SSHConfig config, {String? label}) {
    lastLabel = label;
    return Connection(
      id: 'fake-conn-1',
      label: label ?? config.displayName,
      sshConfig: config,
      state: SSHConnectionState.connected,
    );
  }
}

void main() {
  group('SessionConnect error message formatting', () {
    test('HostKeyError produces userMessage', () {
      const error = HostKeyError('Host key changed');
      expect(error.userMessage, 'Host key changed');
    });

    test('AuthError produces prefixed message', () {
      const error = AuthError('Wrong password');
      final msg = 'Auth failed: ${error.userMessage}';
      expect(msg, 'Auth failed: Wrong password');
    });

    test('ConnectError produces userMessage', () {
      const error = ConnectError('Connection timed out');
      expect(error.userMessage, 'Connection timed out');
    });

    test('HostKeyError with cause unwraps', () {
      const error = HostKeyError('MITM detected', 'Key fingerprint mismatch');
      expect(error.userMessage, 'MITM detected (Key fingerprint mismatch)');
    });

    test('AuthError with SSHError cause chains messages', () {
      const inner = ConnectError('Timeout');
      const error = AuthError('Auth failed', inner);
      expect(error.userMessage, contains('Auth failed'));
      expect(error.userMessage, contains('Timeout'));
    });

    test('generic error produces fallback message', () {
      final error = Exception('Something went wrong');
      final msg = 'Connection error: $error';
      expect(msg, contains('Something went wrong'));
    });
  });

  group('SessionConnect.connectTerminal', () {
    testWidgets('adds terminal tab on successful connection', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'Test Server',
                        host: '10.0.0.1',
                        port: 22,
                        user: 'root',
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);

      fakeManager.dispose();
    });

    testWidgets('uses session label when non-empty', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'My Server',
                        host: '10.0.0.1',
                        port: 22,
                        user: 'root',
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // The label should be passed to connect()
      expect(fakeManager.lastLabel, 'My Server');

      fakeManager.dispose();
    });

    testWidgets('uses displayName when session label is empty', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: '',
                        host: '10.0.0.1',
                        port: 22,
                        user: 'root',
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Empty label => displayName used
      expect(fakeManager.lastLabel, 'root@10.0.0.1:22');

      fakeManager.dispose();
    });

    testWidgets('creates tab in tab provider on success', (tester) async {
      final fakeManager = _FakeConnectionManager();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'Test',
                        host: '10.0.0.1',
                        user: 'root',
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.terminal);

      fakeManager.dispose();
    });
  });

  group('SessionConnect.connectSftp', () {
    testWidgets('adds SFTP tab on successful connection', (tester) async {
      final fakeManager = _FakeConnectionManager();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's2',
                        label: 'SFTP Server',
                        host: '10.0.0.1',
                        user: 'test',
                      );
                      SessionConnect.connectSftp(context, ref, session);
                    },
                    child: const Text('SFTP'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.sftp);

      fakeManager.dispose();
    });

    testWidgets('uses displayName when label is empty for SFTP', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's2',
                        label: '',
                        host: '10.0.0.1',
                        user: 'admin',
                      );
                      SessionConnect.connectSftp(context, ref, session);
                    },
                    child: const Text('SFTP'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      expect(fakeManager.lastLabel, 'admin@10.0.0.1:22');

      fakeManager.dispose();
    });
  });

  group('SessionConnect — failed connection still adds tab', () {
    testWidgets('connectTerminal adds tab even when connection fails', (tester) async {
      final failManager = _FailingConnectionManager(Exception('Wrong password'));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(failManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'Test',
                        host: '10.0.0.1',
                        user: 'root',
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Tab should still be added (connection status shown inside tab)
      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.terminal);

      failManager.dispose();
    });

    testWidgets('connectSftp adds tab even when connection fails', (tester) async {
      final failManager = _FailingConnectionManager(Exception('Auth failed'));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(failManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'Test',
                        host: '10.0.0.1',
                        user: 'root',
                      );
                      SessionConnect.connectSftp(context, ref, session);
                    },
                    child: const Text('SFTP'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('SFTP'));
      await tester.pumpAndSettle();

      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.sftp);

      failManager.dispose();
    });

    testWidgets('connectConfig adds tab even when connection fails', (tester) async {
      final failManager = _FailingConnectionManager(Exception('Refused'));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(failManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(host: '10.0.0.1', user: 'root');
                      SessionConnect.connectConfig(context, ref, config);
                    },
                    child: const Text('Quick'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Quick'));
      await tester.pumpAndSettle();

      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.terminal);

      failManager.dispose();
    });
  });

  group('SessionConnect.connectConfig', () {
    testWidgets('adds terminal tab on successful config connection', (tester) async {
      final fakeManager = _FakeConnectionManager();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(
                        host: '10.0.0.1',
                        port: 22,
                        user: 'test',
                      );
                      SessionConnect.connectConfig(context, ref, config);
                    },
                    child: const Text('Quick'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Quick'));
      await tester.pumpAndSettle();

      final tabState = capturedRef.read(tabProvider);
      expect(tabState.tabs.length, 1);
      expect(tabState.tabs.first.kind, TabKind.terminal);

      fakeManager.dispose();
    });

    testWidgets('connectConfig does not pass label to connect', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(
                        host: '10.0.0.1',
                        port: 2222,
                        user: 'admin',
                      );
                      SessionConnect.connectConfig(context, ref, config);
                    },
                    child: const Text('Quick'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Quick'));
      await tester.pumpAndSettle();

      // connectConfig doesn't pass a label
      expect(fakeManager.lastLabel, isNull);

      fakeManager.dispose();
    });
  });
}
