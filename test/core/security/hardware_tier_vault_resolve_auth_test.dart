import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';

void main() {
  final salt = Uint8List.fromList(List.generate(32, (i) => i));

  Uint8List hmac(List<int> message) =>
      Uint8List.fromList(Hmac(sha256, salt).convert(message).bytes);

  group('HardwareTierVault.resolveAuthValue', () {
    test('no password + no biometric → empty auth (isolation only)', () {
      final out = HardwareTierVault.resolveAuthValue(
        password: false,
        biometric: false,
        salt: salt,
      );
      expect(out, isNotNull);
      expect(out, isEmpty);
    });

    test('password only → HMAC(typedPassword, salt)', () {
      const pw = 'hunter2';
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: pw,
      );
      expect(out, isNotNull);
      expect(out, hmac(utf8.encode(pw)));
    });

    test('biometric overrides password-bound auth value when both set', () {
      final fprintd = Uint8List.fromList(
        List.generate(32, (i) => (i * 3) & 0xFF),
      );
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: true,
        salt: salt,
        typedPassword: 'something',
        fprintdHash: fprintd,
      );
      expect(out, isNotNull);
      expect(out, hmac(fprintd));
    });

    test('password=true without typedPassword → null', () {
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
      );
      expect(out, isNull);
    });

    test('biometric=true without fprintdHash → null', () {
      final out = HardwareTierVault.resolveAuthValue(
        password: false,
        biometric: true,
        salt: salt,
      );
      expect(out, isNull);
    });

    test('biometric=true with empty fprintdHash → null', () {
      final out = HardwareTierVault.resolveAuthValue(
        password: false,
        biometric: true,
        salt: salt,
        fprintdHash: Uint8List(0),
      );
      expect(out, isNull);
    });

    test('password=true with empty typedPassword → null', () {
      final out = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: salt,
        typedPassword: '',
      );
      expect(out, isNull);
    });

    test('different salts produce different auth values for same password', () {
      final saltA = Uint8List.fromList(List.generate(32, (i) => i));
      final saltB = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final a = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: saltA,
        typedPassword: 'same',
      );
      final b = HardwareTierVault.resolveAuthValue(
        password: true,
        biometric: false,
        salt: saltB,
        typedPassword: 'same',
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(b));
    });
  });
}
