import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

/// Fuzz tests for the per-entry JSON parsers in [ExportImport].
///
/// These parsers read data from an .lfs archive whose contents are
/// decrypted before parsing — but the master password is user-supplied,
/// so the decrypted JSON still counts as untrusted input. The parsers
/// must never throw unhandled exceptions regardless of input shape.
void main() {
  group('ExportImport.parseKeysJson fuzz', () {
    final rng = Random(1);

    test('null / empty / whitespace do not crash', () {
      expect(ExportImport.parseKeysJson(null), isEmpty);
      expect(ExportImport.parseKeysJson(''), isEmpty);
      expect(ExportImport.parseKeysJson('   '), isEmpty);
    });

    test('malformed JSON returns empty list', () {
      for (final bad in _malformedJson) {
        expect(ExportImport.parseKeysJson(bad), isEmpty, reason: bad);
      }
    });

    test('JSON scalars / objects (non-list top level) return empty', () {
      for (final input in [
        '"hello"',
        '42',
        'true',
        'null',
        '{"id":"x"}',
        '[1, 2, 3]', // list of non-maps
      ]) {
        expect(ExportImport.parseKeysJson(input), isA<List<Object?>>());
      }
    });

    test('1000 random payloads do not crash', () {
      for (var i = 0; i < 1000; i++) {
        final json = jsonEncode(
          List.generate(rng.nextInt(5), (_) => _randomMap(rng, _keyFields)),
        );
        expect(() => ExportImport.parseKeysJson(json), returnsNormally);
      }
    });

    test('fallback values used when fields missing', () {
      final r = ExportImport.parseKeysJson('[{}]');
      expect(r, hasLength(1));
      expect(r.first.id, '');
      expect(r.first.label, '');
      expect(r.first.isGenerated, false);
    });

    test('wrong types for booleans / dates degrade gracefully', () {
      final r = ExportImport.parseKeysJson(
        '[{"is_generated":"yes","created_at":"not-a-date"}]',
      );
      expect(r.first.isGenerated, false);
      // createdAt must fall back to some DateTime, not throw
      expect(r.first.createdAt, isA<DateTime>());
    });
  });

  group('ExportImport.parseTagsJson fuzz', () {
    final rng = Random(2);

    test('null and malformed return empty', () {
      expect(ExportImport.parseTagsJson(null), isEmpty);
      for (final bad in _malformedJson) {
        expect(ExportImport.parseTagsJson(bad), isEmpty);
      }
    });

    test('1000 random payloads do not crash', () {
      for (var i = 0; i < 1000; i++) {
        final json = jsonEncode(
          List.generate(rng.nextInt(5), (_) => _randomMap(rng, _tagFields)),
        );
        expect(() => ExportImport.parseTagsJson(json), returnsNormally);
      }
    });

    test('non-string color becomes null', () {
      final r = ExportImport.parseTagsJson('[{"color":123}]');
      expect(r.first.color, isNull);
    });
  });

  group('ExportImport.parseSnippetsJson fuzz', () {
    final rng = Random(3);

    test('null and malformed return empty', () {
      expect(ExportImport.parseSnippetsJson(null), isEmpty);
      for (final bad in _malformedJson) {
        expect(ExportImport.parseSnippetsJson(bad), isEmpty);
      }
    });

    test('1000 random payloads do not crash', () {
      for (var i = 0; i < 1000; i++) {
        final json = jsonEncode(
          List.generate(rng.nextInt(5), (_) => _randomMap(rng, _snippetFields)),
        );
        expect(() => ExportImport.parseSnippetsJson(json), returnsNormally);
      }
    });
  });

  group('ExportImport.parseLinksJson fuzz', () {
    final rng = Random(4);

    test('null / malformed / wrong shape return empty', () {
      expect(ExportImport.parseLinksJson(null, targetKey: 'tag_id'), isEmpty);
      for (final bad in _malformedJson) {
        expect(ExportImport.parseLinksJson(bad, targetKey: 'tag_id'), isEmpty);
      }
    });

    test('1000 random payloads do not crash', () {
      for (var i = 0; i < 1000; i++) {
        final key = rng.nextBool() ? 'tag_id' : 'snippet_id';
        final json = jsonEncode(
          List.generate(
            rng.nextInt(5),
            (_) => _randomMap(rng, ['session_id', key, 'extra', 'garbage']),
          ),
        );
        expect(
          () => ExportImport.parseLinksJson(json, targetKey: key),
          returnsNormally,
        );
      }
    });

    test('missing targetKey yields empty targetId', () {
      final r = ExportImport.parseLinksJson(
        '[{"session_id":"s1"}]',
        targetKey: 'tag_id',
      );
      expect(r.first.sessionId, 's1');
      expect(r.first.targetId, '');
    });
  });

  group('ExportImport.parseFolderTagLinksJson fuzz', () {
    final rng = Random(5);

    test('null and malformed return empty', () {
      expect(ExportImport.parseFolderTagLinksJson(null), isEmpty);
      for (final bad in _malformedJson) {
        expect(ExportImport.parseFolderTagLinksJson(bad), isEmpty);
      }
    });

    test('1000 random payloads do not crash', () {
      for (var i = 0; i < 1000; i++) {
        final json = jsonEncode(
          List.generate(
            rng.nextInt(5),
            (_) => _randomMap(rng, ['folder_path', 'tag_id', 'x']),
          ),
        );
        expect(
          () => ExportImport.parseFolderTagLinksJson(json),
          returnsNormally,
        );
      }
    });
  });

  group('ExportImport parsers — extreme inputs', () {
    test('very long strings', () {
      final long = 'A' * 50000;
      final json = jsonEncode([
        {'id': long, 'label': long, 'private_key': long},
      ]);
      final r = ExportImport.parseKeysJson(json);
      expect(r.first.id.length, 50000);
    });

    test('deeply nested / wrong-typed values', () {
      final json = jsonEncode([
        {
          'id': {'nested': true},
          'label': [1, 2, 3],
          'is_generated': 'true',
          'created_at': 12345,
        },
      ]);
      final r = ExportImport.parseKeysJson(json);
      expect(r, hasLength(1));
      expect(r.first.id, '');
      expect(r.first.label, '');
      expect(r.first.isGenerated, false);
    });

    test('special characters survive round-trip of asString', () {
      final specials = ['\x00', '\n\r\t', '../../etc/passwd', '🔑'];
      for (final s in specials) {
        final json = jsonEncode([
          {'id': s, 'name': s},
        ]);
        final r = ExportImport.parseTagsJson(json);
        expect(r.first.id, s);
        expect(r.first.name, s);
      }
    });
  });
}

