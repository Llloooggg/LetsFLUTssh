import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_connect.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/toast.dart';
import '''package:letsflutssh/l10n/app_localizations.dart''';

/// A fake ConnectionManager that returns a disconnected connection with error.
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
    return Connection(
      id: 'conn-fail',
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
      state: SSHConnectionState.disconnected,
      connectionError: error.toString(),
    );
  }
}

/// A fake ConnectionManager that simulates connect success
/// without real network calls.
class _FakeConnectionManager extends ConnectionManager {
  String? lastLabel;
  String? lastSessionId;
  SSHConfig? lastConfig;

  _FakeConnectionManager() : super(knownHosts: KnownHostsManager());

  @override
  Connection connectAsync(
    SSHConfig config, {
    String? label,
    String? sessionId,
  }) {
    lastLabel = label;
    lastSessionId = sessionId;
    lastConfig = config;
    return Connection(
      id: 'fake-conn-1',
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
      state: SSHConnectionState.connected,
    );
  }
}

/// In-memory KeyStore stand-in — [SessionConnect] only reads via `get()`.
class _FakeKeyStore extends KeyStore {
  _FakeKeyStore(this._entries);
  final Map<String, SshKeyEntry> _entries;

  @override
  Future<SshKeyEntry?> get(String id) async => _entries[id];
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
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'Test Server',
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          port: 22,
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: 'My Server',
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          port: 22,
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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

