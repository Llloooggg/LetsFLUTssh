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
/// Apple platforms (iOS + macOS): the key is wrapped with a `SecAccessControl`
/// that requires [AccessControlFlag.biometryCurrentSet] on top of the
/// `.whenPasscodeSetThisDeviceOnly` tier. This binds the stored DB key to
/// the Secure Enclave and to the *current* biometric enrolment — adding,
/// removing, or changing a fingerprint/Face ID invalidates the stored key
/// and forces a master-password re-entry on the next unlock. Android still
/// rides on the default `flutter_secure_storage` EncryptedSharedPreferences
/// until the dedicated Keystore + `BiometricPrompt.CryptoObject` plugin
/// lands (P1.2-android).
class BiometricKeyVault {
  static const _keyName = 'letsflutssh_bio_db_key';

  /// iOS options: Secure Enclave binding via `SecAccessControl` with
  /// `.biometryCurrentSet`. Exposed as a constant so tests (and ports to
  /// other call sites) can assert the exact access-control policy.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  /// macOS options: mirrors [iosOptions]. Keychain on macOS 12+ honours
  /// the same access-control flags against the Secure Enclave on Apple
  /// silicon and against the T2 chip on Intel Macs that ship with one.
  static const macOsOptions = MacOsOptions(
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  final FlutterSecureStorage _storage;

  BiometricKeyVault({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: iosOptions,
      aOptions: AndroidOptions(),
      mOptions: macOsOptions,
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