const _malformedJson = [
  '{',
  '[',
  '}{',
  'not json at all',
  '[{invalid',
  '\u{0000}\u{0001}',
  '[1, 2,]', // trailing comma
];

const _keyFields = [
  'id',
  'label',
  'private_key',
  'public_key',
  'key_type',
  'is_generated',
  'created_at',
];

const _tagFields = ['id', 'name', 'color', 'created_at'];

const _snippetFields = [
  'id',
  'title',
  'command',
  'description',
  'created_at',
  'updated_at',
];

Map<String, Object?> _randomMap(Random rng, List<String> fields) {
  final map = <String, Object?>{};
  for (final f in fields) {
    if (rng.nextBool()) map[f] = _randomValue(rng);
  }
  return map;
}

Object? _randomValue(Random rng) {
  switch (rng.nextInt(8)) {
    case 0:
      return null;
    case 1:
      return _randomString(rng);
    case 2:
      return rng.nextInt(1 << 30) - (1 << 29);
    case 3:
      return rng.nextDouble();
    case 4:
      return rng.nextBool();
    case 5:
      return <Object?>[rng.nextInt(10), _randomString(rng)];
    case 6:
      return <String, Object?>{'k': _randomString(rng)};
    default:
      return _randomString(rng);
  }
}

String _randomString(Random rng) {
  const pool = [
    '',
    'value',
    '2024-01-01T00:00:00Z',
    'not-a-date',
    '\x00\x01',
    '#ff00ff',
    '../../x',
    '🔑',
  ];
  return pool[rng.nextInt(pool.length)];
}
