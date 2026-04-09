import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_client.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

@GenerateNiceMocks([
  MockSpec<SSHSocket>(),
  MockSpec<SSHClient>(),
  MockSpec<SSHSession>(),
  MockSpec<KnownHostsManager>(),
])
import 'ssh_connection_test.mocks.dart';

/// Default test config.
const _config = SSHConfig(
  server: ServerAddress(host: 'example.com', port: 22, user: 'root'),
  auth: SshAuth(password: 'secret'),
);

void main() {
  late MockSSHSocket mockSocket;
  late MockSSHClient mockClient;
  late MockKnownHostsManager mockKnownHosts;

  setUp(() {
    mockSocket = MockSSHSocket();
    mockClient = MockSSHClient();
    mockKnownHosts = MockKnownHostsManager();
  });

  /// Helper — creates an SSHConnection wired to mock factories.
  ///
  /// [authError] — if non-null, `client.authenticated` will fail with this.
  /// [doneFuture] — controls when `client.done` completes.
  /// [triggerHostKey] — if true, synchronously invokes onVerifyHostKey in the
  ///   client factory so that [_wrapVerifyCallback] is exercised.
  SSHConnection createConnection({
    SSHConfig config = _config,
    Object? authError,
    Future<void>? doneFuture,
    bool triggerHostKey = true,
  }) {
    when(mockClient.authenticated).thenAnswer((_) {
      if (authError != null) return Future.error(authError);
      return Future.value();
    });
    when(
      mockClient.done,
    ).thenAnswer((_) => doneFuture ?? Completer<void>().future);

    return SSHConnection(
      config: config,
      knownHosts: mockKnownHosts,
      socketFactory: (host, port, {timeout}) async => mockSocket,
      clientFactory:
          (
            socket, {
            required username,
            onPasswordRequest,
            identities,
            onVerifyHostKey,
            keepAliveInterval,
          }) {
            if (triggerHostKey && onVerifyHostKey != null) {
              // Synchronous call so the callback runs before auth completes.
              onVerifyHostKey('ssh-rsa', Uint8List.fromList([1, 2, 3]));
            }
            return mockClient;
          },
    );
  }

  // ---------------------------------------------------------------------------
  // connect() — success path
  // ---------------------------------------------------------------------------
  group('connect', () {
    test('succeeds with password auth', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);
      when(mockKnownHosts.load()).thenAnswer((_) async {});

      final conn = createConnection();
      final steps = <ConnectionStep>[];
      await conn.connect(onProgress: steps.add);

      expect(conn.isConnected, isTrue);
      expect(conn.client, mockClient);
      expect(
        steps.where((s) => s.status == StepStatus.success).length,
        greaterThanOrEqualTo(1),
      );
    });

    test('throws ConnectError when already disposed', () async {
      final conn = createConnection();
      conn.disconnect();

      expect(
        () => conn.connect(),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('reports progress steps in order', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection();
      final steps = <ConnectionStep>[];
      await conn.connect(onProgress: steps.add);

      // Should have socket connect in-progress → success at minimum.
      expect(
        steps.any(
          (s) =>
              s.phase == ConnectionPhase.socketConnect &&
              s.status == StepStatus.inProgress,
        ),
        isTrue,
      );
      expect(
        steps.any(
          (s) =>
              s.phase == ConnectionPhase.socketConnect &&
              s.status == StepStatus.success,
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // connect() — socket failure
  // ---------------------------------------------------------------------------
  group('connect — socket failure', () {
    test('throws ConnectError on socket failure', () async {
      final conn = SSHConnection(
        config: _config,
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async =>
            throw const SocketException('Connection refused'),
      );

      final steps = <ConnectionStep>[];
      expect(
        () => conn.connect(onProgress: steps.add),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.message,
            'message',
            contains('Failed to connect'),
          ),
        ),
      );
    });

    test('reports socket failure progress step', () async {
      final conn = SSHConnection(
        config: _config,
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async =>
            throw const SocketException('Refused'),
      );

      final steps = <ConnectionStep>[];
      try {
        await conn.connect(onProgress: steps.add);
      } on ConnectError {
        // expected
      }

      expect(
        steps.any(
          (s) =>
              s.phase == ConnectionPhase.socketConnect &&
              s.status == StepStatus.failed,
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // connect() — auth failure
  // ---------------------------------------------------------------------------
  group('connect — authentication failure', () {
    test('throws AuthError on SSHAuthFailError', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection(
        authError: SSHAuthFailError('Bad password'),
      );

      expect(
        () => conn.connect(),
        throwsA(
          isA<AuthError>().having(
            (e) => e.message,
            'message',
            contains('Authentication failed'),
          ),
        ),
      );
    });

    test('throws AuthError on SSHAuthAbortError', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection(authError: SSHAuthAbortError('Aborted'));

      expect(
        () => conn.connect(),
        throwsA(
          isA<AuthError>().having(
            (e) => e.message,
            'message',
            contains('Authentication aborted'),
          ),
        ),
      );
    });

    test(
      'throws HostKeyError when host key rejected + SSHAuthAbortError',
      () async {
        // The host key verification rejects — sets _hostKeyRejected = true.
        when(
          mockKnownHosts.verify(any, any, any, any),
        ).thenAnswer((_) async => false);

        // Auth abort follows host key rejection.
        final conn = SSHConnection(
          config: _config,
          knownHosts: mockKnownHosts,
          socketFactory: (host, port, {timeout}) async => mockSocket,
          clientFactory:
              (
                socket, {
                required username,
                onPasswordRequest,
                identities,
                onVerifyHostKey,
                keepAliveInterval,
              }) {
                // Trigger host key verification synchronously before returning client.
                if (onVerifyHostKey != null) {
                  onVerifyHostKey('ssh-rsa', Uint8List.fromList([1, 2, 3]));
                }
                when(
                  mockClient.authenticated,
                ).thenAnswer((_) => Future.error(SSHAuthAbortError('Aborted')));
                when(
                  mockClient.done,
                ).thenAnswer((_) => Completer<void>().future);
                return mockClient;
              },
        );

        expect(() => conn.connect(), throwsA(isA<HostKeyError>()));
      },
    );

    test(
      'throws HostKeyError when host key rejected + generic error',
      () async {
        when(
          mockKnownHosts.verify(any, any, any, any),
        ).thenAnswer((_) async => false);

        final conn = SSHConnection(
          config: _config,
          knownHosts: mockKnownHosts,
          socketFactory: (host, port, {timeout}) async => mockSocket,
          clientFactory:
              (
                socket, {
                required username,
                onPasswordRequest,
                identities,
                onVerifyHostKey,
                keepAliveInterval,
              }) {
                if (onVerifyHostKey != null) {
                  onVerifyHostKey('ssh-rsa', Uint8List.fromList([1, 2, 3]));
                }
                when(
                  mockClient.authenticated,
                ).thenAnswer((_) => Future.error(Exception('generic')));
                when(
                  mockClient.done,
                ).thenAnswer((_) => Completer<void>().future);
                return mockClient;
              },
        );

        expect(() => conn.connect(), throwsA(isA<HostKeyError>()));
      },
    );

    test('throws ConnectError on generic exception', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection(authError: Exception('something broke'));

      expect(
        () => conn.connect(),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.message,
            'message',
            contains('Connection failed'),
          ),
        ),
      );
    });

    test('reports auth failure progress step', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection(authError: SSHAuthFailError('Bad'));

      final steps = <ConnectionStep>[];
      try {
        await conn.connect(onProgress: steps.add);
      } on AuthError {
        // expected
      }

      expect(
        steps.any(
          (s) =>
              s.phase == ConnectionPhase.authenticate &&
              s.status == StepStatus.failed,
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Host key verification callback
  // ---------------------------------------------------------------------------
  group('host key verification', () {
    test(
      'emits hostKeyVerify success and authenticate inProgress on accept',
      () async {
        when(
          mockKnownHosts.verify(any, any, any, any),
        ).thenAnswer((_) async => true);

        final conn = createConnection();
        final steps = <ConnectionStep>[];
        await conn.connect(onProgress: steps.add);

        expect(
          steps.any(
            (s) =>
                s.phase == ConnectionPhase.hostKeyVerify &&
                s.status == StepStatus.success,
          ),
          isTrue,
        );
        expect(
          steps.any(
            (s) =>
                s.phase == ConnectionPhase.authenticate &&
                s.status == StepStatus.inProgress,
          ),
          isTrue,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // openShell()
  // ---------------------------------------------------------------------------
  group('openShell', () {
    test('returns SSHSession on success', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final mockSession = MockSSHSession();
      when(
        mockClient.shell(pty: anyNamed('pty')),
      ).thenAnswer((_) async => mockSession);

      final conn = createConnection();
      await conn.connect();
      final session = await conn.openShell(80, 24);

      expect(session, mockSession);
    });

    test('throws ConnectError when not connected', () async {
      final conn = createConnection();

      expect(
        () => conn.openShell(80, 24),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.message,
            'message',
            contains('Not connected'),
          ),
        ),
      );
    });

    test('throws ConnectError on shell open failure', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);
      when(
        mockClient.shell(pty: anyNamed('pty')),
      ).thenThrow(Exception('shell failed'));

      final conn = createConnection();
      await conn.connect();

      expect(
        () => conn.openShell(80, 24),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.message,
            'message',
            contains('Failed to open shell'),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // resizeTerminal()
  // ---------------------------------------------------------------------------
  group('resizeTerminal', () {
    test('delegates to shell when available', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final mockSession = MockSSHSession();
      when(
        mockClient.shell(pty: anyNamed('pty')),
      ).thenAnswer((_) async => mockSession);

      final conn = createConnection();
      await conn.connect();
      await conn.openShell(80, 24);

      conn.resizeTerminal(120, 40);
      verify(mockSession.resizeTerminal(120, 40)).called(1);
    });

    test('does nothing when no shell session', () {
      final conn = createConnection();
      // Should not throw.
      conn.resizeTerminal(80, 24);
    });
  });

  // ---------------------------------------------------------------------------
  // disconnect()
  // ---------------------------------------------------------------------------
  group('disconnect', () {
    test('cleans up client and shell', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final mockSession = MockSSHSession();
      when(
        mockClient.shell(pty: anyNamed('pty')),
      ).thenAnswer((_) async => mockSession);

      final conn = createConnection();
      await conn.connect();
      await conn.openShell(80, 24);

      conn.disconnect();
      expect(conn.isConnected, isFalse);
      verify(mockSession.close()).called(1);
      verify(mockClient.close()).called(1);
    });

    test('sets isConnected to false', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection();
      await conn.connect();
      expect(conn.isConnected, isTrue);

      conn.disconnect();
      expect(conn.isConnected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // onDisconnect callback
  // ---------------------------------------------------------------------------
  group('onDisconnect', () {
    test('fires when client.done completes normally', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final doneCompleter = Completer<void>();
      final conn = createConnection(doneFuture: doneCompleter.future);
      var disconnectCalled = false;
      conn.onDisconnect = () => disconnectCalled = true;

      await conn.connect();
      expect(disconnectCalled, isFalse);

      doneCompleter.complete();
      // Allow microtask to run.
      await Future<void>.delayed(Duration.zero);
      expect(disconnectCalled, isTrue);
    });

    test('fires when client.done completes with error', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final doneCompleter = Completer<void>();
      final conn = createConnection(doneFuture: doneCompleter.future);
      var disconnectCalled = false;
      conn.onDisconnect = () => disconnectCalled = true;

      await conn.connect();
      doneCompleter.completeError(Exception('connection lost'));
      await Future<void>.delayed(Duration.zero);
      expect(disconnectCalled, isTrue);
    });

    test('does not fire after manual disconnect', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final doneCompleter = Completer<void>();
      final conn = createConnection(doneFuture: doneCompleter.future);
      var disconnectCount = 0;
      conn.onDisconnect = () => disconnectCount++;

      await conn.connect();
      conn.disconnect(); // sets _disposed = true

      doneCompleter.complete();
      await Future<void>.delayed(Duration.zero);
      // onDisconnect should NOT be called again since already disposed.
      expect(disconnectCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // _onPasswordRequest
  // ---------------------------------------------------------------------------
  group('password auth', () {
    test('provides password when configured', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      String? capturedPassword;
      final conn = SSHConnection(
        config: _config,
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async => mockSocket,
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              capturedPassword = onPasswordRequest?.call();
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      await conn.connect();
      expect(capturedPassword, 'secret');
    });

    test('returns null when no password', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      const noPassConfig = SSHConfig(
        server: ServerAddress(host: 'example.com', user: 'root'),
      );

      String? capturedPassword;
      final conn = SSHConnection(
        config: noPassConfig,
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async => mockSocket,
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              capturedPassword = onPasswordRequest?.call();
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      await conn.connect();
      expect(capturedPassword, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // _buildIdentities — key file auth
  // ---------------------------------------------------------------------------
  group('key file auth', () {
    test(
      'throws ConnectError wrapping AuthError when key file missing',
      () async {
        when(
          mockKnownHosts.verify(any, any, any, any),
        ).thenAnswer((_) async => true);

        const keyConfig = SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
          auth: SshAuth(keyPath: '/nonexistent/key'),
        );

        final conn = SSHConnection(
          config: keyConfig,
          knownHosts: mockKnownHosts,
          socketFactory: (host, port, {timeout}) async => mockSocket,
          clientFactory:
              (
                socket, {
                required username,
                onPasswordRequest,
                identities,
                onVerifyHostKey,
                keepAliveInterval,
              }) {
                when(
                  mockClient.authenticated,
                ).thenAnswer((_) => Future.value());
                when(
                  mockClient.done,
                ).thenAnswer((_) => Completer<void>().future);
                return mockClient;
              },
        );

        // _tryKeyFileAuth throws AuthError, caught by generic catch in
        // _authenticateClient and wrapped as ConnectError.
        expect(
          () => conn.connect(),
          throwsA(
            isA<ConnectError>().having(
              (e) => e.cause,
              'cause',
              isA<AuthError>().having(
                (a) => a.message,
                'message',
                contains('Failed to load SSH key file'),
              ),
            ),
          ),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // _buildIdentities — key text auth
  // ---------------------------------------------------------------------------
  group('key text auth', () {
    test('throws ConnectError wrapping AuthError on invalid PEM', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      const pemConfig = SSHConfig(
        server: ServerAddress(host: 'example.com', user: 'root'),
        auth: SshAuth(keyData: 'not-valid-pem-data'),
      );

      final conn = SSHConnection(
        config: pemConfig,
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async => mockSocket,
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      expect(
        () => conn.connect(),
        throwsA(
          isA<ConnectError>().having(
            (e) => e.cause,
            'cause',
            isA<AuthError>().having(
              (a) => a.message,
              'message',
              contains('Failed to parse PEM key data'),
            ),
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // keepAlive configuration
  // ---------------------------------------------------------------------------
  group('keepAlive configuration', () {
    test('passes keepAliveInterval when keepAliveSec > 0', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      Duration? capturedKeepAlive;
      final conn = SSHConnection(
        config: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
          keepAliveSec: 60,
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async => mockSocket,
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              capturedKeepAlive = keepAliveInterval;
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      await conn.connect();
      expect(capturedKeepAlive, const Duration(seconds: 60));
    });

    test('passes null keepAliveInterval when keepAliveSec is 0', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      Duration? capturedKeepAlive;
      final conn = SSHConnection(
        config: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
          keepAliveSec: 0,
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async => mockSocket,
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              capturedKeepAlive = keepAliveInterval;
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      await conn.connect();
      expect(capturedKeepAlive, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // isConnected getter
  // ---------------------------------------------------------------------------
  group('isConnected', () {
    test('returns false before connect', () {
      final conn = createConnection();
      expect(conn.isConnected, isFalse);
    });

    test('returns false after disconnect', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection();
      await conn.connect();
      conn.disconnect();
      expect(conn.isConnected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // client getter
  // ---------------------------------------------------------------------------
  group('client getter', () {
    test('returns null before connect', () {
      final conn = createConnection();
      expect(conn.client, isNull);
    });

    test('returns client after connect', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      final conn = createConnection();
      await conn.connect();
      expect(conn.client, mockClient);
    });
  });

  // ---------------------------------------------------------------------------
  // connect timeout configuration
  // ---------------------------------------------------------------------------
  group('timeout configuration', () {
    test('passes timeout from config to socket factory', () async {
      when(
        mockKnownHosts.verify(any, any, any, any),
      ).thenAnswer((_) async => true);

      Duration? capturedTimeout;
      final conn = SSHConnection(
        config: const SSHConfig(
          server: ServerAddress(host: 'example.com', user: 'root'),
          timeoutSec: 30,
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (host, port, {timeout}) async {
          capturedTimeout = timeout;
          return mockSocket;
        },
        clientFactory:
            (
              socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) {
              when(mockClient.authenticated).thenAnswer((_) => Future.value());
              when(mockClient.done).thenAnswer((_) => Completer<void>().future);
              return mockClient;
            },
      );

      await conn.connect();
      expect(capturedTimeout, const Duration(seconds: 30));
    });
  });
}
