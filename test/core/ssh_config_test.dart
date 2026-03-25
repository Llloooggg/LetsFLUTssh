import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SSHConfig', () {
    test('defaults', () {
      const config = SSHConfig(host: 'example.com', user: 'root');
      expect(config.port, 22);
      expect(config.effectivePort, 22);
      expect(config.password, '');
      expect(config.keyPath, '');
      expect(config.keyData, '');
      expect(config.keepAliveSec, 30);
      expect(config.timeoutSec, 10);
    });

    test('hasAuth is false when no auth', () {
      const config = SSHConfig(host: 'test', user: 'root');
      expect(config.hasAuth, false);
    });

    test('hasAuth is true with password', () {
      const config = SSHConfig(
        host: 'test',
        user: 'root',
        password: 'secret',
      );
      expect(config.hasAuth, true);
    });

    test('hasAuth is true with key', () {
      const config = SSHConfig(
        host: 'test',
        user: 'root',
        keyPath: '/home/user/.ssh/id_rsa',
      );
      expect(config.hasAuth, true);
    });

    test('displayName format', () {
      const config = SSHConfig(host: 'example.com', user: 'admin', port: 2222);
      expect(config.displayName, 'admin@example.com:2222');
    });

    test('effectivePort defaults to 22 for port 0', () {
      const config = SSHConfig(host: 'test', user: 'root', port: 0);
      expect(config.effectivePort, 22);
    });

    test('copyWith', () {
      const config = SSHConfig(host: 'a', user: 'b');
      final updated = config.copyWith(host: 'c', port: 3333);
      expect(updated.host, 'c');
      expect(updated.port, 3333);
      expect(updated.user, 'b');
    });
  });

  group('SSHConfig.validate', () {
    test('returns null for valid config', () {
      const config = SSHConfig(host: 'example.com', user: 'root');
      expect(config.validate(), isNull);
    });

    test('returns error for empty host', () {
      const config = SSHConfig(host: '', user: 'root');
      expect(config.validate(), contains('Host'));
    });

    test('returns error for whitespace-only host', () {
      const config = SSHConfig(host: '   ', user: 'root');
      expect(config.validate(), contains('Host'));
    });

    test('returns error for empty user', () {
      const config = SSHConfig(host: 'h', user: '');
      expect(config.validate(), contains('Username'));
    });

    test('returns error for port 0', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 0);
      expect(config.validate(), contains('Port'));
    });

    test('returns error for port > 65535', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 70000);
      expect(config.validate(), contains('Port'));
    });

    test('returns error for negative port', () {
      const config = SSHConfig(host: 'h', user: 'u', port: -1);
      expect(config.validate(), contains('Port'));
    });

    test('returns error for negative keepAlive', () {
      const config = SSHConfig(host: 'h', user: 'u', keepAliveSec: -1);
      expect(config.validate(), contains('Keep-alive'));
    });

    test('returns error for zero timeout', () {
      const config = SSHConfig(host: 'h', user: 'u', timeoutSec: 0);
      expect(config.validate(), contains('Timeout'));
    });
  });

  group('SSHConfig — additional coverage', () {
    test('hasAuth is true with keyData', () {
      const config = SSHConfig(
        host: 'test',
        user: 'root',
        keyData: '-----BEGIN RSA PRIVATE KEY-----\ndata\n-----END RSA PRIVATE KEY-----',
      );
      expect(config.hasAuth, true);
    });

    test('effectivePort returns 22 for negative port', () {
      const config = SSHConfig(host: 'test', user: 'root', port: -5);
      expect(config.effectivePort, 22);
    });

    test('validate passes with keepAliveSec = 0', () {
      const config = SSHConfig(host: 'h', user: 'u', keepAliveSec: 0);
      expect(config.validate(), isNull);
    });

    test('validate passes with edge port values', () {
      expect(const SSHConfig(host: 'h', user: 'u', port: 1).validate(), isNull);
      expect(const SSHConfig(host: 'h', user: 'u', port: 65535).validate(), isNull);
    });
  });

  group('SSHConfig equality', () {
    test('equal configs are equal', () {
      const a = SSHConfig(host: 'h', user: 'u', port: 22);
      const b = SSHConfig(host: 'h', user: 'u', port: 22);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different host makes not equal', () {
      const a = SSHConfig(host: 'h1', user: 'u');
      const b = SSHConfig(host: 'h2', user: 'u');
      expect(a, isNot(equals(b)));
    });

    test('different port makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', port: 22);
      const b = SSHConfig(host: 'h', user: 'u', port: 2222);
      expect(a, isNot(equals(b)));
    });

    test('different password makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', password: 'a');
      const b = SSHConfig(host: 'h', user: 'u', password: 'b');
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      const a = SSHConfig(host: 'h', user: 'u');
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      const a = SSHConfig(host: 'h', user: 'u');
      expect(a == Object(), isFalse);
    });
  });
}
