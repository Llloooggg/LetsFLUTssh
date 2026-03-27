import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  // ─── ServerAddress ───────────────────────────────────────────────

  group('ServerAddress', () {
    test('default port is 22', () {
      const addr = ServerAddress(host: 'example.com', user: 'root');
      expect(addr.port, 22);
    });

    test('effectivePort returns port when > 0', () {
      const addr = ServerAddress(host: 'h', user: 'u', port: 2222);
      expect(addr.effectivePort, 2222);
    });

    test('effectivePort returns 22 when port is 0', () {
      const addr = ServerAddress(host: 'h', user: 'u', port: 0);
      expect(addr.effectivePort, 22);
    });

    test('effectivePort returns 22 when port is negative', () {
      const addr = ServerAddress(host: 'h', user: 'u', port: -1);
      expect(addr.effectivePort, 22);
    });

    test('displayName uses effectivePort', () {
      const addr = ServerAddress(host: 'srv', user: 'admin', port: 0);
      expect(addr.displayName, 'admin@srv:22');
    });

    test('displayName with custom port', () {
      const addr = ServerAddress(host: 'srv', user: 'admin', port: 8022);
      expect(addr.displayName, 'admin@srv:8022');
    });

    test('copyWith replaces fields', () {
      const original = ServerAddress(host: 'a', user: 'b', port: 22);
      final copy = original.copyWith(host: 'x', port: 3333);
      expect(copy.host, 'x');
      expect(copy.port, 3333);
      expect(copy.user, 'b');
    });

    test('copyWith with no args returns equivalent object', () {
      const original = ServerAddress(host: 'a', user: 'b', port: 22);
      final copy = original.copyWith();
      expect(copy, original);
    });

    test('equality — same fields are equal', () {
      const a = ServerAddress(host: 'h', user: 'u', port: 22);
      const b = ServerAddress(host: 'h', user: 'u', port: 22);
      expect(a, b);
    });

    test('equality — identical returns true', () {
      const a = ServerAddress(host: 'h', user: 'u');
      expect(a == a, isTrue);
    });

    test('inequality — different host', () {
      const a = ServerAddress(host: 'a', user: 'u');
      const b = ServerAddress(host: 'b', user: 'u');
      expect(a, isNot(b));
    });

    test('inequality — different port', () {
      const a = ServerAddress(host: 'h', user: 'u', port: 22);
      const b = ServerAddress(host: 'h', user: 'u', port: 23);
      expect(a, isNot(b));
    });

    test('inequality — different user', () {
      const a = ServerAddress(host: 'h', user: 'a');
      const b = ServerAddress(host: 'h', user: 'b');
      expect(a, isNot(b));
    });

    test('inequality — different type', () {
      const a = ServerAddress(host: 'h', user: 'u');
      // ignore: unrelated_type_equality_checks
      expect(a == 'not a ServerAddress', isFalse);
    });

    test('hashCode — equal objects have equal hashCode', () {
      const a = ServerAddress(host: 'h', user: 'u', port: 22);
      const b = ServerAddress(host: 'h', user: 'u', port: 22);
      expect(a.hashCode, b.hashCode);
    });

    test('hashCode — different objects likely have different hashCode', () {
      const a = ServerAddress(host: 'h', user: 'u', port: 22);
      const b = ServerAddress(host: 'h', user: 'u', port: 23);
      // Not guaranteed but highly likely for distinct inputs
      expect(a.hashCode, isNot(b.hashCode));
    });
  });

  // ─── SshAuth ─────────────────────────────────────────────────────

  group('SshAuth', () {
    test('defaults are empty strings', () {
      const auth = SshAuth();
      expect(auth.password, '');
      expect(auth.keyPath, '');
      expect(auth.keyData, '');
      expect(auth.passphrase, '');
    });

    test('hasAuth is false when all fields empty', () {
      const auth = SshAuth();
      expect(auth.hasAuth, isFalse);
    });

    test('hasAuth is true with password', () {
      const auth = SshAuth(password: 'secret');
      expect(auth.hasAuth, isTrue);
    });

    test('hasAuth is true with keyPath', () {
      const auth = SshAuth(keyPath: '/path/to/key');
      expect(auth.hasAuth, isTrue);
    });

    test('hasAuth is true with keyData', () {
      const auth = SshAuth(keyData: '-----BEGIN RSA PRIVATE KEY-----');
      expect(auth.hasAuth, isTrue);
    });

    test('hasAuth ignores passphrase alone', () {
      const auth = SshAuth(passphrase: 'pass');
      expect(auth.hasAuth, isFalse);
    });

    test('copyWith replaces fields', () {
      const original = SshAuth(password: 'p', keyPath: 'k');
      final copy = original.copyWith(password: 'new', passphrase: 'pp');
      expect(copy.password, 'new');
      expect(copy.keyPath, 'k');
      expect(copy.keyData, '');
      expect(copy.passphrase, 'pp');
    });

    test('copyWith with no args returns equivalent object', () {
      const original = SshAuth(password: 'p');
      final copy = original.copyWith();
      expect(copy, original);
    });

    test('equality — same fields are equal', () {
      const a = SshAuth(password: 'p', keyPath: 'k');
      const b = SshAuth(password: 'p', keyPath: 'k');
      expect(a, b);
    });

    test('equality — identical returns true', () {
      const a = SshAuth(password: 'p');
      expect(a == a, isTrue);
    });

    test('inequality — different password', () {
      const a = SshAuth(password: 'a');
      const b = SshAuth(password: 'b');
      expect(a, isNot(b));
    });

    test('inequality — different keyPath', () {
      const a = SshAuth(keyPath: 'a');
      const b = SshAuth(keyPath: 'b');
      expect(a, isNot(b));
    });

    test('inequality — different keyData', () {
      const a = SshAuth(keyData: 'a');
      const b = SshAuth(keyData: 'b');
      expect(a, isNot(b));
    });

    test('inequality — different passphrase', () {
      const a = SshAuth(passphrase: 'a');
      const b = SshAuth(passphrase: 'b');
      expect(a, isNot(b));
    });

    test('inequality — different type', () {
      const a = SshAuth();
      // ignore: unrelated_type_equality_checks
      expect(a == 'not SshAuth', isFalse);
    });

    test('hashCode — equal objects have equal hashCode', () {
      const a = SshAuth(password: 'p', keyPath: 'k');
      const b = SshAuth(password: 'p', keyPath: 'k');
      expect(a.hashCode, b.hashCode);
    });

    test('hashCode — different objects likely have different hashCode', () {
      const a = SshAuth(password: 'a');
      const b = SshAuth(password: 'b');
      expect(a.hashCode, isNot(b.hashCode));
    });
  });

  // ─── SSHConfig ───────────────────────────────────────────────────

  group('SSHConfig', () {
    const server = ServerAddress(host: 'example.com', user: 'root', port: 22);
    const auth = SshAuth(password: 'secret');

    group('convenience accessors', () {
      const config = SSHConfig(server: server, auth: auth);

      test('host delegates to server.host', () {
        expect(config.host, 'example.com');
      });

      test('port delegates to server.port', () {
        expect(config.port, 22);
      });

      test('user delegates to server.user', () {
        expect(config.user, 'root');
      });

      test('effectivePort delegates to server.effectivePort', () {
        expect(config.effectivePort, 22);
      });

      test('displayName delegates to server.displayName', () {
        expect(config.displayName, 'root@example.com:22');
      });

      test('password delegates to auth.password', () {
        expect(config.password, 'secret');
      });

      test('keyPath delegates to auth.keyPath', () {
        expect(config.keyPath, '');
      });

      test('keyData delegates to auth.keyData', () {
        expect(config.keyData, '');
      });

      test('passphrase delegates to auth.passphrase', () {
        expect(config.passphrase, '');
      });

      test('hasAuth delegates to auth.hasAuth', () {
        expect(config.hasAuth, isTrue);
      });
    });

    group('defaults', () {
      test('default auth is empty SshAuth', () {
        const config = SSHConfig(server: server);
        expect(config.auth, const SshAuth());
        expect(config.hasAuth, isFalse);
      });

      test('default keepAliveSec is 30', () {
        const config = SSHConfig(server: server);
        expect(config.keepAliveSec, 30);
      });

      test('default timeoutSec is 10', () {
        const config = SSHConfig(server: server);
        expect(config.timeoutSec, 10);
      });
    });

    group('validate', () {
      test('returns null for valid config', () {
        const config = SSHConfig(server: server, auth: auth);
        expect(config.validate(), isNull);
      });

      test('rejects empty host', () {
        const config = SSHConfig(
          server: ServerAddress(host: '', user: 'root'),
        );
        expect(config.validate(), 'Host is required');
      });

      test('rejects whitespace-only host', () {
        const config = SSHConfig(
          server: ServerAddress(host: '   ', user: 'root'),
        );
        expect(config.validate(), 'Host is required');
      });

      test('rejects port 0', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u', port: 0),
        );
        expect(config.validate(), 'Port must be 1-65535');
      });

      test('rejects negative port', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u', port: -1),
        );
        expect(config.validate(), 'Port must be 1-65535');
      });

      test('rejects port above 65535', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u', port: 65536),
        );
        expect(config.validate(), 'Port must be 1-65535');
      });

      test('accepts port 1', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u', port: 1),
          auth: auth,
        );
        expect(config.validate(), isNull);
      });

      test('accepts port 65535', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: 'u', port: 65535),
          auth: auth,
        );
        expect(config.validate(), isNull);
      });

      test('rejects empty user', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: ''),
        );
        expect(config.validate(), 'Username is required');
      });

      test('rejects whitespace-only user', () {
        const config = SSHConfig(
          server: ServerAddress(host: 'h', user: '   '),
        );
        expect(config.validate(), 'Username is required');
      });

      test('rejects missing auth', () {
        const config = SSHConfig(server: server);
        expect(config.validate(), 'Password or SSH key is required');
      });

      test('rejects negative keepAliveSec', () {
        const config = SSHConfig(server: server, auth: auth, keepAliveSec: -1);
        expect(config.validate(), 'Keep-alive must be non-negative');
      });

      test('accepts keepAliveSec 0', () {
        const config = SSHConfig(server: server, auth: auth, keepAliveSec: 0);
        expect(config.validate(), isNull);
      });

      test('rejects timeoutSec 0', () {
        const config = SSHConfig(server: server, auth: auth, timeoutSec: 0);
        expect(config.validate(), 'Timeout must be at least 1 second');
      });

      test('rejects negative timeoutSec', () {
        const config = SSHConfig(server: server, auth: auth, timeoutSec: -5);
        expect(config.validate(), 'Timeout must be at least 1 second');
      });

      test('accepts timeoutSec 1', () {
        const config = SSHConfig(server: server, auth: auth, timeoutSec: 1);
        expect(config.validate(), isNull);
      });

      test('validates in order — host checked before port', () {
        const config = SSHConfig(
          server: ServerAddress(host: '', user: 'u', port: 0),
        );
        expect(config.validate(), 'Host is required');
      });
    });

    group('copyWith', () {
      test('replaces server', () {
        const config = SSHConfig(server: server, auth: auth);
        const newServer = ServerAddress(host: 'new', user: 'new');
        final copy = config.copyWith(server: newServer);
        expect(copy.server, newServer);
        expect(copy.auth, auth);
        expect(copy.keepAliveSec, 30);
      });

      test('replaces auth', () {
        const config = SSHConfig(server: server, auth: auth);
        const newAuth = SshAuth(keyPath: '/key');
        final copy = config.copyWith(auth: newAuth);
        expect(copy.server, server);
        expect(copy.auth, newAuth);
      });

      test('replaces keepAliveSec', () {
        const config = SSHConfig(server: server);
        final copy = config.copyWith(keepAliveSec: 60);
        expect(copy.keepAliveSec, 60);
      });

      test('replaces timeoutSec', () {
        const config = SSHConfig(server: server);
        final copy = config.copyWith(timeoutSec: 30);
        expect(copy.timeoutSec, 30);
      });

      test('no args returns equivalent object', () {
        const config = SSHConfig(server: server, auth: auth);
        final copy = config.copyWith();
        expect(copy, config);
      });
    });

    group('equality', () {
      test('same fields are equal', () {
        const a = SSHConfig(server: server, auth: auth, keepAliveSec: 30);
        const b = SSHConfig(server: server, auth: auth, keepAliveSec: 30);
        expect(a, b);
      });

      test('identical returns true', () {
        const a = SSHConfig(server: server);
        expect(a == a, isTrue);
      });

      test('different server not equal', () {
        const a = SSHConfig(server: server);
        const b = SSHConfig(
          server: ServerAddress(host: 'other', user: 'root'),
        );
        expect(a, isNot(b));
      });

      test('different auth not equal', () {
        const a = SSHConfig(server: server, auth: auth);
        const b = SSHConfig(server: server, auth: SshAuth(password: 'other'));
        expect(a, isNot(b));
      });

      test('different keepAliveSec not equal', () {
        const a = SSHConfig(server: server, keepAliveSec: 30);
        const b = SSHConfig(server: server, keepAliveSec: 60);
        expect(a, isNot(b));
      });

      test('different timeoutSec not equal', () {
        const a = SSHConfig(server: server, timeoutSec: 10);
        const b = SSHConfig(server: server, timeoutSec: 20);
        expect(a, isNot(b));
      });

      test('different type not equal', () {
        const a = SSHConfig(server: server);
        // ignore: unrelated_type_equality_checks
        expect(a == 'not SSHConfig', isFalse);
      });
    });

    group('hashCode', () {
      test('equal objects have equal hashCode', () {
        const a = SSHConfig(server: server, auth: auth);
        const b = SSHConfig(server: server, auth: auth);
        expect(a.hashCode, b.hashCode);
      });

      test('different objects likely have different hashCode', () {
        const a = SSHConfig(server: server, keepAliveSec: 30);
        const b = SSHConfig(server: server, keepAliveSec: 60);
        expect(a.hashCode, isNot(b.hashCode));
      });
    });
  });
}
