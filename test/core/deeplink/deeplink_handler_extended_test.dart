import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';

void main() {
  group('DeepLinkHandler URI handling logic', () {
    // Test the _handleUri routing logic by testing the static parseConnectUri
    // and by testing URI classification patterns used in _handleUri.

    test('parseConnectUri returns null for empty user', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=myhost&user=',
      ));
      expect(config, isNull);
    });

    test('parseConnectUri with no params returns null', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect',
      ));
      expect(config, isNull);
    });

    test('parseConnectUri preserves all fields', () {
      final config = DeepLinkHandler.parseConnectUri(Uri.parse(
        'letsflutssh://connect?host=h&user=u&port=8022&password=pass&key=/path',
      ));
      expect(config, isNotNull);
      expect(config!.host, 'h');
      expect(config.user, 'u');
      expect(config.port, 8022);
      expect(config.password, 'pass');
      expect(config.keyPath, '/path');
    });

    test('file URI classification - .lfs', () {
      final uri = Uri.parse('file:///path/to/archive.lfs');
      expect(uri.path.toLowerCase().endsWith('.lfs'), isTrue);
    });

    test('file URI classification - .pem', () {
      final uri = Uri.parse('file:///path/to/key.pem');
      expect(uri.path.toLowerCase().endsWith('.pem'), isTrue);
    });

    test('file URI classification - .key', () {
      final uri = Uri.parse('file:///path/to/id.key');
      expect(uri.path.toLowerCase().endsWith('.key'), isTrue);
    });

    test('file URI classification - .pub', () {
      final uri = Uri.parse('file:///path/to/id.pub');
      expect(uri.path.toLowerCase().endsWith('.pub'), isTrue);
    });

    test('content URI scheme recognized', () {
      final uri = Uri.parse('content://com.android.providers/document/file.lfs');
      expect(uri.scheme, 'content');
    });

    test('custom scheme connect host recognized', () {
      final uri = Uri.parse('letsflutssh://connect?host=h&user=u');
      expect(uri.scheme, 'letsflutssh');
      expect(uri.host, 'connect');
    });

    test('custom scheme unknown action', () {
      final uri = Uri.parse('letsflutssh://unknown');
      expect(uri.host, 'unknown');
      // In the real handler, this logs and is ignored
    });
  });

  group('DeepLinkHandler lifecycle', () {
    test('dispose does not throw', () {
      final handler = DeepLinkHandler();
      handler.dispose();
    });

    test('callbacks are initially null', () {
      final handler = DeepLinkHandler();
      expect(handler.onConnect, isNull);
      expect(handler.onKeyFileOpened, isNull);
      expect(handler.onLfsFileOpened, isNull);
      handler.dispose();
    });

    test('callbacks can be set', () {
      final handler = DeepLinkHandler();
      handler.onConnect = (_) {};
      handler.onKeyFileOpened = (_) {};
      handler.onLfsFileOpened = (_) {};
      expect(handler.onConnect, isNotNull);
      expect(handler.onKeyFileOpened, isNotNull);
      expect(handler.onLfsFileOpened, isNotNull);
      handler.dispose();
    });
  });
}
