import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-256-GCM encryption utility.
///
/// Wire format: `[IV (12 bytes)] [ciphertext + GCM authentication tag]`.
/// Used by [SessionStore], [KeyStore], [KnownHostsManager], and
/// [MasterPasswordManager].
class AesGcm {
  /// AES-256 key length in bytes.
  static const keyLength = 32;

  /// IV length in bytes (standard for GCM).
  static const ivLength = 12;

  /// Minimum encrypted payload: IV + at least 1 byte of ciphertext.
  static const minEncryptedLength = ivLength + 1;

  /// Encrypt [plaintext] with a 256-bit [key].
  ///
  /// Returns `[IV (12)] [ciphertext + GCM tag]`.
  static Uint8List encrypt(String plaintext, Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(ivLength, (_) => random.nextInt(256)),
    );

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);

    return Uint8List.fromList([...iv, ...output]);
  }

  /// Decrypt [data] with a 256-bit [key].
  ///
  /// Throws [AesGcmException] if the data is too short or decryption fails
  /// (wrong key, corrupted data, or tampered ciphertext).
  static String decrypt(Uint8List data, Uint8List key) {
    if (data.length < minEncryptedLength) {
      throw AesGcmException(
        'Encrypted data too short (${data.length} bytes) — file is corrupted',
      );
    }
    final iv = data.sublist(0, ivLength);
    final ciphertext = data.sublist(ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final output = cipher.process(ciphertext);
    return utf8.decode(output);
  }

  /// Generate a cryptographically secure random key.
  static Uint8List generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(keyLength, (_) => random.nextInt(256)),
    );
  }
}

/// Thrown when AES-GCM encryption or decryption fails.
class AesGcmException implements Exception {
  final String message;
  final Object? cause;

  const AesGcmException(this.message, {this.cause});

  @override
  String toString() => 'AesGcmException: $message';
}
