import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('DeepLinkHandler.parseConnectUri', () {
    test('extracts host and user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=10.0.0.1&user=root',
      ));
      expect(config, isNotNull);
      expect(config!.host, '10.0.0.1');
      expect(config.user, 'root');
      expect(config.port, 22);
      expect(config.password, '');
    });

    test('extracts all params', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=myserver.com&port=2222&user=admin&password=secret&key=/home/me/.ssh/id_rsa',
      ));
      expect(config, isNotNull);
      expect(config!.host, 'myserver.com');
      expect(config.port, 2222);
      expect(config.user, 'admin');
      expect(config.password, 'secret');
      expect(config.keyPath, '/home/me/.ssh/id_rsa');
    });

    test('returns null without host', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?user=root',
      ));
      expect(config, isNull);
    });

    test('returns null without user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=10.0.0.1',
      ));
      expect(config, isNull);
    });

    test('defaults port to 22 for invalid value', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&port=abc',
      ));
      expect(config, isNotNull);
      expect(config!.port, 22);
    });

    test('returns null for empty host', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=&user=root',
      ));
      expect(config, isNull);
    });

    test('handles URL-encoded values', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=my%20server.com&user=my%20user',
      ));
      expect(config, isNotNull);
      expect(config!.host, 'my server.com');
      expect(config.user, 'my user');
    });

    test('returns null for empty user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=',
      ));
      expect(config, isNull);
    });

    test('returns null for missing both host and user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect',
      ));
      expect(config, isNull);
    });

    test('defaults keyPath to empty string when not provided', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u',
      ));
      expect(config, isNotNull);
      expect(config!.keyPath, '');
    });

    test('defaults password to empty string when not provided', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u',
      ));
      expect(config, isNotNull);
      expect(config!.password, '');
    });

    test('returns null for port 0', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&port=0',
      ));
      expect(config, isNull);
    });

    test('returns null for port > 65535', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&port=70000',
      ));
      expect(config, isNull);
    });

    test('returns null for negative port', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&port=-1',
      ));
      expect(config, isNull);
    });

    test('returns null for host with slash', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h/evil&user=u',
      ));
      expect(config, isNull);
    });

    test('returns null for host with backslash', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h%5Cevil&user=u',
      ));
      expect(config, isNull);
    });

    test('returns null for excessively long host', () {
      final longHost = 'a' * 300;
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=$longHost&user=u',
      ));
      expect(config, isNull);
    });

    test('rejects key path with path traversal', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&key=../../etc/passwd',
      ));
      expect(config, isNull);
    });

    test('accepts valid key path without traversal', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&key=/home/user/.ssh/id_rsa',
      ));
      expect(config, isNotNull);
      expect(config!.keyPath, '/home/user/.ssh/id_rsa');
    });

    test('trims whitespace from host and user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=%20h%20&user=%20u%20',
      ));
      expect(config, isNotNull);
      expect(config!.host, 'h');
      expect(config.user, 'u');
    });
  });

  group('DeepLinkHandler.handleUri routing', () {
    late DeepLinkHandler handler;

    setUp(() {
      handler = DeepLinkHandler();
    });

    tearDown(() {
      handler.dispose();
    });

    test('routes letsflutssh scheme to handleCustomScheme → onConnect', () {
      SSHConfig? received;
      handler.onConnect = (c) => received = c;

      handler.handleUri(Uri.parse('letsflutssh://connect?host=h&user=u'));
      expect(received, isNotNull);
      expect(received!.host, 'h');
    });

    test('routes file scheme .lfs to onLfsFileOpened', () {
      String? received;
      handler.onLfsFileOpened = (p) => received = p;

      handler.handleUri(Uri.parse('file:///tmp/archive.lfs'));
      expect(received, isNotNull);
      expect(received, contains('archive.lfs'));
    });

    test('routes file scheme .pem to onKeyFileOpened', () {
      String? received;
      handler.onKeyFileOpened = (p) => received = p;

      handler.handleUri(Uri.parse('file:///tmp/id.pem'));
      expect(received, isNotNull);
      expect(received, contains('id.pem'));
    });

    test('routes file scheme .key to onKeyFileOpened', () {
      String? received;
      handler.onKeyFileOpened = (p) => received = p;

      handler.handleUri(Uri.parse('file:///tmp/id.key'));
      expect(received, isNotNull);
    });

    test('routes file scheme .pub to onKeyFileOpened', () {
      String? received;
      handler.onKeyFileOpened = (p) => received = p;

      handler.handleUri(Uri.parse('file:///tmp/id.pub'));
      expect(received, isNotNull);
    });

    test('routes content scheme to handleFileUri', () {
      // content:// URIs go through handleFileUri path
      // but toFilePath() only works with file:// scheme,
      // so we test the routing reaches handleFileUri via file://
      String? received;
      handler.onLfsFileOpened = (p) => received = p;

      handler.handleUri(Uri.parse('file:///provider/archive.lfs'));
      expect(received, isNotNull);
    });

    test('ignores unknown scheme without crash', () {
      handler.handleUri(Uri.parse('https://example.com'));
      // Should not throw, just log
    });

    test('ignores unsupported file type', () {
      String? key;
      String? lfs;
      handler.onKeyFileOpened = (p) => key = p;
      handler.onLfsFileOpened = (p) => lfs = p;

      handler.handleUri(Uri.parse('file:///tmp/readme.txt'));
      expect(key, isNull);
      expect(lfs, isNull);
    });
  });

  group('DeepLinkHandler.handleCustomScheme', () {
    late DeepLinkHandler handler;

    setUp(() {
      handler = DeepLinkHandler();
    });

    tearDown(() {
      handler.dispose();
    });

    test('connect action calls onConnect with valid params', () {
      SSHConfig? received;
      handler.onConnect = (c) => received = c;

      handler.handleCustomScheme(Uri.parse('letsflutssh://connect?host=h&user=u'));
      expect(received, isNotNull);
    });

    test('connect action with invalid params does not call onConnect', () {
      SSHConfig? received;
      handler.onConnect = (c) => received = c;

      handler.handleCustomScheme(Uri.parse('letsflutssh://connect?host=&user='));
      expect(received, isNull);
    });

    test('unknown action does not call onConnect', () {
      SSHConfig? received;
      handler.onConnect = (c) => received = c;

      handler.handleCustomScheme(Uri.parse('letsflutssh://settings'));
      expect(received, isNull);
    });

    test('onConnect null does not crash', () {
      handler.onConnect = null;
      handler.handleCustomScheme(Uri.parse('letsflutssh://connect?host=h&user=u'));
      // Should not throw
    });
  });

  group('DeepLinkHandler.handleFileUri', () {
    late DeepLinkHandler handler;

    setUp(() {
      handler = DeepLinkHandler();
    });

    tearDown(() {
      handler.dispose();
    });

    test('onLfsFileOpened null does not crash', () {
      handler.onLfsFileOpened = null;
      handler.handleFileUri(Uri.parse('file:///tmp/a.lfs'));
    });

    test('onKeyFileOpened null does not crash', () {
      handler.onKeyFileOpened = null;
      handler.handleFileUri(Uri.parse('file:///tmp/a.pem'));
    });

    test('case insensitive file extension matching', () {
      String? received;
      handler.onLfsFileOpened = (p) => received = p;

      handler.handleFileUri(Uri.parse('file:///tmp/Archive.LFS'));
      expect(received, isNotNull);
    });
  });

  group('DeepLinkHandler callbacks', () {
    late DeepLinkHandler handler;

    setUp(() {
      handler = DeepLinkHandler();
    });

    tearDown(() {
      handler.dispose();
    });

    test('onConnect callback is initially null', () {
      expect(handler.onConnect, isNull);
    });

    test('onKeyFileOpened callback is initially null', () {
      expect(handler.onKeyFileOpened, isNull);
    });

    test('onLfsFileOpened callback is initially null', () {
      expect(handler.onLfsFileOpened, isNull);
    });

    test('onConnect callback can be set', () {
      handler.onConnect = (_) {};
      expect(handler.onConnect, isNotNull);
    });

    test('onKeyFileOpened callback can be set', () {
      handler.onKeyFileOpened = (_) {};
      expect(handler.onKeyFileOpened, isNotNull);
    });

    test('onLfsFileOpened callback can be set', () {
      handler.onLfsFileOpened = (_) {};
      expect(handler.onLfsFileOpened, isNotNull);
    });

    test('dispose can be called without init', () {
      // Should not throw
      handler.dispose();
    });

    test('dispose can be called multiple times', () {
      handler.dispose();
      handler.dispose();
    });
  });
}
