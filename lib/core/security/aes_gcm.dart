import 'dart:math';
import 'dart:typed_data';

/// Helper for the AES-256 random-key generation step. AES-GCM
/// encrypt / decrypt themselves live in `lfs_core::crypto` —
/// `cryptoAesGcmEncrypt` / `cryptoAesGcmDecrypt` over FRB. Keygen
/// stays Dart-side because it's a single `Random.secure()` fill.
class AesGcm {
  /// AES-256 key length in bytes.
  static const keyLength = 32;

  /// Generate a cryptographically secure random key.
  static Uint8List generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(keyLength, (_) => random.nextInt(256)),
    );
  }
}
