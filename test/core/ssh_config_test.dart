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
}
