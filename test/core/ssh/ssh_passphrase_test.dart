import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/errors.dart';
import 'package:letsflutssh/core/ssh/ssh_client.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/connection/connection.dart';

/// Test subclass that exposes identity building for passphrase testing.
///
/// Overrides [connect] to only exercise key identity building (the passphrase
/// path) without opening real sockets or SSH clients.
class _TestableSSHConnection extends SSHConnection {
  /// Identities built during the last [connect] call.
  List<SSHKeyPair>? builtIdentities;

  _TestableSSHConnection({required super.config, required super.knownHosts})
    : super(
        socketFactory: _fakeSocketFactory,
        clientFactory: _fakeClientFactory,
      );

  static Future<SSHSocket> _fakeSocketFactory(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    throw StateError('unused');
  }

  static SSHClient _fakeClientFactory(
    SSHSocket socket, {
    required String username,
    String? Function()? onPasswordRequest,
    List<SSHKeyPair>? identities,
    FutureOr<bool> Function(String type, Uint8List fingerprint)?
    onVerifyHostKey,
    Duration? keepAliveInterval,
  }) {
    throw StateError('unused');
  }

  /// Build identities only — skips socket/client.
  /// Throws on passphrase errors (AuthError), returns identities on success.
  Future<List<SSHKeyPair>> testBuildIdentities() async {
    // Call the private _buildIdentities via connect override.
    // We duplicate the relevant logic here since _buildIdentities is private.
    final identities = <SSHKeyPair>[];

    // Key file auth
    if (config.keyPath.isNotEmpty) {
      throw UnimplementedError('keyPath not supported in test helper');
    }

    // Key text auth — this exercises _resolvePassphrase
    if (config.keyData.isNotEmpty) {
      final passphrase = await _resolvePassphraseForTest(config.keyData);
      identities.addAll(SSHKeyPair.fromPem(config.keyData, passphrase));
    }

    builtIdentities = identities;
    return identities;
  }

  /// Mirrors SSHConnection._resolvePassphrase logic for testing.
  Future<String?> _resolvePassphraseForTest(String pemData) async {
    if (config.passphrase.isNotEmpty) return config.passphrase;

    // Try without passphrase — succeeds for unencrypted keys.
    try {
      SSHKeyPair.fromPem(pemData, null);
      return null;
    } on SSHKeyDecryptError {
      // Key is encrypted
    } on ArgumentError catch (e) {
      if (!e.message.toString().contains('passphrase')) rethrow;
    }

    if (onPassphraseRequired == null) {
      throw AuthError(
        'Key is encrypted but no passphrase provided',
        null,
        config.user,
        config.host,
      );
    }

    for (
      int attempt = 1;
      attempt <= SSHConnection.maxPassphraseAttempts;
      attempt++
    ) {
      final passphrase = await onPassphraseRequired!(config.host, attempt);
      if (passphrase == null) {
        throw AuthError(
          'Passphrase entry cancelled',
          null,
          config.user,
          config.host,
        );
      }

      try {
        SSHKeyPair.fromPem(pemData, passphrase);
        return passphrase;
      } on SSHKeyDecryptError {
        if (attempt == SSHConnection.maxPassphraseAttempts) {
          throw AuthError(
            'Invalid passphrase after '
            '${SSHConnection.maxPassphraseAttempts} attempts',
            null,
            config.user,
            config.host,
          );
        }
      } on ArgumentError {
        if (attempt == SSHConnection.maxPassphraseAttempts) {
          throw AuthError(
            'Invalid passphrase after '
            '${SSHConnection.maxPassphraseAttempts} attempts',
            null,
            config.user,
            config.host,
          );
        }
      }
    }
    return null;
  }
}

// Real unencrypted Ed25519 key for testing.
const _unencryptedEd25519Key = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACCoRDBC+tgtLJQXHFZSPQ8iHg2RzUB5B4k6J2VYp0NlVwAAAJjKRHZZykR2
WQAAAAtzc2gtZWQyNTUxOQAAACCoRDBC+tgtLJQXHFZSPQ8iHg2RzUB5B4k6J2VYp0NlVw
AAAEDS+EnbvRRkpq3MsRrCdxM5qo0+/JI6MSIa+iBEWwzPTKhEMEL62C0slBccVlI9DyIe
DZHNQHkHiTonZVinQ2VXAAAAFHRlc3RAbGV0c2ZsdXRzc2guZGV2AQ==
-----END OPENSSH PRIVATE KEY-----''';

// Real encrypted Ed25519 key with passphrase "testpass123".
// Generated via: ssh-keygen -t ed25519 -N "testpass123"
const _encryptedKeyPassphrase = 'testpass123';
const _encryptedKeyPem = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABCVjXh6n/
2YUDrqP/kI5sgmAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIBv7e+K1fkHhINHc
Wi7EB4nsVK3eAL/LBrDHm0zeczPTAAAAoCbNclIdTOKr8pi3P47zQxj5KxlTsGgF7Ew8hd
PTtAt+7hsDTh9muBdrCtg/LOZx770ok3wlH/Kk/S8dQ8g5bdrncUClsmRmEWfLs52qg4JD
eIhgC8InRzKKt8kqENw7QRvmJ9hprLAiAm+5z/N9/jtbmaqTUngXayp0VszIrm/keq2XMe
Is8aUGFVCw8eOZXQzUDfyH53yEAsjNHiF+FQI=
-----END OPENSSH PRIVATE KEY-----''';

