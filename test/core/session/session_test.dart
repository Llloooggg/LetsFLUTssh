import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';

void main() {
  group('Session', () {
    test('validate requires host', () {
      final s = Session(label: 'test', host: '', user: 'root');
      expect(s.validate(), 'Host is required');
    });

    test('validate requires user', () {
      final s = Session(label: 'test', host: 'example.com', user: '');
      expect(s.validate(), 'Username is required');
    });

    test('validate checks port range', () {
      final s = Session(label: 'test', host: 'x', user: 'r', port: 0);
      expect(s.validate(), 'Port must be 1-65535');
    });

    test('validate passes with valid data', () {
      final s = Session(label: 'test', host: 'example.com', user: 'root');
      expect(s.validate(), isNull);
    });

    test('displayName with label', () {
      final s = Session(label: 'prod', host: 'example.com', user: 'root');
      expect(s.displayName, 'prod (root@example.com)');
    });

    test('displayName without label', () {
      final s = Session(label: '', host: 'example.com', user: 'root', port: 2222);
      expect(s.displayName, 'root@example.com:2222');
    });

    test('fullPath with group', () {
      final s = Session(label: 'nginx', group: 'Production/Web', host: 'x', user: 'r');
      expect(s.fullPath, 'Production/Web/nginx');
    });

    test('fullPath without group', () {
      final s = Session(label: 'nginx', host: 'x', user: 'r');
      expect(s.fullPath, 'nginx');
    });

    test('duplicate creates copy with new id', () {
      final s = Session(label: 'test', host: 'x', user: 'r');
      final copy = s.duplicate();
      expect(copy.id, isNot(s.id));
      expect(copy.label, 'test (copy)');
      expect(copy.host, s.host);
    });

    test('JSON roundtrip', () {
      final s = Session(
        label: 'prod',
        group: 'Servers/Web',
        host: 'example.com',
        port: 2222,
        user: 'admin',
        authType: AuthType.key,
        keyPath: '/home/.ssh/id_rsa',
      );
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
      final s = Session(label: 'a', host: 'b', user: 'c');
      final updated = s.copyWith(label: 'new', port: 3333);
      expect(updated.id, s.id);
      expect(updated.label, 'new');
      expect(updated.port, 3333);
      expect(updated.host, 'b');
    });
  });
}
