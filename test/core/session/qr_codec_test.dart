import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('encodeSessionCompact', () {
    Session base({
      String label = 'lab',
      String host = 'example.com',
      String user = 'alice',
      int port = 22,
      String folder = '',
      AuthType authType = AuthType.password,
      String password = '',
    }) => Session(
      label: label,
      server: ServerAddress(host: host, user: user, port: port),
      auth: SessionAuth(authType: authType, password: password),
      folder: folder,
    );

    test('emits only required keys for the default shape', () {
      final m = encodeSessionCompact(base());
      expect(m, {'l': 'lab', 'h': 'example.com', 'u': 'alice'});
    });

    test('default port collapses out of the payload', () {
      final m = encodeSessionCompact(base(port: 22));
      expect(m.containsKey('p'), isFalse);
    });

    test('non-default port surfaces under p', () {
      final m = encodeSessionCompact(base(port: 2222));
      expect(m['p'], 2222);
    });

    test('non-empty folder surfaces under g', () {
      final m = encodeSessionCompact(base(folder: 'infra/prod'));
      expect(m['g'], 'infra/prod');
    });

    test('auth other than password surfaces under a as enum name', () {
      final m = encodeSessionCompact(base(authType: AuthType.key));
      expect(m['a'], 'key');
    });

    test('keyId + isManagerKey surface under ki + mg', () {
      final m = encodeSessionCompact(
        base(authType: AuthType.key),
        keyId: 'k0',
        isManagerKey: true,
      );
      expect(m['ki'], 'k0');
      expect(m['mg'], 1);
    });

    test('password is omitted unless includePasswords opts in', () {
      final off = encodeSessionCompact(base(password: 'secret'));
      expect(off.containsKey('pw'), isFalse);
      final on = encodeSessionCompact(
        base(password: 'secret'),
        includePasswords: true,
      );
      expect(on['pw'], 'secret');
    });

    test('opt-in with empty password still omits the field', () {
      final m = encodeSessionCompact(base(), includePasswords: true);
      expect(m.containsKey('pw'), isFalse);
    });
  });
}
