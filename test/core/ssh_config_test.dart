import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SSHConfig', () {
    test('defaults', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.port, 22);
      expect(config.effectivePort, 22);
      expect(config.password, '');
      expect(config.keyPath, '');
      expect(config.keyData, '');
      expect(config.keepAliveSec, 30);
      expect(config.timeoutSec, 10);
    });

    test('hasAuth is false when no auth', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', user: 'root'));
      expect(config.hasAuth, false);
    });

    test('hasAuth is true with password', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', user: 'root'), auth: SshAuth(password: 'secret'));
      expect(config.hasAuth, true);
    });

    test('hasAuth is true with key', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', user: 'root'), auth: SshAuth(keyPath: '/home/user/.ssh/id_rsa'));
      expect(config.hasAuth, true);
    });

    test('displayName format', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', port: 2222, user: 'admin'));
      expect(config.displayName, 'admin@example.com:2222');
    });

    test('effectivePort defaults to 22 for port 0', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', port: 0, user: 'root'));
      expect(config.effectivePort, 22);
    });

    test('copyWith', () {
      const config = SSHConfig(server: ServerAddress(host: 'a', user: 'b'));
      final updated = config.copyWith(server: config.server.copyWith(host: 'c', port: 3333));
      expect(updated.host, 'c');
      expect(updated.port, 3333);
      expect(updated.user, 'b');
    });
  });

  group('SSHConfig.validate', () {
    test('returns null for valid config', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.validate(), isNull);
    });

    test('returns error for empty host', () {
      const config = SSHConfig(server: ServerAddress(host: '', user: 'root'));
      expect(config.validate(), contains('Host'));
    });

    test('returns error for whitespace-only host', () {
      const config = SSHConfig(server: ServerAddress(host: '   ', user: 'root'));
      expect(config.validate(), contains('Host'));
    });

    test('returns error for empty user', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: ''));
      expect(config.validate(), contains('Username'));
    });

    test('returns error for port 0', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', port: 0, user: 'u'));
      expect(config.validate(), contains('Port'));
    });

    test('returns error for port > 65535', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', port: 70000, user: 'u'));
      expect(config.validate(), contains('Port'));
    });

    test('returns error for negative port', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', port: -1, user: 'u'));
      expect(config.validate(), contains('Port'));
    });

    test('returns error for negative keepAlive', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), keepAliveSec: -1);
      expect(config.validate(), contains('Keep-alive'));
    });

    test('returns error for zero timeout', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), timeoutSec: 0);
      expect(config.validate(), contains('Timeout'));
    });
  });

  group('SSHConfig — additional coverage', () {
    test('hasAuth is true with keyData', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', user: 'root'), auth: SshAuth(keyData: '-----BEGIN RSA PRIVATE KEY-----\ndata\n-----END RSA PRIVATE KEY-----'));
      expect(config.hasAuth, true);
    });

    test('effectivePort returns 22 for negative port', () {
      const config = SSHConfig(server: ServerAddress(host: 'test', port: -5, user: 'root'));
      expect(config.effectivePort, 22);
    });

    test('validate passes with keepAliveSec = 0', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), keepAliveSec: 0);
      expect(config.validate(), isNull);
    });

    test('validate passes with edge port values', () {
      expect(const SSHConfig(server: ServerAddress(host: 'h', port: 1, user: 'u')).validate(), isNull);
      expect(const SSHConfig(server: ServerAddress(host: 'h', port: 65535, user: 'u')).validate(), isNull);
    });
  });

  group('SSHConfig equality', () {
    test('equal configs are equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u'));
      const b = SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different host makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h1', user: 'u'));
      const b = SSHConfig(server: ServerAddress(host: 'h2', user: 'u'));
      expect(a, isNot(equals(b)));
    });

    test('different port makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u'));
      const b = SSHConfig(server: ServerAddress(host: 'h', port: 2222, user: 'u'));
      expect(a, isNot(equals(b)));
    });

    test('different password makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(password: 'a'));
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(password: 'b'));
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'));
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'));
      expect(a == Object(), isFalse);
    });

    test('different keyPath makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(keyPath: '/a'));
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(keyPath: '/b'));
      expect(a, isNot(equals(b)));
    });

    test('different keyData makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(keyData: 'data1'));
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(keyData: 'data2'));
      expect(a, isNot(equals(b)));
    });

    test('different passphrase makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(passphrase: 'pp1'));
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), auth: SshAuth(passphrase: 'pp2'));
      expect(a, isNot(equals(b)));
    });

    test('different keepAliveSec makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), keepAliveSec: 30);
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), keepAliveSec: 60);
      expect(a, isNot(equals(b)));
    });

    test('different timeoutSec makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), timeoutSec: 10);
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), timeoutSec: 20);
      expect(a, isNot(equals(b)));
    });

    test('different user makes not equal', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', user: 'u1'));
      const b = SSHConfig(server: ServerAddress(host: 'h', user: 'u2'));
      expect(a, isNot(equals(b)));
    });

    test('all fields equal produces same hashCode', () {
      const a = SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u'), auth: SshAuth(password: 'p', keyPath: 'k', keyData: 'kd', passphrase: 'pp'), keepAliveSec: 30, timeoutSec: 10);
      const b = SSHConfig(server: ServerAddress(host: 'h', port: 22, user: 'u'), auth: SshAuth(password: 'p', keyPath: 'k', keyData: 'kd', passphrase: 'pp'), keepAliveSec: 30, timeoutSec: 10);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SSHConfig.validate — edge cases', () {
    test('whitespace-only user returns error', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: '   '));
      expect(config.validate(), contains('Username'));
    });

    test('negative timeout returns error', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), timeoutSec: -1);
      expect(config.validate(), contains('Timeout'));
    });

    test('timeout 1 is valid', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'), timeoutSec: 1);
      expect(config.validate(), isNull);
    });
  });

  group('SSHConfig.copyWith — all fields', () {
    test('copyWith replaces all fields', () {
      const config = SSHConfig(server: ServerAddress(host: 'a', port: 22, user: 'b'), auth: SshAuth(password: 'c', keyPath: 'd', keyData: 'e', passphrase: 'f'), keepAliveSec: 30, timeoutSec: 10);
      final updated = config.copyWith(keepAliveSec: 60, timeoutSec: 20, server: config.server.copyWith(host: 'h2', port: 2222, user: 'u2'), auth: config.auth.copyWith(password: 'p2', keyPath: 'k2', keyData: 'kd2', passphrase: 'pp2'));
      expect(updated.host, 'h2');
      expect(updated.port, 2222);
      expect(updated.user, 'u2');
      expect(updated.password, 'p2');
      expect(updated.keyPath, 'k2');
      expect(updated.keyData, 'kd2');
      expect(updated.passphrase, 'pp2');
      expect(updated.keepAliveSec, 60);
      expect(updated.timeoutSec, 20);
    });

    test('copyWith with no args returns equal config', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', user: 'u'));
      final copy = config.copyWith();
      expect(copy, equals(config));
    });
  });

  group('SSHConfig.effectivePort — edge cases', () {
    test('effectivePort for port -10 returns 22', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', port: -10, user: 'u'));
      expect(config.effectivePort, 22);
    });

    test('effectivePort for positive port returns itself', () {
      const config = SSHConfig(server: ServerAddress(host: 'h', port: 8022, user: 'u'));
      expect(config.effectivePort, 8022);
    });
  });

  group('SSHConfig.displayName — default port', () {
    test('displayName with default port', () {
      const config = SSHConfig(server: ServerAddress(host: 'example.com', user: 'root'));
      expect(config.displayName, 'root@example.com:22');
    });
  });
}
