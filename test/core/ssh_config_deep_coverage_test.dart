import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// Deep coverage for ssh_config.dart — covers remaining edge cases:
/// whitespace-only user, timeout edge, copyWith all fields, equality
/// for keyPath/keyData/passphrase/keepAliveSec/timeoutSec differences.
void main() {
  group('SSHConfig.validate — uncovered edges', () {
    test('whitespace-only user returns error', () {
      const config = SSHConfig(host: 'h', user: '   ');
      expect(config.validate(), contains('Username'));
    });

    test('negative timeout returns error', () {
      const config = SSHConfig(host: 'h', user: 'u', timeoutSec: -1);
      expect(config.validate(), contains('Timeout'));
    });

    test('timeout 1 is valid', () {
      const config = SSHConfig(host: 'h', user: 'u', timeoutSec: 1);
      expect(config.validate(), isNull);
    });

    test('keepAlive exactly 0 is valid', () {
      const config = SSHConfig(host: 'h', user: 'u', keepAliveSec: 0);
      expect(config.validate(), isNull);
    });

    test('port exactly 1 is valid', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 1);
      expect(config.validate(), isNull);
    });

    test('port exactly 65535 is valid', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 65535);
      expect(config.validate(), isNull);
    });
  });

  group('SSHConfig.copyWith — all fields', () {
    test('copyWith replaces all fields', () {
      const config = SSHConfig(
        host: 'a',
        port: 22,
        user: 'b',
        password: 'c',
        keyPath: 'd',
        keyData: 'e',
        passphrase: 'f',
        keepAliveSec: 30,
        timeoutSec: 10,
      );
      final updated = config.copyWith(
        host: 'h2',
        port: 2222,
        user: 'u2',
        password: 'p2',
        keyPath: 'k2',
        keyData: 'kd2',
        passphrase: 'pp2',
        keepAliveSec: 60,
        timeoutSec: 20,
      );
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
      const config = SSHConfig(host: 'h', user: 'u');
      final copy = config.copyWith();
      expect(copy, equals(config));
    });
  });

  group('SSHConfig equality — remaining field differences', () {
    test('different keyPath makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', keyPath: '/a');
      const b = SSHConfig(host: 'h', user: 'u', keyPath: '/b');
      expect(a, isNot(equals(b)));
    });

    test('different keyData makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', keyData: 'data1');
      const b = SSHConfig(host: 'h', user: 'u', keyData: 'data2');
      expect(a, isNot(equals(b)));
    });

    test('different passphrase makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', passphrase: 'pp1');
      const b = SSHConfig(host: 'h', user: 'u', passphrase: 'pp2');
      expect(a, isNot(equals(b)));
    });

    test('different keepAliveSec makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', keepAliveSec: 30);
      const b = SSHConfig(host: 'h', user: 'u', keepAliveSec: 60);
      expect(a, isNot(equals(b)));
    });

    test('different timeoutSec makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u', timeoutSec: 10);
      const b = SSHConfig(host: 'h', user: 'u', timeoutSec: 20);
      expect(a, isNot(equals(b)));
    });

    test('different user makes not equal', () {
      const a = SSHConfig(host: 'h', user: 'u1');
      const b = SSHConfig(host: 'h', user: 'u2');
      expect(a, isNot(equals(b)));
    });

    test('all fields equal produces same hashCode', () {
      const a = SSHConfig(
        host: 'h', port: 22, user: 'u', password: 'p',
        keyPath: 'k', keyData: 'kd', passphrase: 'pp',
        keepAliveSec: 30, timeoutSec: 10,
      );
      const b = SSHConfig(
        host: 'h', port: 22, user: 'u', password: 'p',
        keyPath: 'k', keyData: 'kd', passphrase: 'pp',
        keepAliveSec: 30, timeoutSec: 10,
      );
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SSHConfig.effectivePort — edge cases', () {
    test('effectivePort for port 0 returns 22', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 0);
      expect(config.effectivePort, 22);
    });

    test('effectivePort for port -10 returns 22', () {
      const config = SSHConfig(host: 'h', user: 'u', port: -10);
      expect(config.effectivePort, 22);
    });

    test('effectivePort for positive port returns itself', () {
      const config = SSHConfig(host: 'h', user: 'u', port: 8022);
      expect(config.effectivePort, 8022);
    });
  });

  group('SSHConfig.displayName', () {
    test('displayName with default port', () {
      const config = SSHConfig(host: 'example.com', user: 'root');
      expect(config.displayName, 'root@example.com:22');
    });

    test('displayName with custom port', () {
      const config = SSHConfig(host: 'example.com', user: 'admin', port: 2222);
      expect(config.displayName, 'admin@example.com:2222');
    });
  });
}
