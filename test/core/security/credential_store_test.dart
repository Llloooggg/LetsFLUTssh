import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:letsflutssh/core/security/credential_store.dart';

void main() {
  group('CredentialData', () {
    test('isEmpty when all fields empty', () {
      const cred = CredentialData();
      expect(cred.isEmpty, true);
    });

    test('not isEmpty when password set', () {
      const cred = CredentialData(password: 'secret');
      expect(cred.isEmpty, false);
    });

    test('not isEmpty when keyData set', () {
      const cred = CredentialData(keyData: '-----BEGIN RSA PRIVATE KEY-----');
      expect(cred.isEmpty, false);
    });

    test('JSON roundtrip', () {
      const cred = CredentialData(
        password: 'pass123',
        keyData: 'PEM-DATA',
        passphrase: 'phrase',
      );
      final json = cred.toJson();
      final restored = CredentialData.fromJson(json);
      expect(restored.password, 'pass123');
      expect(restored.keyData, 'PEM-DATA');
      expect(restored.passphrase, 'phrase');
    });

    test('fromJson handles missing fields', () {
      final cred = CredentialData.fromJson(<String, dynamic>{});
      expect(cred.password, '');
      expect(cred.keyData, '');
      expect(cred.passphrase, '');
      expect(cred.isEmpty, true);
    });
  });

  group('AES-256-GCM roundtrip', () {
    // Test the crypto primitives directly (same algorithm as CredentialStore)
    test('encrypt then decrypt returns original', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final iv = Uint8List.fromList(List.generate(12, (i) => i + 100));
      const plaintext = 'Hello, encrypted world! 🔐';

      // Encrypt
      final encCipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final encrypted = encCipher.process(Uint8List.fromList(utf8.encode(plaintext)));

      // Decrypt
      final decCipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final decrypted = decCipher.process(encrypted);

      expect(utf8.decode(decrypted), plaintext);
    });

    test('wrong key fails to decrypt', () {
      final key1 = Uint8List.fromList(List.generate(32, (i) => i));
      final key2 = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final iv = Uint8List.fromList(List.generate(12, (i) => i));
      const plaintext = 'secret data';

      final encCipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key1), 128, iv, Uint8List(0)));
      final encrypted = encCipher.process(Uint8List.fromList(utf8.encode(plaintext)));

      final decCipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key2), 128, iv, Uint8List(0)));

      expect(() => decCipher.process(encrypted), throwsA(anything));
    });
  });

  group('PBKDF2 key derivation', () {
    test('same password and salt produce same key', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      const password = 'test-password';

      final pbkdf2a = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyA = pbkdf2a.process(Uint8List.fromList(utf8.encode(password)));

      final pbkdf2b = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyB = pbkdf2b.process(Uint8List.fromList(utf8.encode(password)));

      expect(keyA, keyB);
    });

    test('different passwords produce different keys', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));

      final pbkdf2a = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyA = pbkdf2a.process(Uint8List.fromList(utf8.encode('password1')));

      final pbkdf2b = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 1000, 32));
      final keyB = pbkdf2b.process(Uint8List.fromList(utf8.encode('password2')));

      expect(keyA, isNot(keyB));
    });
  });
}
