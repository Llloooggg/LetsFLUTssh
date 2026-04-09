import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';

/// Fuzz tests for [DeepLinkHandler.parseConnectUri].
///
/// Verifies that no malformed URI can crash the parser.
void main() {
  group('Fuzz DeepLinkHandler.parseConnectUri', () {
    final rng = Random(42);

    test('handles 1000 random URIs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final uri = _randomConnectUri(rng);
        // Must never throw — returns null on invalid input
        DeepLinkHandler.parseConnectUri(uri);
      }
    });

    test('rejects URIs with invalid hosts', () {
      final hosts = [
        '',
        '/',
        '\\',
        '\x00',
        'a' * 254,
        '../etc/passwd',
        'host/path',
        'host\\path',
        'host\x00null',
      ];
      for (final host in hosts) {
        final uri = Uri(
          scheme: 'letsflutssh',
          host: 'connect', // URI host = 'connect', param host = test value
          queryParameters: {'host': host, 'user': 'root'},
        );
        final result = DeepLinkHandler.parseConnectUri(uri);
        // Must either return null or a valid SSHConfig — never crash
        if (result != null) {
          expect(result.server.host, isNotEmpty);
        }
      }
    });

    test('handles extreme port values', () {
      final ports = [
        '-1',
        '0',
        '1',
        '22',
        '65535',
        '65536',
        '99999',
        '-99999',
        'abc',
        '',
        '2147483647',
        '-2147483648',
        '9999999999999',
        'NaN',
        'Infinity',
      ];
      for (final port in ports) {
        final uri = Uri(
          scheme: 'letsflutssh',
          host: 'connect',
          queryParameters: {
            'host': 'example.com',
            'user': 'root',
            'port': port,
          },
        );
        final result = DeepLinkHandler.parseConnectUri(uri);
        if (result != null) {
          expect(result.server.port, greaterThanOrEqualTo(1));
          expect(result.server.port, lessThanOrEqualTo(65535));
        }
      }
    });

    test('handles missing required parameters', () {
      final uris = [
        Uri.parse('letsflutssh://connect'),
        Uri.parse('letsflutssh://connect?host=example.com'),
        Uri.parse('letsflutssh://connect?user=root'),
        Uri.parse('letsflutssh://connect?host=&user='),
        Uri.parse('letsflutssh://connect?host=  &user=  '),
      ];
      for (final uri in uris) {
        expect(DeepLinkHandler.parseConnectUri(uri), isNull);
      }
    });

    test('handles special characters in user parameter', () {
      final users = [
        '\x00',
        '  ',
        '\t\n',
        'user@host',
        "user'; DROP TABLE--",
        '<script>',
        'a' * 10000,
      ];
      for (final user in users) {
        final uri = Uri(
          scheme: 'letsflutssh',
          host: 'connect',
          queryParameters: {'host': 'example.com', 'user': user},
        );
        // Must never crash
        DeepLinkHandler.parseConnectUri(uri);
      }
    });

    test('handles extra unknown parameters gracefully', () {
      final uri = Uri(
        scheme: 'letsflutssh',
        host: 'connect',
        queryParameters: {
          'host': 'example.com',
          'user': 'root',
          'port': '22',
          'password': 'secret',
          '__proto__': 'polluted',
          'extra': 'ignored',
        },
      );
      final result = DeepLinkHandler.parseConnectUri(uri);
      expect(result, isNotNull);
      expect(result!.server.host, 'example.com');
    });
  });
}

Uri _randomConnectUri(Random rng) {
  final schemes = ['letsflutssh', 'https', 'ssh', ''];
  final uriHosts = ['connect', 'import', '', 'example.com'];

  final params = <String, String>{};
  if (rng.nextBool()) params['host'] = _randomHost(rng);
  if (rng.nextBool()) params['user'] = _randomString(rng);
  if (rng.nextBool()) params['port'] = '${rng.nextInt(100000) - 1000}';

  return Uri(
    scheme: schemes[rng.nextInt(schemes.length)],
    host: uriHosts[rng.nextInt(uriHosts.length)],
    queryParameters: params.isEmpty ? null : params,
  );
}

String _randomHost(Random rng) {
  final hosts = [
    '',
    'example.com',
    '192.168.1.1',
    '::1',
    'a' * 300,
    'host/path',
    'host\x00null',
    'host\\back',
    '   ',
  ];
  return hosts[rng.nextInt(hosts.length)];
}

String _randomString(Random rng) {
  final pool = ['', 'root', 'admin', '\x00', '  spaces  ', 'a' * 5000];
  return pool[rng.nextInt(pool.length)];
}
