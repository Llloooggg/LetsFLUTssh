import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_client.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<SSHClient>(),
  MockSpec<SSHSocket>(),
  MockSpec<SSHSession>(),
  MockSpec<KnownHostsManager>(),
])
import 'ssh_connection_test.mocks.dart';

void main() {
  setUpAll(() async {
    // Generate a test SSH key at runtime to avoid hardcoded secrets in source.
    final tempDir = await Directory.systemTemp.createTemp('keygen_');
    final keyPath = '${tempDir.path}/test_key';
    final result = await Process.run(
      'ssh-keygen', ['-t', 'ed25519', '-f', keyPath, '-N', '', '-q'],
    );
    if (result.exitCode == 0) {
      _testEd25519PrivateKey = await File(keyPath).readAsString();
    } else {
      // Fallback: generate RSA key (ssh-keygen always available on Linux)
      await Process.run(
        'ssh-keygen', ['-t', 'rsa', '-b', '2048', '-f', keyPath, '-N', '', '-q'],
      );
      _testEd25519PrivateKey = await File(keyPath).readAsString();
    }
    await tempDir.delete(recursive: true);
  });

  group('SSHConnection — construction and state', () {
    test('isConnected is false before connect', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      expect(conn.isConnected, isFalse);
      expect(conn.client, isNull);
    });

    test('config is accessible', () {
      const config = SSHConfig(
        host: 'test.server',
        port: 2222,
        user: 'admin',
        password: 'secret',
        keyPath: '/home/user/.ssh/id_rsa',
        keyData: 'PEM-DATA',
        passphrase: 'phrase',
      );
      final conn = SSHConnection(
        config: config,
        knownHosts: KnownHostsManager(),
      );
      expect(conn.config.host, 'test.server');
      expect(conn.config.port, 2222);
      expect(conn.config.user, 'admin');
      expect(conn.config.password, 'secret');
    });

    test('disconnect on fresh connection does not throw', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      conn.disconnect();
      expect(conn.isConnected, isFalse);
    });

    test('connect to disposed connection throws ConnectError', () async {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      conn.disconnect(); // sets _disposed = true
      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.message,
          'message',
          'Connection disposed',
        )),
      );
    });

    test('openShell throws when not connected', () async {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      expect(
        () => conn.openShell(80, 24),
        throwsA(isA<ConnectError>().having(
          (e) => e.message,
          'message',
          'Not connected',
        )),
      );
    });

    test('resizeTerminal on null shell does not throw', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      conn.resizeTerminal(120, 40);
    });

    test('onDisconnect callback can be set', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      bool called = false;
      conn.onDisconnect = () => called = true;
      expect(called, isFalse);
    });

    test('multiple disconnect calls do not throw', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      conn.disconnect();
      conn.disconnect();
      conn.disconnect();
      expect(conn.isConnected, isFalse);
    });

    test('isConnected is false after disconnect', () {
      final conn = SSHConnection(
        config: const SSHConfig(host: 'example.com', user: 'root'),
        knownHosts: KnownHostsManager(),
      );
      conn.disconnect();
      expect(conn.isConnected, isFalse);
      expect(conn.client, isNull);
    });
  });

  group('SSHConnection.connect — with injectable factories', () {
    late MockSSHSocket mockSocket;
    late MockSSHClient mockClient;
    late MockKnownHostsManager mockKnownHosts;

    setUp(() {
      mockSocket = MockSSHSocket();
      mockClient = MockSSHClient();
      mockKnownHosts = MockKnownHostsManager();
    });

    /// Helper: creates SSHConnection with mock factories.
    SSHConnection buildConnection({
      SSHConfig config = const SSHConfig(
        host: 'test.host',
        user: 'testuser',
        password: 'testpass',
      ),
      Future<SSHSocket> Function(String, int, {Duration? timeout})?
          socketFactory,
      SSHClient Function(
        SSHSocket, {
        required String username,
        String? Function()? onPasswordRequest,
        List<SSHKeyPair>? identities,
        FutureOr<bool> Function(String, Uint8List)? onVerifyHostKey,
        Duration? keepAliveInterval,
      })? clientFactory,
      KnownHostsManager? knownHosts,
    }) {
      return SSHConnection(
        config: config,
        knownHosts: knownHosts ?? mockKnownHosts,
        socketFactory: socketFactory ?? (host, port, {timeout}) async => mockSocket,
        clientFactory: clientFactory ??
            (socket, {
              required username,
              onPasswordRequest,
              identities,
              onVerifyHostKey,
              keepAliveInterval,
            }) =>
                mockClient,
      );
    }

    test('successful connect sets isConnected and client', () async {
      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection();
      await conn.connect();

      expect(conn.isConnected, isTrue);
      expect(conn.client, mockClient);
    });

    test('connect passes correct host and port to socket factory', () async {
      String? capturedHost;
      int? capturedPort;
      Duration? capturedTimeout;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(
          host: 'myhost.com',
          port: 3333,
          user: 'admin',
          timeoutSec: 15,
        ),
        socketFactory: (host, port, {timeout}) async {
          capturedHost = host;
          capturedPort = port;
          capturedTimeout = timeout;
          return mockSocket;
        },
      );

      await conn.connect();

      expect(capturedHost, 'myhost.com');
      expect(capturedPort, 3333);
      expect(capturedTimeout, const Duration(seconds: 15));
    });

    test('connect passes correct username to client factory', () async {
      String? capturedUsername;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(host: 'h', user: 'myuser', password: 'p'),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedUsername = username;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedUsername, 'myuser');
    });

    test('connect passes password callback that returns password', () async {
      String? Function()? capturedPasswordCb;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(
          host: 'h',
          user: 'u',
          password: 'secretpass',
        ),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedPasswordCb = onPasswordRequest;
          return mockClient;
        },
      );

      await conn.connect();

      expect(capturedPasswordCb, isNotNull);
      expect(capturedPasswordCb!(), 'secretpass');
    });

    test('password callback returns null when password is empty', () async {
      String? Function()? capturedPasswordCb;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(host: 'h', user: 'u', password: ''),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedPasswordCb = onPasswordRequest;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedPasswordCb!(), isNull);
    });

    test('connect passes keepAliveInterval when keepAliveSec > 0', () async {
      Duration? capturedKeepAlive;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(host: 'h', user: 'u', keepAliveSec: 45),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedKeepAlive = keepAliveInterval;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedKeepAlive, const Duration(seconds: 45));
    });

    test('connect passes null keepAliveInterval when keepAliveSec is 0',
        () async {
      Duration? capturedKeepAlive = const Duration(seconds: 999); // sentinel

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(host: 'h', user: 'u', keepAliveSec: 0),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedKeepAlive = keepAliveInterval;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedKeepAlive, isNull);
    });

    test('socket factory failure throws ConnectError', () async {
      final conn = buildConnection(
        socketFactory: (host, port, {timeout}) async {
          throw const SocketException('Connection refused');
        },
      );

      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.message,
          'message',
          contains('Failed to connect'),
        )),
      );
    });

    test('SSHAuthFailError during auth throws AuthError', () async {
      when(mockClient.authenticated)
          .thenThrow(SSHAuthFailError('all methods failed'));

      final conn = buildConnection();

      expect(
        () => conn.connect(),
        throwsA(isA<AuthError>().having(
          (e) => e.message,
          'message',
          contains('Authentication failed'),
        )),
      );
    });

    test('SSHAuthAbortError during auth throws AuthError', () async {
      when(mockClient.authenticated)
          .thenThrow(SSHAuthAbortError('aborted'));

      final conn = buildConnection();

      expect(
        () => conn.connect(),
        throwsA(isA<AuthError>().having(
          (e) => e.message,
          'message',
          'Authentication aborted',
        )),
      );
    });

    test('SSHAuthAbortError with host key rejected throws HostKeyError',
        () async {
      FutureOr<bool> Function(String, Uint8List)? capturedVerify;

      final conn = buildConnection(
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedVerify = onVerifyHostKey;
          return mockClient;
        },
      );

      when(mockKnownHosts.verify(any, any, any, any))
          .thenAnswer((_) async => false);

      // Simulate: dartssh2 calls onVerifyHostKey, it rejects, then auth aborts
      when(mockClient.authenticated).thenAnswer((_) async {
        if (capturedVerify != null) {
          await capturedVerify!('ssh-rsa', Uint8List.fromList([1, 2, 3]));
        }
        throw SSHAuthAbortError('host key rejected');
      });

      expect(
        () => conn.connect(),
        throwsA(isA<HostKeyError>().having(
          (e) => e.message,
          'message',
          contains('Host key rejected'),
        )),
      );
    });

    test(
        'generic error during auth with host key rejected throws HostKeyError',
        () async {
      FutureOr<bool> Function(String, Uint8List)? capturedVerify;

      final conn = buildConnection(
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedVerify = onVerifyHostKey;
          return mockClient;
        },
      );

      when(mockKnownHosts.verify(any, any, any, any))
          .thenAnswer((_) async => false);

      when(mockClient.authenticated).thenAnswer((_) async {
        if (capturedVerify != null) {
          await capturedVerify!(
              'ssh-ed25519', Uint8List.fromList([4, 5, 6]));
        }
        throw Exception('some error');
      });

      expect(
        () => conn.connect(),
        throwsA(isA<HostKeyError>()),
      );
    });

    test(
        'generic error during auth without host key rejection throws ConnectError',
        () async {
      when(mockClient.authenticated).thenThrow(Exception('unexpected'));

      final conn = buildConnection();

      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.message,
          'message',
          contains('Connection failed'),
        )),
      );
    });

    test('connect cleans up client on auth failure', () async {
      when(mockClient.authenticated)
          .thenThrow(SSHAuthFailError('fail'));

      final conn = buildConnection();

      try {
        await conn.connect();
      } catch (_) {}

      expect(conn.client, isNull);
      expect(conn.isConnected, isFalse);
    });

    test('disconnect callback fires when client.done completes', () async {
      final doneCompleter = Completer<void>();
      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => doneCompleter.future);

      final conn = buildConnection();

      bool disconnected = false;
      conn.onDisconnect = () => disconnected = true;

      await conn.connect();
      expect(disconnected, isFalse);

      doneCompleter.complete();
      await Future.delayed(Duration.zero);

      expect(disconnected, isTrue);
    });

    test('disconnect callback does not fire after manual disconnect', () async {
      final doneCompleter = Completer<void>();
      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => doneCompleter.future);

      final conn = buildConnection();

      bool disconnected = false;
      conn.onDisconnect = () => disconnected = true;

      await conn.connect();
      conn.disconnect();

      doneCompleter.complete();
      await Future.delayed(Duration.zero);

      expect(disconnected, isFalse);
    });

    test('host key verification delegates to KnownHostsManager', () async {
      FutureOr<bool> Function(String, Uint8List)? capturedVerify;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        config: const SSHConfig(host: 'myhost', port: 2222, user: 'u'),
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedVerify = onVerifyHostKey;
          return mockClient;
        },
      );

      when(mockKnownHosts.verify('myhost', 2222, 'ssh-rsa', any))
          .thenAnswer((_) async => true);

      await conn.connect();

      final result = await capturedVerify!(
        'ssh-rsa',
        Uint8List.fromList([10, 20, 30]),
      );

      expect(result, isTrue);
      verify(mockKnownHosts.verify(
        'myhost',
        2222,
        'ssh-rsa',
        Uint8List.fromList([10, 20, 30]),
      )).called(1);
    });

    test('host key verification returns false when knownHosts rejects',
        () async {
      FutureOr<bool> Function(String, Uint8List)? capturedVerify;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = buildConnection(
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedVerify = onVerifyHostKey;
          return mockClient;
        },
      );

      when(mockKnownHosts.verify(any, any, any, any))
          .thenAnswer((_) async => false);

      await conn.connect();

      final result = await capturedVerify!(
        'ssh-ed25519',
        Uint8List.fromList([1]),
      );

      expect(result, isFalse);
    });
  });

  group('SSHConnection.connect — identity building', () {
    late MockSSHSocket mockSocket;
    late MockSSHClient mockClient;
    late MockKnownHostsManager mockKnownHosts;

    setUp(() {
      mockSocket = MockSSHSocket();
      mockClient = MockSSHClient();
      mockKnownHosts = MockKnownHostsManager();
    });

    test('connect with no keys passes identities list', () async {
      List<SSHKeyPair>? capturedIdentities;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = SSHConnection(
        config: const SSHConfig(host: 'h', user: 'u', password: 'p'),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedIdentities = identities;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedIdentities, isNotNull);
    });

    test('connect with invalid keyData throws ConnectError wrapping AuthError',
        () async {
      final conn = SSHConnection(
        config: const SSHConfig(
          host: 'h',
          user: 'u',
          keyData: 'INVALID-NOT-PEM',
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) =>
            mockClient,
      );

      // AuthError from _tryKeyTextAuth is caught by generic catch in connect()
      // and re-wrapped as ConnectError
      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.cause,
          'cause',
          isA<AuthError>(),
        )),
      );
    });

    test('connect with nonexistent key file throws ConnectError wrapping AuthError',
        () async {
      final conn = SSHConnection(
        config: const SSHConfig(
          host: 'h',
          user: 'u',
          keyPath: '/nonexistent/path/to/key_file_that_does_not_exist',
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) =>
            mockClient,
      );

      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.cause,
          'cause',
          isA<AuthError>(),
        )),
      );
    });

    test('connect with valid key file parses PEM', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssh_test_');
      final keyFile = File('${tempDir.path}/test_key');
      await keyFile.writeAsString(_testEd25519PrivateKey);

      List<SSHKeyPair>? capturedIdentities;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      try {
        final conn = SSHConnection(
          config: SSHConfig(host: 'h', user: 'u', keyPath: keyFile.path),
          knownHosts: mockKnownHosts,
          socketFactory: (h, p, {timeout}) async => mockSocket,
          clientFactory: (socket, {
            required username,
            onPasswordRequest,
            identities,
            onVerifyHostKey,
            keepAliveInterval,
          }) {
            capturedIdentities = identities;
            return mockClient;
          },
        );

        await conn.connect();
        expect(capturedIdentities, isNotNull);
        expect(capturedIdentities!.isNotEmpty, isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('connect with valid keyData parses PEM', () async {
      List<SSHKeyPair>? capturedIdentities;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = SSHConnection(
        config: SSHConfig(
          host: 'h',
          user: 'u',
          keyData: _testEd25519PrivateKey,
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) {
          capturedIdentities = identities;
          return mockClient;
        },
      );

      await conn.connect();
      expect(capturedIdentities, isNotNull);
      expect(capturedIdentities!.isNotEmpty, isTrue);
    });

    test('keyData with passphrase on unencrypted key throws error', () async {
      // dartssh2 rejects passphrase for unencrypted keys
      final conn = SSHConnection(
        config: SSHConfig(
          host: 'h',
          user: 'u',
          keyData: _testEd25519PrivateKey,
          passphrase: 'unused-but-set',
        ),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) =>
            mockClient,
      );

      expect(
        () => conn.connect(),
        throwsA(isA<ConnectError>().having(
          (e) => e.cause,
          'cause',
          isA<AuthError>(),
        )),
      );
    });

    test('keyPath takes priority when both keyPath and keyData provided',
        () async {
      // When keyPath is set, keyFile auth runs first; if it succeeds,
      // keyData auth still runs. Both should contribute identities.
      final tempDir = await Directory.systemTemp.createTemp('ssh_test_');
      final keyFile = File('${tempDir.path}/test_key');
      await keyFile.writeAsString(_testEd25519PrivateKey);

      List<SSHKeyPair>? capturedIdentities;

      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      try {
        final conn = SSHConnection(
          config: SSHConfig(
            host: 'h',
            user: 'u',
            keyPath: keyFile.path,
            keyData: _testEd25519PrivateKey,
          ),
          knownHosts: mockKnownHosts,
          socketFactory: (h, p, {timeout}) async => mockSocket,
          clientFactory: (socket, {
            required username,
            onPasswordRequest,
            identities,
            onVerifyHostKey,
            keepAliveInterval,
          }) {
            capturedIdentities = identities;
            return mockClient;
          },
        );

        await conn.connect();
        // Both keyPath and keyData should contribute identities
        expect(capturedIdentities, isNotNull);
        expect(capturedIdentities!.length, greaterThanOrEqualTo(2));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SSHConnection.openShell — with mock client', () {
    late MockSSHSocket mockSocket;
    late MockSSHClient mockClient;
    late MockSSHSession mockSession;
    late MockKnownHostsManager mockKnownHosts;

    setUp(() {
      mockSocket = MockSSHSocket();
      mockClient = MockSSHClient();
      mockSession = MockSSHSession();
      mockKnownHosts = MockKnownHostsManager();
    });

    Future<SSHConnection> connectMock() async {
      when(mockClient.authenticated).thenAnswer((_) async {});
      when(mockClient.done).thenAnswer((_) => Completer<void>().future);

      final conn = SSHConnection(
        config: const SSHConfig(host: 'h', user: 'u', password: 'p'),
        knownHosts: mockKnownHosts,
        socketFactory: (h, p, {timeout}) async => mockSocket,
        clientFactory: (socket, {
          required username,
          onPasswordRequest,
          identities,
          onVerifyHostKey,
          keepAliveInterval,
        }) =>
            mockClient,
      );

      await conn.connect();
      return conn;
    }

    test('openShell returns session on success', () async {
      when(mockClient.shell(pty: anyNamed('pty')))
          .thenAnswer((_) async => mockSession);

      final conn = await connectMock();
      final session = await conn.openShell(80, 24);

      expect(session, mockSession);
    });

    test('openShell passes correct PTY config', () async {
      SSHPtyConfig? capturedPty;
      when(mockClient.shell(pty: anyNamed('pty'))).thenAnswer((inv) async {
        capturedPty = inv.namedArguments[#pty] as SSHPtyConfig?;
        return mockSession;
      });

      final conn = await connectMock();
      await conn.openShell(120, 40);

      expect(capturedPty, isNotNull);
      expect(capturedPty!.width, 120);
      expect(capturedPty!.height, 40);
      expect(capturedPty!.type, 'xterm-256color');
    });

    test('openShell wraps errors in ConnectError', () async {
      when(mockClient.shell(pty: anyNamed('pty')))
          .thenThrow(Exception('channel failed'));

      final conn = await connectMock();

      expect(
        () => conn.openShell(80, 24),
        throwsA(isA<ConnectError>().having(
          (e) => e.message,
          'message',
          'Failed to open shell',
        )),
      );
    });

    test('resizeTerminal delegates to shell', () async {
      when(mockClient.shell(pty: anyNamed('pty')))
          .thenAnswer((_) async => mockSession);

      final conn = await connectMock();
      await conn.openShell(80, 24);

      conn.resizeTerminal(120, 40);
      verify(mockSession.resizeTerminal(120, 40)).called(1);
    });

    test('disconnect after connect cleans up', () async {
      when(mockClient.shell(pty: anyNamed('pty')))
          .thenAnswer((_) async => mockSession);

      final conn = await connectMock();
      await conn.openShell(80, 24);

      conn.disconnect();

      expect(conn.isConnected, isFalse);
      expect(conn.client, isNull);
      verify(mockSession.close()).called(1);
      verify(mockClient.close()).called(1);
    });
  });
}

/// Runtime-generated test key. Created in setUpAll, avoids hardcoded secrets.
late String _testEd25519PrivateKey;
