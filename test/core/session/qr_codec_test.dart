import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  Session makeSession({
    String label = 'test',
    String host = 'example.com',
    int port = 22,
    String user = 'root',
    String group = '',
    AuthType authType = AuthType.password,
    String password = 'secret',
  }) {
    return Session(
      label: label,
      server: ServerAddress(host: host, port: port, user: user),
      group: group,
      auth: SessionAuth(authType: authType, password: password),
    );
  }

  group('encodeSessionsForQr', () {
    test('encodes a single session with default port', () {
      final sessions = [makeSession()];
      final json = encodeSessionsForQr(sessions);
      expect(json, contains('"v":1'));
      expect(json, contains('"l":"test"'));
      expect(json, contains('"h":"example.com"'));
      expect(json, contains('"u":"root"'));
      // Default port 22 should not be included
      expect(json, isNot(contains('"p":')));
      // No credentials
      expect(json, isNot(contains('secret')));
    });

    test('encodes non-default port', () {
      final sessions = [makeSession(port: 2222)];
      final json = encodeSessionsForQr(sessions);
      expect(json, contains('"p":2222'));
    });

    test('encodes group', () {
      final sessions = [makeSession(group: 'Production/Web')];
      final json = encodeSessionsForQr(sessions);
      expect(json, contains('"g":"Production/Web"'));
    });

    test('encodes non-default auth type', () {
      final sessions = [makeSession(authType: AuthType.key)];
      final json = encodeSessionsForQr(sessions);
      expect(json, contains('"a":"key"'));
    });

    test('omits default auth type (password)', () {
      final sessions = [makeSession(authType: AuthType.password)];
      final json = encodeSessionsForQr(sessions);
      expect(json, isNot(contains('"a":')));
    });

    test('encodes empty groups', () {
      final sessions = [makeSession()];
      final json = encodeSessionsForQr(sessions, emptyGroups: {'Staging', 'Dev'});
      expect(json, contains('"eg":'));
      expect(json, contains('Staging'));
      expect(json, contains('Dev'));
    });

    test('omits empty groups key when none provided', () {
      final sessions = [makeSession()];
      final json = encodeSessionsForQr(sessions);
      expect(json, isNot(contains('"eg"')));
    });

    test('never includes credentials', () {
      final sessions = [makeSession(password: 'supersecret')];
      final json = encodeSessionsForQr(sessions);
      expect(json, isNot(contains('supersecret')));
      expect(json, isNot(contains('password')));
    });

    test('encodes multiple sessions', () {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
        makeSession(label: 'c', host: 'c.com'),
      ];
      final json = encodeSessionsForQr(sessions);
      expect(json, contains('"a.com"'));
      expect(json, contains('"b.com"'));
      expect(json, contains('"c.com"'));
    });
  });

  group('decodeSessionsFromQr', () {
    test('roundtrip encode/decode preserves session data', () {
      final sessions = [
        makeSession(label: 'nginx', host: 'prod.com', port: 2222, user: 'deploy', group: 'Production'),
        makeSession(label: 'api', host: 'api.com', user: 'admin'),
      ];
      final json = encodeSessionsForQr(sessions, emptyGroups: {'Staging'});
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions.length, 2);
      expect(result.sessions[0].label, 'nginx');
      expect(result.sessions[0].host, 'prod.com');
      expect(result.sessions[0].port, 2222);
      expect(result.sessions[0].user, 'deploy');
      expect(result.sessions[0].group, 'Production');
      expect(result.sessions[1].label, 'api');
      expect(result.sessions[1].host, 'api.com');
      expect(result.sessions[1].port, 22);
      expect(result.emptyGroups, {'Staging'});
    });

    test('decoded sessions are marked as incomplete', () {
      final sessions = [makeSession()];
      final json = encodeSessionsForQr(sessions);
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions[0].incomplete, isTrue);
    });

    test('decoded sessions have no credentials', () {
      final sessions = [makeSession(password: 'secret')];
      final json = encodeSessionsForQr(sessions);
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions[0].password, '');
      expect(result.sessions[0].keyPath, '');
      expect(result.sessions[0].keyData, '');
      expect(result.sessions[0].passphrase, '');
    });

    test('returns null for invalid JSON', () {
      expect(decodeSessionsFromQr('not json'), isNull);
    });

    test('returns null for wrong version', () {
      expect(decodeSessionsFromQr('{"v":99,"s":[]}'), isNull);
    });

    test('returns null for missing sessions key', () {
      expect(decodeSessionsFromQr('{"v":1}'), isNull);
    });

    test('returns null for empty string', () {
      expect(decodeSessionsFromQr(''), isNull);
    });

    test('handles missing optional fields gracefully', () {
      const json = '{"v":1,"s":[{"h":"host","u":"user"}]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions.length, 1);
      expect(result.sessions[0].host, 'host');
      expect(result.sessions[0].user, 'user');
      expect(result.sessions[0].label, '');
      expect(result.sessions[0].port, 22);
      expect(result.sessions[0].group, '');
      expect(result.sessions[0].authType, AuthType.password);
    });

    test('handles empty sessions array', () {
      const json = '{"v":1,"s":[]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions, isEmpty);
      expect(result.emptyGroups, isEmpty);
    });

    test('handles no empty groups key', () {
      const json = '{"v":1,"s":[{"h":"h","u":"u"}]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.emptyGroups, isEmpty);
    });

    test('decodes auth type key', () {
      const json = '{"v":1,"s":[{"h":"h","u":"u","a":"key"}]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions[0].authType, AuthType.key);
    });

    test('decodes auth type keyWithPassword', () {
      const json = '{"v":1,"s":[{"h":"h","u":"u","a":"keyWithPassword"}]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions[0].authType, AuthType.keyWithPassword);
    });

    test('defaults unknown auth type to password', () {
      const json = '{"v":1,"s":[{"h":"h","u":"u","a":"unknown"}]}';
      final result = decodeSessionsFromQr(json);

      expect(result, isNotNull);
      expect(result!.sessions[0].authType, AuthType.password);
    });
  });

  group('calculateQrPayloadSize', () {
    test('returns size in bytes', () {
      final sessions = [makeSession()];
      final size = calculateQrPayloadSize(sessions);
      expect(size, greaterThan(0));
    });

    test('size increases with more sessions', () {
      final one = [makeSession()];
      final three = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
        makeSession(label: 'c', host: 'c.com'),
      ];
      expect(calculateQrPayloadSize(three), greaterThan(calculateQrPayloadSize(one)));
    });

    test('size increases with empty groups', () {
      final sessions = [makeSession()];
      final withoutGroups = calculateQrPayloadSize(sessions);
      final withGroups = calculateQrPayloadSize(sessions, emptyGroups: {'A', 'B', 'C'});
      expect(withGroups, greaterThan(withoutGroups));
    });
  });

  group('qrMaxPayloadBytes', () {
    test('is a reasonable limit', () {
      expect(qrMaxPayloadBytes, greaterThan(1000));
      expect(qrMaxPayloadBytes, lessThanOrEqualTo(3000));
    });
  });

  group('Session.incomplete field', () {
    test('defaults to false', () {
      final s = makeSession();
      expect(s.incomplete, isFalse);
    });

    test('can be set to true', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      expect(s.incomplete, isTrue);
    });

    test('auto-resets when auth is filled via copyWith', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      expect(s.incomplete, isTrue);

      final updated = s.copyWith(
        auth: const SessionAuth(password: 'pass'),
      );
      expect(updated.incomplete, isFalse);
    });

    test('stays incomplete when auth is still empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      final updated = s.copyWith(label: 'renamed');
      expect(updated.incomplete, isTrue);
    });

    test('can be explicitly set via copyWith', () {
      final s = makeSession();
      final updated = s.copyWith(incomplete: true);
      expect(updated.incomplete, isTrue);
    });

    test('serialized to JSON only when true', () {
      final normal = makeSession();
      expect(normal.toJson().containsKey('incomplete'), isFalse);

      final incomplete = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      expect(incomplete.toJson()['incomplete'], isTrue);
    });

    test('deserialized from JSON', () {
      const json = {
        'id': 'test-id',
        'host': 'h',
        'user': 'u',
        'incomplete': true,
      };
      final s = Session.fromJson(json);
      expect(s.incomplete, isTrue);
    });

    test('defaults to false when not in JSON', () {
      const json = {
        'id': 'test-id',
        'host': 'h',
        'user': 'u',
      };
      final s = Session.fromJson(json);
      expect(s.incomplete, isFalse);
    });

    test('equality includes incomplete', () {
      final a = Session(
        id: 'same',
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: false,
      );
      final b = Session(
        id: 'same',
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      expect(a, isNot(equals(b)));
    });

    test('duplicate preserves incomplete', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        incomplete: true,
      );
      final copy = s.duplicate();
      expect(copy.incomplete, isTrue);
      expect(copy.id, isNot(equals(s.id)));
    });
  });
}
