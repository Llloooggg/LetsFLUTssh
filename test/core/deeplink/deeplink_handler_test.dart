import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';

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
  });
}
