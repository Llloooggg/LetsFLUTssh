import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/secure_key_storage.dart';
import '../core/security/security_level.dart';

/// Global [SecureKeyStorage] instance for OS keychain access.
final secureKeyStorageProvider = Provider<SecureKeyStorage>(
  (_) => SecureKeyStorage(),
);

/// Current data protection level, detected at startup.
///
/// Defaults to [SecurityLevel.plaintext]. Updated by the security
/// initialization flow in main.dart via [SecurityStateNotifier].
final securityStateProvider =
    NotifierProvider<SecurityStateNotifier, SecurityState>(
      SecurityStateNotifier.new,
    );

/// Immutable snapshot of security state: level + optional encryption key.
class SecurityState {
  final SecurityLevel level;
  final Uint8List? encryptionKey;

  const SecurityState({
    this.level = SecurityLevel.plaintext,
    this.encryptionKey,
  });

  /// Whether data stores should encrypt their contents.
  bool get isEncrypted => level != SecurityLevel.plaintext;
}

/// Notifier for security state — set once at startup, updated on
/// master password enable/disable/change.
class SecurityStateNotifier extends Notifier<SecurityState> {
  @override
  SecurityState build() => const SecurityState();

  /// Set the security level and encryption key.
  void set(SecurityLevel level, [Uint8List? key]) {
    state = SecurityState(level: level, encryptionKey: key);
  }

  /// Clear encryption (revert to plaintext).
  void clearEncryption() {
    state = const SecurityState();
  }
}
