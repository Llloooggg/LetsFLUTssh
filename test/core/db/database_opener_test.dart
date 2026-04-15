import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database_opener.dart';

void main() {
  group('encryptionKeyToSqlLiteral', () {
    test('formats 32-byte key as lowercase hex blob literal', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final literal = encryptionKeyToSqlLiteral(key);
      expect(literal, startsWith("x'"));
      expect(literal, endsWith("'"));
      expect(literal.length, 2 + 64 + 1);
      expect(
        literal,
        "x'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'",
      );
    });

    test('pads single-digit bytes', () {
      final key = Uint8List.fromList([0x01, 0x0a, 0xff, 0x00]);
      expect(encryptionKeyToSqlLiteral(key), "x'010aff00'");
    });
  });
}