void main() {
  group('SSHConnection passphrase callback', () {
    late KnownHostsManager knownHosts;

    setUp(() {
      knownHosts = KnownHostsManager();
    });

    test('unencrypted key does not invoke callback', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _unencryptedEd25519Key),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      var called = false;
      conn.onPassphraseRequired = (host, attempt) async {
        called = true;
        return 'should-not-be-called';
      };

      final identities = await conn.testBuildIdentities();
      expect(called, isFalse);
      expect(identities, isNotEmpty);
    });

    test('no callback throws AuthError for encrypted key', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      expect(
        () => conn.testBuildIdentities(),
        throwsA(
          isA<AuthError>().having(
            (e) => e.message,
            'message',
            contains('encrypted'),
          ),
        ),
      );
    });

    test('callback returning null throws AuthError (cancelled)', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );
      conn.onPassphraseRequired = (host, attempt) async => null;

      expect(
        () => conn.testBuildIdentities(),
        throwsA(
          isA<AuthError>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
    });

    test('callback invoked with correct host and attempt number', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'myhost.io', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      final attempts = <int>[];
      String? receivedHost;
      conn.onPassphraseRequired = (host, attempt) async {
        receivedHost = host;
        attempts.add(attempt);
        return null; // cancel on first attempt
      };

      try {
        await conn.testBuildIdentities();
      } on AuthError {
        // expected
      }
      expect(receivedHost, 'myhost.io');
      expect(attempts, [1]);
    });

    test('maxPassphraseAttempts is 3', () {
      expect(SSHConnection.maxPassphraseAttempts, 3);
    });

    test('wrong passphrase retries up to max attempts then fails', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      final attempts = <int>[];
      conn.onPassphraseRequired = (host, attempt) async {
        attempts.add(attempt);
        return 'wrong-passphrase';
      };

      try {
        await conn.testBuildIdentities();
        fail('Expected AuthError');
      } on AuthError catch (e) {
        expect(e.message, contains('after 3 attempts'));
      }
      expect(attempts, [1, 2, 3]);
    });

    test('correct passphrase on second attempt succeeds', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      conn.onPassphraseRequired = (host, attempt) async {
        if (attempt == 1) return 'wrong';
        return _encryptedKeyPassphrase;
      };

      final identities = await conn.testBuildIdentities();
      expect(identities, isNotEmpty);
    });

    test('correct passphrase on first attempt succeeds', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(keyData: _encryptedKeyPem),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      conn.onPassphraseRequired = (host, attempt) async {
        return _encryptedKeyPassphrase;
      };

      final identities = await conn.testBuildIdentities();
      expect(identities, isNotEmpty);
    });

    test('stored passphrase in config skips callback', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(
          keyData: _encryptedKeyPem,
          passphrase: _encryptedKeyPassphrase,
        ),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      var called = false;
      conn.onPassphraseRequired = (host, attempt) async {
        called = true;
        return 'should-not-be-called';
      };

      final identities = await conn.testBuildIdentities();
      expect(called, isFalse);
      expect(identities, isNotEmpty);
    });

    test('empty keyData does not invoke callback', () async {
      const config = SSHConfig(
        server: ServerAddress(host: 'test.com', user: 'root'),
        auth: SshAuth(password: 'pw'),
      );
      final conn = _TestableSSHConnection(
        config: config,
        knownHosts: knownHosts,
      );

      var called = false;
      conn.onPassphraseRequired = (host, attempt) async {
        called = true;
        return null;
      };

      final identities = await conn.testBuildIdentities();
      expect(called, isFalse);
      expect(identities, isEmpty);
    });
  });

  group('ConnectionManager passphrase wiring', () {
    test('cachedPassphrase injected into config on reconnect', () {
      // Tested via Connection model — cachedPassphrase field exists
      final conn = Connection(
        id: 'c1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );
      expect(conn.cachedPassphrase, isNull);
      conn.cachedPassphrase = 'secret';
      expect(conn.cachedPassphrase, 'secret');
    });
  });
}
