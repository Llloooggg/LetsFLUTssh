import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

/// Fuzz tests for QR codec ([decodeExportPayload], [decodeImportUri]).
///
/// Verifies that no malformed payload can cause an unhandled crash.
void main() {
  group('Fuzz decodeExportPayload', () {
    final rng = Random(42);

    test('handles 1000 random payloads without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final payload = _randomQrPayload(rng);
        // Must never throw — returns null on invalid input
        decodeExportPayload(payload);
      }
    });

    test('handles empty string', () {
      expect(decodeExportPayload(''), isNull);
    });

    test('handles non-JSON strings', () {
      final inputs = [
        'not json',
        '{invalid',
        '{"v":1',
        '[1,2,3]',
        'null',
        'true',
        '42',
        '\x00\x01\x02',
        '🔑🔑🔑',
        '<xml>data</xml>',
      ];
      for (final input in inputs) {
        expect(decodeExportPayload(input), isNull);
      }
    });

    test('handles wrong version numbers', () {
      // Build payloads with explicit wrong `v` field values as
      // base64(JSON) to reach the old-format parser path.
      final wrongVersions = [-999, -1, 0, 2, 3, 99, 9999999];
      for (final v in wrongVersions) {
        final json = jsonEncode({
          'v': v,
          's': [
            {'l': 'test', 'h': 'host', 'u': 'user'},
          ],
        });
        final encoded = base64Url.encode(utf8.encode(json));
        // Must never throw
        decodeExportPayload(encoded);
      }

      // Also test non-integer version values
      final badTypeVersions = [
        {'v': 'abc', 's': []},
        {'v': null, 's': []},
        {'v': true, 's': []},
        {
          'v': [1],
          's': [],
        },
        {'v': 1.5, 's': []},
        {'s': []}, // missing v entirely
      ];
      for (final payload in badTypeVersions) {
        final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
        // Must never throw
        decodeExportPayload(encoded);
      }
    });

    test('handles malformed session entries', () {
      // After hardening (`is List` / `whereType` instead of `as` casts),
      // most malformed shapes no longer crash and instead surface as a
      // payload with empty sessions. The contract is "must never throw,
      // and never silently insert garbage" — not "must return null".
      final tolerantPayloads = [
        '{"v":1,"s":"not_a_list"}', // s is a string, not a list — skipped
        '{"v":1,"s":[null]}', // null entry — skipped
        '{"v":1,"s":["string"]}', // wrong shape — skipped
        '{"v":1,"s":[42]}', // wrong shape — skipped
        '{"v":1,"s":[true]}', // wrong shape — skipped
        '{"v":1,"s":[[]]}', // wrong shape — skipped
      ];
      for (final json in tolerantPayloads) {
        final encoded = base64Url.encode(utf8.encode(json));
        final result = decodeExportPayload(encoded);
        expect(result, isNotNull, reason: 'Payload: $json');
        expect(result!.sessions, isEmpty, reason: 'Payload: $json');
      }

      // Type errors deeper inside _decodeSession (wrong types for required
      // fields like port=NaN) still trip the outer catch and return null —
      // those entries genuinely violate the schema, not just its container
      // shape.
      const stillBad = '{"v":1,"s":[{"l":123,"h":456,"p":"NaN"}]}';
      final encodedBad = base64Url.encode(utf8.encode(stillBad));
      expect(decodeExportPayload(encodedBad), isNull);

      // These are structurally valid and should decode with defaults.
      // Use encodeExportPayload for proper base64(deflate(JSON)) format.
      final validSessions = [
        Session(
          label: '',
          server: const ServerAddress(host: '', user: ''),
        ),
      ];
      final validEncoded = encodeExportPayload(validSessions);
      final result = decodeExportPayload(validEncoded);
      expect(result, isNotNull, reason: 'Encoded sessions should decode');
      expect(result!.sessions, hasLength(1));
    });

    test('handles deeply nested payloads', () {
      // Build actual deeply nested JSON structures and encode as base64
      // to verify the parser handles unexpected nesting gracefully.
      Object nested = 'leaf';
      for (var i = 0; i < 50; i++) {
        nested = {'nested': nested};
      }

      final deepPayloads = [
        // Deeply nested object where 's' is expected
        {'v': 1, 's': nested},
        // Deeply nested inside session entries
        {
          'v': 1,
          's': [nested],
        },
        // Deeply nested list
        {
          'v': 1,
          's': [
            [
              [
                [
                  [
                    ['deep'],
                  ],
                ],
              ],
            ],
          ],
        },
        // Session entry with deeply nested field values
        {
          'v': 1,
          's': [
            {'l': nested, 'h': nested, 'u': nested},
          ],
        },
      ];

      for (final payload in deepPayloads) {
        final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
        // Must never throw
        decodeExportPayload(encoded);
      }
    });

    test('handles very large payloads', () {
      final sessions = List.generate(
        10000,
        (i) => Session(
          label: 'session_$i',
          server: ServerAddress(host: 'host_$i', user: 'user_$i'),
        ),
      );
      final encoded = encodeExportPayload(sessions);
      final result = decodeExportPayload(encoded);
      expect(result, isNotNull);
      expect(result!.sessions.length, 10000);
    });
  });

  group('Fuzz decodeImportUri', () {
    final rng = Random(42);

    test('handles 1000 random URIs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final uri = _randomImportUri(rng);
        // Must never throw
        decodeImportUri(uri);
      }
    });

    test('handles URIs with invalid base64', () {
      final uris = [
        Uri.parse('letsflutssh://import?d=!!!invalid!!!'),
        Uri.parse('letsflutssh://import?d====='),
        Uri.parse('letsflutssh://import?d=\x00\x01'),
        Uri.parse('letsflutssh://import?d='),
        Uri.parse('letsflutssh://import'),
        Uri.parse('letsflutssh://wrong_host?d=dGVzdA=='),
        Uri.parse('https://example.com/import?d=dGVzdA=='),
      ];
      for (final uri in uris) {
        expect(decodeImportUri(uri), isNull);
      }
    });

    test('handles URI with valid base64 but invalid JSON', () {
      final b64 = base64Url.encode(utf8.encode('not json'));
      final uri = Uri.parse('letsflutssh://import?d=$b64');
      expect(decodeImportUri(uri), isNull);
    });
  });
}

