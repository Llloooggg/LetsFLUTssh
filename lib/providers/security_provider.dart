import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/biometric_auth.dart';
import '../core/security/biometric_key_vault.dart';
import '../core/security/hardware_tier_vault.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/secret_buffer.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';

/// Global [SecureKeyStorage] instance for OS keychain access.
final secureKeyStorageProvider = Provider<SecureKeyStorage>(
  (_) => SecureKeyStorage(),
);

/// Biometric authentication probe + prompt. Used by the optional
/// "unlock with biometrics" flow in master-password mode.
final biometricAuthProvider = Provider<BiometricAuth>((_) => BiometricAuth());

/// Biometric-scoped secure storage of the DB key — only populated when
/// the user opts in to biometric unlock; read at startup before the
/// master-password dialog.
final biometricKeyVaultProvider = Provider<BiometricKeyVault>(
  (_) => BiometricKeyVault(),
);

/// L2 keychain-password gate. Split-storage salted HMAC; fronts the
/// keychain-stored DB key with a short-password check dialog.
final keychainPasswordGateProvider = Provider<KeychainPasswordGate>(
  (_) => KeychainPasswordGate(),
);

/// L3 hardware-bound DB key vault (TPM2 on Linux, stubbed elsewhere
/// until per-platform plugins land).
final hardwareTierVaultProvider = Provider<HardwareTierVault>(
  (_) => HardwareTierVault(),
);

/// OS / hardware capabilities snapshot, probed asynchronously and
/// cached for the lifetime of the Riverpod container. TPM / Secure
/// Enclave / libsecret do not appear or disappear mid-session, so a
/// one-shot probe is correct — the Settings upgrade banner consumes
/// this to decide whether to surface the "hardware tier available"
/// row or the "hardware tier unavailable — why" notice.
final securityCapabilitiesProvider = FutureProvider<SecurityCapabilities>((
  ref,
) async {
  return probeCapabilities(
    keyStorage: ref.read(secureKeyStorageProvider),
    hardwareVault: ref.read(hardwareTierVaultProvider),
  );
});

/// Current data protection level, detected at startup.
///
/// Defaults to [SecurityTier.plaintext]. Updated by the security
/// initialization flow in main.dart via [SecurityStateNotifier].
final securityStateProvider =
    NotifierProvider<SecurityStateNotifier, SecurityState>(
      SecurityStateNotifier.new,
    );

/// Immutable snapshot of security state: level + optional encryption key
/// held in a page-locked native buffer.
///
/// [_buffer] owns a [SecretBuffer] with the 32-byte DB key; [encryptionKey]
/// exposes it as a `Uint8List` alias for compatibility with the existing
/// drift/SQLite3MC call sites. The alias stays valid as long as the buffer
/// lives — i.e. until the next `set(...)`/`clearEncryption()` replaces the
/// state, at which point the old buffer is disposed (zeroed + munlock +
/// freed) by [SecurityStateNotifier].
class SecurityState {
  final SecurityTier level;
  final SecretBuffer? _buffer;

  SecurityState({this.level = SecurityTier.plaintext, SecretBuffer? buffer})
    : _buffer = buffer;

  /// Live `Uint8List` view into the locked buffer, or null in plaintext mode.
  Uint8List? get encryptionKey => _buffer?.bytes;

  /// Internal handle — needed by [SecurityStateNotifier] to dispose on
  /// transitions. Not part of the public surface.
  SecretBuffer? get buffer => _buffer;

  /// Whether data stores should encrypt their contents.
  bool get isEncrypted => level != SecurityTier.plaintext;
}

/// Notifier for security state — set once at startup, updated on
/// master password enable/disable/change. Owns the [SecretBuffer] lifecycle:
/// any transition disposes the previous buffer so the plaintext key is
/// zeroed + unlocked + freed before a new one takes its place.
class SecurityStateNotifier extends Notifier<SecurityState> {
  SecretBuffer? _owned;

  @override
  SecurityState build() {
    // Dispose the currently-owned buffer when the provider itself is torn
    // down. Reading `state` inside onDispose isn't allowed (Riverpod
    // forbids ref access from lifecycle callbacks), so we keep a plain
    // field that mirrors the buffer the state holds.
    ref.onDispose(() {
      _owned?.dispose();
      _owned = null;
    });
    return SecurityState();
  }

  /// Set the security level and encryption key. Copies [key] into a fresh
  /// page-locked buffer and disposes the previous one. The caller is
  /// responsible for zeroing its own `Uint8List` copy afterwards.
  void set(SecurityTier level, [Uint8List? key]) {
    final previous = _owned;
    final buffer = key == null ? null : SecretBuffer.fromBytes(key);
    _owned = buffer;
    state = SecurityState(level: level, buffer: buffer);
    previous?.dispose();
  }

  /// Clear encryption (revert to plaintext). Zeroes and releases the
  /// in-memory key.
  void clearEncryption() {
    final previous = _owned;
    _owned = null;
    state = SecurityState();
    previous?.dispose();
  }
}
