import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('Session', () {
    test('validate requires host', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: '', user: 'root'),
      );
      expect(s.validate(), 'Host is required');
    });

    test('validate requires user', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'example.com', user: ''),
      );
      expect(s.validate(), 'Username is required');
    });

    test('validate checks port range', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'x', port: 0, user: 'r'),
      );
      expect(s.validate(), 'Port must be 1-65535');
    });

    test('validate passes with valid data', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'example.com', user: 'root'),
      );
      expect(s.validate(), isNull);
    });

    test('displayName with label', () {
      final s = Session(
        label: 'prod',
        server: const ServerAddress(host: 'example.com', user: 'root'),
      );
      expect(s.displayName, 'prod (root@example.com)');
    });

    test('displayName without label', () {
      final s = Session(
        label: '',
        server: const ServerAddress(
          host: 'example.com',
          port: 2222,
          user: 'root',
        ),
      );
      expect(s.displayName, 'root@example.com:2222');
    });

    test('fullPath with folder', () {
      final s = Session(
        label: 'nginx',
        folder: 'Production/Web',
        server: const ServerAddress(host: 'x', user: 'r'),
      );
      expect(s.fullPath, 'Production/Web/nginx');
    });

    test('fullPath without folder', () {
      final s = Session(
        label: 'nginx',
        server: const ServerAddress(host: 'x', user: 'r'),
      );
      expect(s.fullPath, 'nginx');
    });

    test('duplicate creates copy with new id', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'x', user: 'r'),
      );
      final copy = s.duplicate();
      expect(copy.id, isNot(s.id));
      expect(copy.label, 'test (copy)');
      expect(copy.host, s.host);
    });

    test('duplicate with empty label produces empty label', () {
      final s = Session(
        label: '',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final copy = s.duplicate();
      expect(copy.label, isEmpty);
      expect(copy.displayName, 'u@h:22');
    });

    test('duplicate creates independent server and auth copies', () {
      final s = Session(
        label: 'orig',
        server: const ServerAddress(host: 'a', port: 22, user: 'b'),
        auth: const SessionAuth(password: 'pw', keyData: 'key'),
      );
      final copy = s.duplicate();
      expect(copy.host, s.host);
      expect(copy.password, s.password);
      expect(copy.keyData, s.keyData);
      expect(identical(copy.server, s.server), isFalse);
      expect(identical(copy.auth, s.auth), isFalse);
    });

    test('duplicate preserves authType', () {
      final s = Session(
        label: 'key-session',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.keyWithPassword,
          keyPath: '/key',
          passphrase: 'pp',
        ),
      );
      final copy = s.duplicate();
      expect(copy.authType, AuthType.keyWithPassword);
    });

    test('JSON roundtrip', () {
      final s = Session(
        label: 'prod',
        folder: 'Servers/Web',
        server: const ServerAddress(
          host: 'example.com',
          port: 2222,
          user: 'admin',
        ),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '/home/.ssh/id_rsa',
        ),
      );
      final json = s.toJson();
      final restored = Session.fromJson(json);
      expect(restored.label, 'prod');
      expect(restored.folder, 'Servers/Web');
      expect(restored.host, 'example.com');
      expect(restored.port, 2222);
      expect(restored.user, 'admin');
      expect(restored.authType, AuthType.key);
      expect(restored.keyPath, '/home/.ssh/id_rsa');
    });

    test('JSON roundtrip preserves keyId', () {
      final s = Session(
        label: 'with-key-id',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(authType: AuthType.key, keyId: 'store-key-42'),
      );
      final json = s.toJson();
      expect(json['key_id'], 'store-key-42');
      final restored = Session.fromJson(json);
      expect(restored.keyId, 'store-key-42');
    });

    test('JSON without key_id defaults to empty', () {
      final restored = Session.fromJson({'id': 'x', 'host': 'h', 'user': 'u'});
      expect(restored.keyId, isEmpty);
    });

    test('copyWith updates fields', () {
      final s = Session(
        label: 'a',
        server: const ServerAddress(host: 'b', user: 'c'),
      );
      final updated = s.copyWith(
        label: 'new',
        server: s.server.copyWith(port: 3333),
      );
      expect(updated.id, s.id);
      expect(updated.label, 'new');
      expect(updated.port, 3333);
      expect(updated.host, 'b');
    });
  });

  group('SessionAuth', () {
    test('copyWith partial fields', () {
      const auth = SessionAuth(
        authType: AuthType.password,
        password: 'pw',
        keyPath: '/k',
        keyData: 'kd',
        passphrase: 'pp',
      );
      final copy = auth.copyWith(password: 'new');
      expect(copy.authType, AuthType.password);
      expect(copy.password, 'new');
      expect(copy.keyPath, '/k');
      expect(copy.keyData, 'kd');
      expect(copy.passphrase, 'pp');
    });

    test('copyWith all fields', () {
      const auth = SessionAuth();
      final copy = auth.copyWith(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      expect(copy.authType, AuthType.key);
      expect(copy.password, 'p');
      expect(copy.keyPath, 'k');
      expect(copy.keyData, 'd');
      expect(copy.passphrase, 'pp');
    });

    test('copyWith no args returns equal', () {
      const auth = SessionAuth(authType: AuthType.password, password: 'x');
      final copy = auth.copyWith();
      expect(copy, equals(auth));
    });

    test('equality for same values', () {
      const a = SessionAuth(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      const b = SessionAuth(
        authType: AuthType.key,
        password: 'p',
        keyPath: 'k',
        keyData: 'd',
        passphrase: 'pp',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different authType', () {
      const a = SessionAuth(authType: AuthType.password);
      const b = SessionAuth(authType: AuthType.key);
      expect(a, isNot(equals(b)));
    });

    test('inequality for different keyPath', () {
      const a = SessionAuth(keyPath: '/a');
      const b = SessionAuth(keyPath: '/b');
      expect(a, isNot(equals(b)));
    });

    test('inequality for different keyData', () {
      const a = SessionAuth(keyData: 'x');
      const b = SessionAuth(keyData: 'y');
      expect(a, isNot(equals(b)));
    });

    test('inequality for different passphrase', () {
      const a = SessionAuth(passphrase: 'x');
      const b = SessionAuth(passphrase: 'y');
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      const a = SessionAuth();
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      const a = SessionAuth();
      expect(a == Object(), isFalse);
    });

    test('keyId preserved in copyWith', () {
      const auth = SessionAuth(keyId: 'key-123', authType: AuthType.key);
      final copy = auth.copyWith(password: 'pw');
      expect(copy.keyId, 'key-123');
      expect(copy.password, 'pw');
    });

    test('keyId included in equality', () {
      const a = SessionAuth(keyId: 'k1');
      const b = SessionAuth(keyId: 'k2');
      expect(a, isNot(equals(b)));
    });

    test('keyId defaults to empty', () {
      const auth = SessionAuth();
      expect(auth.keyId, isEmpty);
    });
  });

  group('Session equality', () {
    test('same id and fields are equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different id makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'y',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different host makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h1', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h2', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different password makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'a'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'b'),
      );
      expect(a, isNot(equals(b)));
    });

    test('different folder makes not equal', () {
      final a = Session(
        id: 'x',
        label: 'a',
        folder: 'A',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      final b = Session(
        id: 'x',
        label: 'a',
        folder: 'B',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a, isNot(equals(b)));
    });

    test('identical returns true', () {
      final a = Session(
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a == a, isTrue);
    });

    test('not equal to other types', () {
      final a = Session(
        label: 'a',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(a == Object(), isFalse);
    });
  });

  group('Session hasCredentials', () {
    test('true with password only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyData only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyData: 'ssh-rsa AAA'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyId only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyId: 'k1'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('true with keyPath only', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(keyPath: '/home/user/.ssh/id_rsa'),
      );
      expect(s.hasCredentials, isTrue);
    });

    test('false when all credential fields are empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(s.hasCredentials, isFalse);
    });

    test('true when in-memory fields are empty but hasStoredSecret signals '
        'that the DB holds the secret — covers the startup path where the '
        'session cache is loaded without plaintext credentials', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(authType: AuthType.key, hasStoredSecret: true),
      );
      expect(s.hasCredentials, isTrue);
      expect(s.isValid, isTrue);
    });
  });

  group('Session isValid', () {
    test('true with all required fields and password', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isTrue);
    });

    test('true with keyPath credential', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyPath: '/home/.ssh/id_rsa',
        ),
      );
      expect(s.isValid, isTrue);
    });

    test('false when host is empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: '', user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when user is empty', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: ''),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when port out of range', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', port: 0, user: 'u'),
        auth: const SessionAuth(password: 'pw'),
      );
      expect(s.isValid, isFalse);
    });

    test('false when no credentials', () {
      final s = Session(
        label: 'test',
        server: const ServerAddress(host: 'h', user: 'u'),
      );
      expect(s.isValid, isFalse);
    });
  });

  group('Session.extras', () {
    Session base() => Session(
      id: 'fixed-id',
      label: 'l',
      server: const ServerAddress(host: 'h', user: 'u'),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('default is empty', () {
      expect(base().extras, isEmpty);
    });

    test('extras map is unmodifiable', () {
      final s = base().withExtras({'k': true});
      expect(() => (s.extras as dynamic)['x'] = 1, throwsUnsupportedError);
    });

    test('typed accessors return null for missing or wrong-typed entries', () {
      final s = base().withExtras({
        'flag': true,
        'name': 'r',
        'count': 7,
        'mismatch': 'oops',
      });
      expect(s.extrasBool('flag'), isTrue);
      expect(s.extrasStr('name'), 'r');
      expect(s.extrasInt('count'), 7);
      expect(s.extrasBool('missing'), isNull);
      expect(s.extrasInt('mismatch'), isNull);
    });

    test('withExtras merges and removes via null', () {
      final s = base().withExtras({'a': 1, 'b': 'x'});
      final merged = s.withExtras({'b': null, 'c': true});
      expect(merged.extras.containsKey('b'), isFalse);
      expect(merged.extras['a'], 1);
      expect(merged.extras['c'], isTrue);
    });

    test('toJson omits empty extras, fromJson tolerates missing key', () {
      final s = base();
      expect(s.toJson().containsKey('extras'), isFalse);
      final round = Session.fromJson({...s.toJson()});
      expect(round.extras, isEmpty);
    });

    test('toJson includes extras when non-empty and round-trips', () {
      final s = base().withExtras({'record': true, 'tag': 'prod'});
      final json = s.toJsonWithCredentials();
      expect(json['extras'], {'record': true, 'tag': 'prod'});
      final back = Session.fromJson(json);
      expect(back.extras['record'], isTrue);
      expect(back.extras['tag'], 'prod');
    });

    test('fromJson tolerates a JSON-encoded extras string', () {
      final s = base();
      final json = s.toJson();
      json['extras'] = '{"k":42}';
      final back = Session.fromJson(json);
      expect(back.extras['k'], 42);
    });

    test('fromJson silently drops corrupt extras', () {
      final s = base();
      final json = s.toJson();
      json['extras'] = '{not-json';
      final back = Session.fromJson(json);
      expect(back.extras, isEmpty);
    });

    test('equality includes extras', () {
      final a = base().withExtras({'k': 1});
      final b = base().copyWith().withExtras({'k': 1});
      final c = base().withExtras({'k': 2});
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
