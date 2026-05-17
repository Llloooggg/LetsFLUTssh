import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/widgets/tag_color.dart';

Tag _tag({String? color}) =>
    Tag(name: 'demo', color: color, createdAt: DateTime(2024, 1, 1));

void main() {
  group('TagColorX.colorValue', () {
    test('null color returns null', () {
      expect(_tag().colorValue, isNull);
    });

    test('empty color string returns null', () {
      expect(_tag(color: '').colorValue, isNull);
    });

    test('valid #RRGGBB parses with full opacity', () {
      // The implementation prefixes `FF` to force opaque alpha. Pin
      // that contract — without it the colour silently turns
      // transparent on a 6-digit hex.
      expect(_tag(color: '#FF5722').colorValue, const Color(0xFFFF5722));
    });

    test(
      'hex without leading # parses too (defensive against #-stripped writes)',
      () {
        expect(_tag(color: '4CAF50').colorValue, const Color(0xFF4CAF50));
      },
    );

    test('lower-case hex digits parse', () {
      expect(_tag(color: '#abcdef').colorValue, const Color(0xFFABCDEF));
    });

    test('non-hex characters return null instead of throwing', () {
      // Each of these would otherwise throw `FormatException` from
      // `int.parse` — pin that the helper swallows them so a stored
      // garbage colour never crashes a tag list render. Truncated
      // hex (`#12`, `#1234567`) does NOT belong here: it still
      // parses to a valid radix-16 integer — `Color` silently
      // truncates to 32 bits, so the surface failure is "wrong
      // colour but no crash". Pinned in the next test.
      for (final bad in const ['#XYZ', 'not-a-color', 'gg']) {
        expect(
          _tag(color: bad).colorValue,
          isNull,
          reason: 'non-hex input "$bad" must collapse to null',
        );
      }
    });

    test('truncated hex parses (silently wrong colour, never throws)', () {
      // Both are valid radix-16 strings — `int.parse('FF12')`
      // succeeds and `Color` accepts the resulting integer.
      // Documented here so a future "strict 6-digit only"
      // tightening surfaces as a failing test instead of a silent
      // UI shift.
      expect(_tag(color: '#12').colorValue, isNotNull);
      expect(_tag(color: '#1234567').colorValue, isNotNull);
    });
  });
}
