import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/aes_gcm.dart';

void main() {
  group('AesGcm fuzz', () {
    final random = Random(42); // deterministic seed for reproducibility

    Uint8List randomBytes(int length) {
      return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)),
      );
    }

    test(
      'decrypt with random garbage never crashes with unhandled exception',
      () {
        final key = AesGcm.generateKey();
        for (int i = 0; i < 100; i++) {
          final length = random.nextInt(256);
          final data = randomBytes(length);
          try {
            AesGcm.decrypt(data, key);
          } on AesGcmException {
            // Expected — data too short or invalid
          } catch (_) {
            // Any other exception is also acceptable (e.g. pointycastle
            // InvalidCipherTextException for GCM auth tag failure).
            // The key invariant: no unhandled crash / segfault / hang.
          }
        }
      },
    );

    test('decrypt with random key on valid ciphertext never crashes', () {
      final realKey = AesGcm.generateKey();
      final encrypted = AesGcm.encrypt('test data', realKey);
      for (int i = 0; i < 50; i++) {
        final fakeKey = randomBytes(32);
        try {
          AesGcm.decrypt(encrypted, fakeKey);
        } catch (_) {
          // Expected: wrong key → auth tag mismatch
        }
      }
    });

    test('encrypt/decrypt roundtrip with random plaintext', () {
      final key = AesGcm.generateKey();
      for (int i = 0; i < 50; i++) {
        final length = random.nextInt(1000);
        final bytes = randomBytes(length);
        final plaintext = String.fromCharCodes(
          bytes.map((b) => b % 128), // ASCII range
        );
        final encrypted = AesGcm.encrypt(plaintext, key);
        final decrypted = AesGcm.decrypt(encrypted, key);
        expect(decrypted, plaintext, reason: 'Iteration $i, length $length');
      }
    });

    test('decrypt with truncated ciphertext never crashes', () {
      final key = AesGcm.generateKey();
      final encrypted = AesGcm.encrypt('test payload for truncation', key);
      for (int i = 0; i < encrypted.length; i++) {
        final truncated = encrypted.sublist(0, i);
        try {
          AesGcm.decrypt(Uint8List.fromList(truncated), key);
        } catch (_) {
          // Expected
        }
      }
    });

    test('decrypt with appended garbage never crashes', () {
      final key = AesGcm.generateKey();
      final encrypted = AesGcm.encrypt('test', key);
      for (int i = 0; i < 20; i++) {
        final extra = randomBytes(random.nextInt(64) + 1);
        final tampered = Uint8List.fromList([...encrypted, ...extra]);
        try {
          AesGcm.decrypt(tampered, key);
        } catch (_) {
          // Expected
        }
      }
    });

    test('empty data returns AesGcmException', () {
      final key = AesGcm.generateKey();
      expect(
        () => AesGcm.decrypt(Uint8List(0), key),
        throwsA(isA<AesGcmException>()),
      );
    });
  });
}
