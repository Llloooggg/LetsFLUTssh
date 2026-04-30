import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // parseConnectUri routes through `lfs_core::deeplink::
  // parse_connect_uri` — bootstrap FRB so the canonical Rust grammar
  // is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('DeepLinkHandler.parseConnectUri', () {
    test('extracts host and user', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=10.0.0.1&user=root'),
      );
      expect(config, isNotNull);
      expect(config!.host, '10.0.0.1');
      expect(config.user, 'root');
      expect(config.port, 22);
      expect(config.password, '');
    });

    test('extracts host, port, user — ignores credentials in URL', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse(
          'letsflutssh://connect?host=myserver.com&port=2222&user=admin&password=secret&key=id_rsa',
        ),
      );
      expect(config, isNotNull);
      expect(config!.host, 'myserver.com');
      expect(config.port, 2222);
      expect(config.user, 'admin');
      // Credentials are never extracted from deep links for security.
      expect(config.password, '');
      expect(config.keyPath, '');
    });

    test('returns null without host', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?user=root'),
      );
      expect(config, isNull);
    });

    test('returns null without user', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=10.0.0.1'),
      );
      expect(config, isNull);
    });

    test('rejects invalid port value', () {
      // Rust's `parse_connect_uri` treats a non-numeric `port=` as
      // a hard parse failure (returns None) rather than silently
      // defaulting to 22 — a malformed URI should not silently
      // connect to the default port the user did not type.
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&port=abc'),
      );
      expect(config, isNull);
    });

    test('returns null for empty host', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=&user=root'),
      );
      expect(config, isNull);
    });

    test('handles URL-encoded values', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=my%20server.com&user=my%20user'),
      );
      expect(config, isNotNull);
      expect(config!.host, 'my server.com');
      expect(config.user, 'my user');
    });

    test('returns null for empty user', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user='),
      );
      expect(config, isNull);
    });

    test('returns null for missing both host and user', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect'),
      );
      expect(config, isNull);
    });

    test('defaults keyPath to empty string when not provided', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u'),
      );
      expect(config, isNotNull);
      expect(config!.keyPath, '');
    });

    test('defaults password to empty string when not provided', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u'),
      );
      expect(config, isNotNull);
      expect(config!.password, '');
    });

    test('returns null for port 0', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&port=0'),
      );
      expect(config, isNull);
    });

    test('returns null for port > 65535', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&port=70000'),
      );
      expect(config, isNull);
    });

    test('returns null for negative port', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&port=-1'),
      );
      expect(config, isNull);
    });

    test('returns null for host with slash', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=a/b&user=u'),
      );
      expect(config, isNull);
    });

    test('returns null for host with backslash', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse(r'letsflutssh://connect?host=h&user=a\b'),
      );
      expect(config, isNull);
    });

    test('returns null for excessively long host', () {
      final host = 'h' * 254;
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=$host&user=u'),
      );
      expect(config, isNull);
    });

    test('returns null for host with null byte', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h%00x&user=u'),
      );
      expect(config, isNull);
    });

    test('returns null for host with control character (CR/LF)', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h%0Ax&user=u'),
      );
      expect(config, isNull);
    });

    test('returns null for user with null byte', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=a%00b'),
      );
      expect(config, isNull);
    });

    test('returns null for user with newline (config-injection guard)', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=a%0Ab'),
      );
      expect(config, isNull);
    });

    test('returns null for user with path separator', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=a/b'),
      );
      expect(config, isNull);
    });

    test('returns null for excessively long user', () {
      final user = 'u' * 257;
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=$user'),
      );
      expect(config, isNull);
    });

    test('accepts user with @ for domain-style accounts', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=alice%40corp'),
      );
      expect(config, isNotNull);
      expect(config!.user, 'alice@corp');
    });

    test('ignores key path parameter — credentials not in deep links', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&key=/etc/secret'),
      );
      expect(config, isNotNull);
      expect(config!.keyPath, '');
    });

    test('ignores valid key path — credentials not in deep links', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=h&user=u&key=mykey.pem'),
      );
      expect(config, isNotNull);
      expect(config!.keyPath, '');
    });

    test('trims whitespace from host and user', () {
      final config = DeepLinkHandler.parseConnectUri(
        Uri.parse('letsflutssh://connect?host=%20h%20&user=%20u%20'),
      );
      expect(config, isNotNull);
      expect(config!.host, 'h');
      expect(config.user, 'u');
    });
  });

  // ---------------------------------------------------------------------------
  // Routing, scheme dispatch, file-extension classification, and dedup all
  // live in `lfs_core::deeplink::DeeplinkDispatcher` now. The Rust unit
  // tests in `lfs_core/src/deeplink.rs` (`route_connect_*`,
  // `route_lfs_file*`, `route_pem_key_file`, `dispatcher_dedups_within_window`,
  // …) cover the same matrix the deleted Dart `handleUri routing`,
  // `handleCustomScheme`, `handleFileUri`, `dedup` groups used to.
  // ---------------------------------------------------------------------------

  group('DeepLinkHandler — lifecycle and callbacks', () {
    test('callbacks are initially null', () {
      final h = DeepLinkHandler();
      expect(h.onConnect, isNull);
      expect(h.onKeyFileOpened, isNull);
      expect(h.onLfsFileOpened, isNull);
      h.dispose();
    });

    test('callbacks can be set', () {
      final h = DeepLinkHandler();
      h.onConnect = (_) {};
      h.onKeyFileOpened = (_) {};
      h.onLfsFileOpened = (_) {};
      expect(h.onConnect, isNotNull);
      expect(h.onKeyFileOpened, isNotNull);
      expect(h.onLfsFileOpened, isNotNull);
      h.dispose();
    });

    test('dispose can be called without init', () {
      final h = DeepLinkHandler();
      h.dispose();
    });

    test('dispose can be called multiple times', () {
      final h = DeepLinkHandler();
      h.dispose();
      h.dispose();
    });
  });
}
