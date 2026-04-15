import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/logger.dart';

/// Secure storage of the master-password-derived DB key, gated by device
/// biometrics via [FlutterSecureStorage] platform options.
///
/// Design: the user's master password remains the root secret. When they
/// opt in to "unlock with biometrics", we save the already-derived 32-byte
/// DB key here under an iOS accessibility / Android security-level that
/// requires the device to be unlocked (passcode, fingerprint, face).
/// On app start we query this vault first; if the platform returns the key
/// we hand it straight to drift and skip the PBKDF2 prompt, otherwise we
/// fall back to the master-password dialog.
///
/// This is weaker than a full BiometricPrompt-wrapped hardware-key but is
/// what `flutter_secure_storage` exposes cross-platform today. A future
/// pass can tighten iOS via `SecAccessControl` and Android via explicit
/// `BiometricPrompt.CryptoObject`.
class BiometricKeyVault {
  static const _keyName = 'letsflutssh_bio_db_key';

  final FlutterSecureStorage _storage;

  BiometricKeyVault({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.passcode,
        synchronizable: false,
      ),
      aOptions: AndroidOptions(),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.passcode,
        synchronizable: false,
      ),
    );
  }

  /// True if a biometric-protected DB key is currently stashed.
  Future<bool> isStored() async {
    try {
      return await _storage.containsKey(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.isStored failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  /// Stash the DB [key] in platform secure storage. Returns false on
  /// failure (unsupported platform, keychain unavailable, etc.).
  Future<bool> store(Uint8List key) async {
    try {
      await _storage.write(key: _keyName, value: base64Encode(key));
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.store failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  /// Read the stashed DB key. Returns null if nothing stored or read fails
  /// (user cancelled passcode prompt, device locked, etc.).
  Future<Uint8List?> read() async {
    try {
      final value = await _storage.read(key: _keyName);
      if (value == null) return null;
      return base64Decode(value);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.read failed: $e',
        name: 'BiometricKeyVault',
      );
      return null;
    }
  }

  /// Drop the stashed DB key — called when the user disables biometric
  /// unlock or changes the master password.
  Future<void> clear() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.clear failed: $e',
        name: 'BiometricKeyVault',
      );
    }
  }
}