String _randomQrPayload(Random rng) {
  switch (rng.nextInt(6)) {
    case 0:
      return _randomString(rng);
    case 1:
      return jsonEncode(_randomJsonValue(rng));
    case 2:
      // Valid structure, random content
      return jsonEncode({
        'v': rng.nextInt(5),
        's': List.generate(
          rng.nextInt(5),
          (_) => {
            if (rng.nextBool()) 'l': _randomString(rng),
            if (rng.nextBool()) 'h': _randomString(rng),
            if (rng.nextBool()) 'u': _randomString(rng),
            if (rng.nextBool()) 'p': rng.nextInt(70000) - 1000,
            if (rng.nextBool()) 'a': _randomString(rng),
          },
        ),
        if (rng.nextBool()) 'eg': _randomValue(rng),
      });
    case 3:
      // Truncated JSON
      final full = jsonEncode({
        'v': 1,
        's': [
          {'l': 'x'},
        ],
      });
      return full.substring(0, rng.nextInt(full.length));
    case 4:
      return '';
    default:
      return String.fromCharCodes(
        List.generate(rng.nextInt(200), (_) => rng.nextInt(128)),
      );
  }
}

Uri _randomImportUri(Random rng) {
  final schemes = ['letsflutssh', 'https', 'ssh', 'file', ''];
  final hosts = ['import', 'connect', 'wrong', '', 'example.com'];
  final scheme = schemes[rng.nextInt(schemes.length)];
  final host = hosts[rng.nextInt(hosts.length)];

  String? d;
  switch (rng.nextInt(4)) {
    case 0:
      d = base64Url.encode(utf8.encode(_randomQrPayload(rng)));
    case 1:
      d = _randomString(rng);
    case 2:
      d = null;
    default:
      d = '';
  }

  return Uri(
    scheme: scheme,
    host: host,
    queryParameters: d != null ? {'d': d} : null,
  );
}

Object? _randomJsonValue(Random rng) {
  switch (rng.nextInt(5)) {
    case 0:
      return null;
    case 1:
      return rng.nextInt(1000);
    case 2:
      return _randomString(rng);
    case 3:
      return rng.nextBool();
    default:
      return <String, dynamic>{'key': _randomString(rng)};
  }
}

Object? _randomValue(Random rng) {
  switch (rng.nextInt(4)) {
    case 0:
      return null;
    case 1:
      return rng.nextInt(100);
    case 2:
      return [_randomString(rng)];
    default:
      return _randomString(rng);
  }
}

String _randomString(Random rng) {
  final pool = [
    '',
    'test',
    'password',
    'example.com',
    '\x00',
    '../../etc/passwd',
    'a' * 5000,
  ];
  return pool[rng.nextInt(pool.length)];
}
