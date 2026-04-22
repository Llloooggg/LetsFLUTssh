import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';

void main() {
  group('Tag', () {
    test('constructor generates id and timestamp', () {
      final tag = Tag(name: 'Production');
      expect(tag.id, isNotEmpty);
      expect(tag.name, 'Production');
      expect(tag.color, isNull);
      expect(tag.createdAt, isNotNull);
    });

    test('constructor uses provided id', () {
      final tag = Tag(id: 'custom', name: 'Test');
      expect(tag.id, 'custom');
    });

    test('colorValue parses hex color', () {
      final tag = Tag(name: 'Red', color: '#EF5350');
      expect(tag.colorValue, isA<Color>());
      expect((tag.colorValue!.r * 255).round(), 0xEF);
    });

    test('colorValue returns null for null color', () {
      final tag = Tag(name: 'NoColor');
      expect(tag.colorValue, isNull);
    });

    test('colorValue returns null for empty color', () {
      final tag = Tag(name: 'Empty', color: '');
      expect(tag.colorValue, isNull);
    });

    test('colorValue returns null for invalid hex', () {
      final tag = Tag(name: 'Bad', color: 'not-a-color');
      expect(tag.colorValue, isNull);
    });

    test('copyWith updates fields', () {
      final original = Tag(name: 'Old', color: '#FF0000');
      final updated = original.copyWith(name: 'New', color: '#00FF00');
      expect(updated.id, original.id);
      expect(updated.name, 'New');
      expect(updated.color, '#00FF00');
      expect(updated.createdAt, original.createdAt);
    });

    test('copyWith preserves unchanged fields', () {
      final original = Tag(name: 'Test', color: '#FF0000');
      final updated = original.copyWith(name: 'New');
      expect(updated.color, '#FF0000');
    });

    test('equality by id', () {
      final a = Tag(id: '1', name: 'A');
      final b = Tag(id: '1', name: 'B');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when ids differ', () {
      final a = Tag(id: '1', name: 'A');
      final b = Tag(id: '2', name: 'A');
      expect(a, isNot(equals(b)));
    });

    test('two tags get different ids', () {
      final a = Tag(name: 'A');
      final b = Tag(name: 'B');
      expect(a.id, isNot(b.id));
    });

    test('copyWith without name keeps the original name', () {
      // Pins `name: name ?? this.name` — regression gate for a
      // refactor that reversed the fallback direction.
      final original = Tag(id: 'id', name: 'Original', color: '#EF5350');
      final updated = original.copyWith(color: '#42A5F5');
      expect(updated.name, 'Original');
      expect(updated.color, '#42A5F5');
    });

    test('toString surfaces id + name for log + dev-tools triage', () {
      final tag = Tag(id: 'tag-1', name: 'Prod');
      final repr = tag.toString();
      expect(repr, contains('tag-1'));
      expect(repr, contains('Prod'));
    });

    test('colorValue tolerates a hex string without the leading "#"', () {
      // The parser strips a single leading `#` before calling
      // `int.parse`. Legacy configs migrated from a hand-edited
      // file may carry the bare hex — the fallback must still
      // produce a valid color rather than `null`.
      final tag = Tag(name: 'BareHex', color: 'EF5350');
      expect(tag.colorValue, isA<Color>());
    });
  });

  group('tagColors', () {
    test('predefined colors are valid hex', () {
      for (final c in tagColors) {
        expect(c, startsWith('#'));
        expect(c.length, 7);
        final hex = c.replaceFirst('#', '');
        expect(() => int.parse('FF$hex', radix: 16), returnsNormally);
      }
    });
  });
}
