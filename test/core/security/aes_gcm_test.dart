import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/aes_gcm.dart';

void main() {
  group('AesGcm', () {
    late Uint8List key;

    setUp(() {
      key = AesGcm.generateKey();
    });

    test('generateKey returns 32 bytes', () {
      expect(key.length, AesGcm.keyLength);
    });

    test('generateKey returns different keys each time', () {
      final key2 = AesGcm.generateKey();
      expect(key, isNot(equals(key2)));
    });

    test('encrypt/decrypt roundtrip', () {
      const plaintext = 'Hello, World!';
      final encrypted = AesGcm.encrypt(plaintext, key);
      final decrypted = AesGcm.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('roundtrip with empty string', () {
      const plaintext = '';
      final encrypted = AesGcm.encrypt(plaintext, key);
      final decrypted = AesGcm.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('roundtrip with unicode', () {
      const plaintext = 'Привет 🌍 日本語';
      final encrypted = AesGcm.encrypt(plaintext, key);
      final decrypted = AesGcm.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('roundtrip with large payload', () {
      final plaintext = 'A' * 100000;
      final encrypted = AesGcm.encrypt(plaintext, key);
      final decrypted = AesGcm.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('roundtrip with JSON', () {
      const plaintext =
          '{"password":"secret","key_data":"-----BEGIN OPENSSH PRIVATE KEY-----"}';
      final encrypted = AesGcm.encrypt(plaintext, key);
      final decrypted = AesGcm.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('encrypted output starts with 12-byte IV', () {
      final encrypted = AesGcm.encrypt('test', key);
      expect(encrypted.length, greaterThan(AesGcm.ivLength));
    });

    test('encrypt produces different output each time (random IV)', () {
      const plaintext = 'same input';
      final enc1 = AesGcm.encrypt(plaintext, key);
      final enc2 = AesGcm.encrypt(plaintext, key);
      expect(enc1, isNot(equals(enc2)));
    });

    test('decrypt with wrong key throws', () {
      final encrypted = AesGcm.encrypt('secret', key);
      final wrongKey = AesGcm.generateKey();
      expect(() => AesGcm.decrypt(encrypted, wrongKey), throwsA(anything));
    });

    test('decrypt with too-short data throws AesGcmException', () {
      final shortData = Uint8List(5);
      expect(
        () => AesGcm.decrypt(shortData, key),
        throwsA(isA<AesGcmException>()),
      );
    });

    test('decrypt with exactly minEncryptedLength - 1 throws', () {
      final shortData = Uint8List(AesGcm.minEncryptedLength - 1);
      expect(
        () => AesGcm.decrypt(shortData, key),
        throwsA(isA<AesGcmException>()),
      );
    });

    test('decrypt with tampered ciphertext throws', () {
      final encrypted = AesGcm.encrypt('secret', key);
      // Flip a bit in the ciphertext (after IV)
      encrypted[AesGcm.ivLength + 1] ^= 0xFF;
      expect(() => AesGcm.decrypt(encrypted, key), throwsA(anything));
    });

    test('decrypt with tampered IV throws', () {
      final encrypted = AesGcm.encrypt('secret', key);
      encrypted[0] ^= 0xFF;
      expect(() => AesGcm.decrypt(encrypted, key), throwsA(anything));
    });

    test('AesGcmException.toString embeds the message', () {
      // Pin the toString contract — used by error-surface formatters
      // and log lines; changing the prefix would break grep tools
      // and user-visible copy in one go.
      const e = AesGcmException('bad bytes');
      expect(e.toString(), 'AesGcmException: bad bytes');
    });
  });
}
