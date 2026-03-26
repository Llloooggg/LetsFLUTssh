import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('Session', () {
    test('validate requires host', () {
      final s = Session(label: 'test', server: const ServerAddress(host: '', user: 'root'));
      expect(s.validate(), 'Host is required');
    });

    test('validate requires user', () {
      final s = Session(label: 'test', server: const ServerAddress(host: 'example.com', user: ''));
      expect(s.validate(), 'Username is required');
    });

    test('validate checks port range', () {
      final s = Session(label: 'test', server: const ServerAddress(host: 'x', port: 0, user: 'r'));
      expect(s.validate(), 'Port must be 1-65535');
    });

    test('validate passes with valid data', () {
      final s = Session(label: 'test', server: const ServerAddress(host: 'example.com', user: 'root'));
      expect(s.validate(), isNull);
    });

    test('displayName with label', () {
      final s = Session(label: 'prod', server: const ServerAddress(host: 'example.com', user: 'root'));
      expect(s.displayName, 'prod (root@example.com)');
    });

    test('displayName without label', () {
      final s = Session(label: '', server: const ServerAddress(host: 'example.com', port: 2222, user: 'root'));
      expect(s.displayName, 'root@example.com:2222');
    });

    test('fullPath with group', () {
      final s = Session(label: 'nginx', group: 'Production/Web', server: const ServerAddress(host: 'x', user: 'r'));
      expect(s.fullPath, 'Production/Web/nginx');
    });

    test('fullPath without group', () {
      final s = Session(label: 'nginx', server: const ServerAddress(host: 'x', user: 'r'));
      expect(s.fullPath, 'nginx');
    });

    test('duplicate creates copy with new id', () {
      final s = Session(label: 'test', server: const ServerAddress(host: 'x', user: 'r'));
      final copy = s.duplicate();
      expect(copy.id, isNot(s.id));
      expect(copy.label, 'test (copy)');
      expect(copy.host, s.host);
    });

    test('JSON roundtrip', () {
      final s = Session(label: 'prod', group: 'Servers/Web', server: const ServerAddress(host: 'example.com', port: 2222, user: 'admin'), auth: const SessionAuth(authType: AuthType.key, keyPath: '/home/.ssh/id_rsa'));
      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.label, 'prod');
      expect(restored.group, 'Servers/Web');
      expect(restored.host, 'example.com');
      expect(restored.port, 2222);
      expect(restored.user, 'admin');
      expect(restored.authType, AuthType.key);
      expect(restored.keyPath, '/home/.ssh/id_rsa');
    });

    test('copyWith updates fields', () {
      final s = Session(label: 'a', server: const ServerAddress(host: 'b', user: 'c'));
      final updated = s.copyWith(label: 'new', server: s.server.copyWith(port: 3333));
      expect(updated.id, s.id);
      expect(updated.label, 'new');
      expect(updated.port, 3333);
      expect(updated.host, 'b');
    });
  });

  group('Session equality', () {
    test('same id and fields are equal', () {
      final a = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      final b = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different id makes not equal', () {
      final a = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      final b = Session(id: 'y', label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      expect(a, isNot(equals(b)));
    });

    test('different host makes not equal', () {
      final a = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h1', user: 'u'));
      final b = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h2', user: 'u'));
      expect(a, isNot(equals(b)));
    });

    test('different password makes not equal', () {
      final a = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h', user: 'u'), auth: const SessionAuth(password: 'a'));
      final b = Session(id: 'x', label: 'a', server: const ServerAddress(host: 'h', user: 'u'), auth: const SessionAuth(password: 'b'));
      expect(a, isNot(equals(b)));
    });

    test('different group makes not equal', () {
      final a = Session(id: 'x', label: 'a', group: 'A', server: const ServerAddress(host: 'h', user: 'u'));
      final b = Session(id: 'x', label: 'a', group: 'B', server: const ServerAddress(host: 'h', user: 'u'));
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      final a = Session(label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      final a = Session(label: 'a', server: const ServerAddress(host: 'h', user: 'u'));
      expect(a == Object(), isFalse);
    });
  });
}