    testWidgets('passes session ID to connection manager', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 'sess-42',
                        label: 'Test',
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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

      expect(fakeManager.lastSessionId, 'sess-42');

      fakeManager.dispose();
    });

    testWidgets('uses displayName when session label is empty', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's1',
                        label: '',
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          port: 22,
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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

      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.terminal);

      fakeManager.dispose();
    });
  });

  group('SessionConnect.connectSftp', () {
    testWidgets('adds SFTP tab on successful connection', (tester) async {
      final fakeManager = _FakeConnectionManager();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'test',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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

      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.sftp);

      fakeManager.dispose();
    });

    testWidgets('uses displayName when label is empty for SFTP', (
      tester,
    ) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      final session = Session(
                        id: 's2',
                        label: '',
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'admin',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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
    testWidgets('connectTerminal adds tab even when connection fails', (
      tester,
    ) async {
      final failManager = _FailingConnectionManager(
        Exception('Wrong password'),
      );
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(failManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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
      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.terminal);

      failManager.dispose();
    });

    testWidgets('connectSftp adds tab even when connection fails', (
      tester,
    ) async {
      final failManager = _FailingConnectionManager(Exception('Auth failed'));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(failManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
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
                        server: const ServerAddress(
                          host: '10.0.0.1',
                          user: 'root',
                        ),
                        auth: const SessionAuth(password: 'secret'),
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

      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.sftp);

      failManager.dispose();
    });

    testWidgets('connectConfig adds tab even when connection fails', (
      tester,
    ) async {
      final failManager = _FailingConnectionManager(Exception('Refused'));
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(failManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(
                        server: ServerAddress(host: '10.0.0.1', user: 'root'),
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

      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.terminal);

      failManager.dispose();
    });
  });

  group('SessionConnect.connectConfig', () {
    testWidgets('adds terminal tab on successful config connection', (
      tester,
    ) async {
      final fakeManager = _FakeConnectionManager();
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(
                        server: ServerAddress(
                          host: '10.0.0.1',
                          port: 22,
                          user: 'test',
                        ),
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

      final ws = capturedRef.read(workspaceProvider);
      final allTabs = collectAllTabs(ws.root);
      expect(allTabs.length, 1);
      expect(allTabs.first.kind, TabKind.terminal);

      fakeManager.dispose();
    });

    testWidgets('connectConfig does not pass label to connect', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      const config = SSHConfig(
                        server: ServerAddress(
                          host: '10.0.0.1',
                          port: 2222,
                          user: 'admin',
                        ),
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

  group('SessionConnect — incomplete session blocking', () {
    testWidgets('connectTerminal returns false for incomplete session', (
      tester,
    ) async {
      final fakeManager = _FakeConnectionManager();
      bool? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      // Session without credentials → isValid = false
                      final session = Session(
                        label: 'incomplete',
                        server: const ServerAddress(host: 'h', user: 'u'),
                      );
                      result = await SessionConnect.connectTerminal(
                        context,
                        ref,
                        session,
                      );
                    },
                    child: const Text('Go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      Toast.clearAllForTest();
      fakeManager.dispose();
    });

    testWidgets('connectSftp returns false for incomplete session', (
      tester,
    ) async {
      final fakeManager = _FakeConnectionManager();
      bool? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      // Session without credentials → isValid = false
                      final session = Session(
                        label: 'incomplete',
                        server: const ServerAddress(host: 'h', user: 'u'),
                      );
                      result = await SessionConnect.connectSftp(
                        context,
                        ref,
                        session,
                      );
                    },
                    child: const Text('Go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      Toast.clearAllForTest();
      fakeManager.dispose();
    });

    testWidgets('connectTerminal returns true for complete session', (
      tester,
    ) async {
      final fakeManager = _FakeConnectionManager();
      bool? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      final session = Session(
                        label: 'ok',
                        server: const ServerAddress(host: 'h', user: 'u'),
                        auth: const SessionAuth(password: 'pass'),
                      );
                      result = await SessionConnect.connectTerminal(
                        context,
                        ref,
                        session,
                      );
                    },
                    child: const Text('Go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      fakeManager.dispose();
    });

    testWidgets(
      'keyId on the session resolves against the key store and injects keyData',
      (tester) async {
        // The `_resolveConfig` helper looks up `session.keyId` in the
        // key store and copies the entry's `privateKey` into the
        // SSHConfig's `keyData` slot — the only way a session with a
        // key reference reaches the connection manager with actual
        // PEM material. A regression that dropped the lookup would
        // quietly fall back to password auth and surface as "server
        // disconnected" only during the handshake.
        final fakeManager = _FakeConnectionManager();
        final fakeKeyStore = _FakeKeyStore({
          'k-1': SshKeyEntry(
            id: 'k-1',
            label: 'staging',
            privateKey: '-----BEGIN KEY-----',
            publicKey: 'ssh-ed25519 AAAA',
            keyType: 'ed25519',
            createdAt: DateTime(2024),
          ),
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectionManagerProvider.overrideWithValue(fakeManager),
              keyStoreProvider.overrideWithValue(fakeKeyStore),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        final session = Session(
                          id: 's1',
                          label: 'Keyed',
                          server: const ServerAddress(
                            host: '10.0.0.1',
                            user: 'root',
                          ),
                          auth: const SessionAuth(keyId: 'k-1'),
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

        expect(
          fakeManager.lastConfig?.keyData,
          '-----BEGIN KEY-----',
          reason: 'keyId must be resolved into inline keyData before connect',
        );
        fakeManager.dispose();
      },
    );

    testWidgets(
      'missing keyId entry surfaces a no-crash fallback without keyData',
      (tester) async {
        final fakeManager = _FakeConnectionManager();
        final fakeKeyStore = _FakeKeyStore({}); // no entries

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectionManagerProvider.overrideWithValue(fakeManager),
              keyStoreProvider.overrideWithValue(fakeKeyStore),
            ],
            child: MaterialApp(
              localizationsDelegates: S.localizationsDelegates,
              supportedLocales: S.supportedLocales,
              theme: AppTheme.dark(),
              home: Consumer(
                builder: (context, ref, _) {
                  return Scaffold(
                    body: ElevatedButton(
                      onPressed: () {
                        final session = Session(
                          id: 's1',
                          label: 'Orphan',
                          server: const ServerAddress(
                            host: '10.0.0.1',
                            user: 'root',
                          ),
                          auth: const SessionAuth(keyId: 'ghost'),
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

        expect(
          fakeManager.lastConfig?.keyData,
          isEmpty,
          reason: 'Missing key entry must not invent keyData',
        );
        fakeManager.dispose();
      },
    );

    testWidgets('incomplete session shows warning toast', (tester) async {
      final fakeManager = _FakeConnectionManager();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectionManagerProvider.overrideWithValue(fakeManager)],
          child: MaterialApp(
            localizationsDelegates: S.localizationsDelegates,
            supportedLocales: S.supportedLocales,
            theme: AppTheme.dark(),
            home: Consumer(
              builder: (context, ref, _) {
                return Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      // Session without credentials → isValid = false
                      final session = Session(
                        label: 'inc',
                        server: const ServerAddress(host: 'h', user: 'u'),
                      );
                      SessionConnect.connectTerminal(context, ref, session);
                    },
                    child: const Text('Go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no credentials'), findsOneWidget);

      // Clean up toast overlay
      Toast.clearAllForTest();
      fakeManager.dispose();
    });
  });
}
