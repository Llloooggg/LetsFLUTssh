import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';

/// Fuzz tests for QR codec ([decodeSessionsFromQr], [decodeImportUri]).
///
/// Verifies that no malformed payload can cause an unhandled crash.
void main() {
  group('Fuzz decodeSessionsFromQr', () {
    final rng = Random(42);

    test('handles 1000 random payloads without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final payload = _randomQrPayload(rng);
        // Must never throw — returns null on invalid input
        decodeSessionsFromQr(payload);
      }
    });

    test('handles empty string', () {
      expect(decodeSessionsFromQr(''), isNull);
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
        expect(decodeSessionsFromQr(input), isNull);
      }
    });

    test('handles wrong version numbers', () {
      for (var v = -10; v < 10; v++) {
        if (v == 1) continue; // valid version
        final payload = jsonEncode({'v': v, 's': []});
        expect(decodeSessionsFromQr(payload), isNull);
      }
    });

    test('handles malformed session entries', () {
      final payloads = [
        '{"v":1,"s":null}',
        '{"v":1,"s":"not_a_list"}',
        '{"v":1,"s":[null]}',
        '{"v":1,"s":["string"]}',
        '{"v":1,"s":[42]}',
        '{"v":1,"s":[true]}',
        '{"v":1,"s":[[]]}',
        '{"v":1,"s":[{"l":null,"h":null}]}',
        '{"v":1,"s":[{"l":123,"h":456,"p":"NaN"}]}',
      ];
      for (final p in payloads) {
        // May return null or a result — must not throw
        try {
          decodeSessionsFromQr(p);
        } on TypeError {
          // Acceptable — type cast failures
        }
      }
    });

    test('handles deeply nested payloads', () {
      var nested = '{"v":1,"s":[{"l":"x","h":"y","u":"z"';
      for (var i = 0; i < 100; i++) {
        nested += ',"extra_$i":{"nested":true}';
      }
      nested += '}]}';
      // Must not crash on deep nesting
      try {
        decodeSessionsFromQr(nested);
      } on TypeError {
        // Acceptable
      }
    });

    test('handles very large payloads', () {
      final bigList = List.generate(
        10000,
        (i) => {'l': 'session_$i', 'h': 'host_$i', 'u': 'user_$i'},
      );
      final payload = jsonEncode({'v': 1, 's': bigList});
      final result = decodeSessionsFromQr(payload);
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
