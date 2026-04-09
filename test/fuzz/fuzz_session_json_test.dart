import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';

/// Fuzz tests for [Session.fromJson].
///
/// Generates random and malformed JSON maps to verify the parser
/// never crashes with an unhandled exception on untrusted input.
void main() {
  group('Fuzz Session.fromJson', () {
    final rng = Random(42); // deterministic seed for reproducibility

    test('handles 1000 random JSON payloads without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = _randomSessionJson(rng);
        try {
          Session.fromJson(json);
        } on TypeError {
          // Expected for type mismatches (e.g. int where String expected)
        } on FormatException {
          // Expected for malformed dates, etc.
        }
      }
    });

    test('handles empty map', () {
      try {
        Session.fromJson({});
      } on TypeError {
        // 'id' and 'host'/'user' are required non-nullable Strings
      }
    });

    test('handles map with all null values', () {
      final json = {
        'id': null,
        'label': null,
        'folder': null,
        'host': null,
        'port': null,
        'user': null,
        'auth_type': null,
        'password': null,
        'key_path': null,
        'key_data': null,
        'passphrase': null,
        'created_at': null,
        'updated_at': null,
        'incomplete': null,
      };
      try {
        Session.fromJson(json);
      } on TypeError {
        // Expected — id, host, user are non-nullable
      }
    });

    test('handles map with wrong types', () {
      for (var i = 0; i < 500; i++) {
        final json = _wrongTypeSessionJson(rng);
        try {
          Session.fromJson(json);
        } on TypeError {
          // Expected
        } on FormatException {
          // Expected
        }
      }
    });

    test('handles map with extreme numeric values', () {
      final extremes = [
        0,
        -1,
        -2147483648,
        2147483647,
        9007199254740991,
        -9007199254740991,
      ];
      for (final port in extremes) {
        try {
          Session.fromJson({
            'id': 'test-id',
            'host': 'h',
            'user': 'u',
            'port': port,
          });
        } on TypeError {
          // Expected
        }
      }
    });

    test('handles map with very long strings', () {
      final longStr = 'A' * 100000;
      try {
        Session.fromJson({
          'id': longStr,
          'host': longStr,
          'user': longStr,
          'label': longStr,
          'password': longStr,
        });
      } on TypeError {
        // Expected
      }
    });

    test('handles map with special characters in strings', () {
      final specials = [
        '\x00',
        '\n\r\t',
        '../../etc/passwd',
        '<script>alert(1)</script>',
        "'; DROP TABLE sessions; --",
        '\u{FFFD}',
        '\u{0000}',
        '🔑' * 1000,
      ];
      for (final s in specials) {
        try {
          Session.fromJson({
            'id': s,
            'host': s,
            'user': s,
            'auth_type': s,
            'created_at': s,
          });
        } on TypeError {
          // Expected
        }
      }
    });

    test('handles map with extra unknown keys', () {
      final session = Session.fromJson({
        'id': 'test',
        'host': 'example.com',
        'user': 'root',
        '__proto__': 'polluted',
        'constructor': {'prototype': 'attack'},
        'toString': 'overridden',
      });
      expect(session.id, 'test');
    });
  });
}

/// Generate a random JSON map that may or may not be valid for Session.fromJson.
Map<String, dynamic> _randomSessionJson(Random rng) {
  return {
    if (rng.nextBool()) 'id': _randomValue(rng),
    if (rng.nextBool()) 'label': _randomValue(rng),
    if (rng.nextBool()) 'folder': _randomValue(rng),
    if (rng.nextBool()) 'host': _randomValue(rng),
    if (rng.nextBool()) 'port': _randomValue(rng),
    if (rng.nextBool()) 'user': _randomValue(rng),
    if (rng.nextBool()) 'auth_type': _randomValue(rng),
    if (rng.nextBool()) 'password': _randomValue(rng),
    if (rng.nextBool()) 'key_path': _randomValue(rng),
    if (rng.nextBool()) 'key_data': _randomValue(rng),
    if (rng.nextBool()) 'passphrase': _randomValue(rng),
    if (rng.nextBool()) 'created_at': _randomValue(rng),
    if (rng.nextBool()) 'updated_at': _randomValue(rng),
    if (rng.nextBool()) 'incomplete': _randomValue(rng),
    if (rng.nextBool()) 'group': _randomValue(rng),
  };
}

/// Generate a map where every key has a wrong type.
Map<String, dynamic> _wrongTypeSessionJson(Random rng) {
  return {
    'id': rng.nextBool() ? rng.nextInt(9999) : rng.nextBool(),
    'host': rng.nextBool() ? rng.nextInt(9999) : <String>[],
    'port': rng.nextBool() ? 'not_a_number' : rng.nextDouble(),
    'user': rng.nextBool() ? rng.nextInt(9999) : null,
    'auth_type': rng.nextBool() ? rng.nextInt(5) : <String, dynamic>{},
    'incomplete': rng.nextBool() ? 'true' : 0,
    'created_at': rng.nextBool() ? rng.nextInt(9999) : true,
  };
}

/// Generate a random value of a random type.
Object? _randomValue(Random rng) {
  switch (rng.nextInt(8)) {
    case 0:
      return null;
    case 1:
      return _randomString(rng);
    case 2:
      return rng.nextInt(100000) - 50000;
    case 3:
      return rng.nextDouble() * 200 - 100;
    case 4:
      return rng.nextBool();
    case 5:
      return <String>[];
    case 6:
      return <String, dynamic>{};
    default:
      return _randomString(rng);
  }
}

String _randomString(Random rng) {
  final pool = [
    '',
    'password',
    'key',
    'keyWithPassword',
    'example.com',
    'root',
    '2024-01-01T00:00:00Z',
    'not-a-date',
    '\x00\x01\x02',
    '../../../etc/passwd',
    '192.168.1.1',
    'a' * 10000,
  ];
  return pool[rng.nextInt(pool.length)];
}
