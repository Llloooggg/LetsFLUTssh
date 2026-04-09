import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/logger.dart';

/// Thin wrapper around OS keychain for storing the AES-256 encryption key.
///
/// Uses [FlutterSecureStorage] (Keychain on iOS/macOS, Credential Manager on
/// Windows, libsecret on Linux, EncryptedSharedPreferences on Android).
///
/// All methods catch platform exceptions and return null/false — the caller
/// must handle graceful fallback to plaintext or master-password mode.
class SecureKeyStorage {
  static const _keyName = 'letsflutssh_encryption_key';
  static const _probeName = 'letsflutssh_keychain_probe';

  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Probe whether OS keychain is available at runtime.
  ///
  /// Performs a full write → read → delete cycle with a disposable key.
  /// Returns false if any step fails (no keyring daemon, sandbox restriction,
  /// missing libsecret on Linux, etc.).
  Future<bool> isAvailable() async {
    try {
      const probe = 'probe';
      await _storage.write(key: _probeName, value: probe);
      final readBack = await _storage.read(key: _probeName);
      await _storage.delete(key: _probeName);
      return readBack == probe;
    } catch (e) {
      AppLogger.instance.log(
        'Keychain not available: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Read the encryption key from OS keychain.
  ///
  /// Returns null if the key does not exist or keychain is unavailable.
  Future<Uint8List?> readKey() async {
    try {
      final value = await _storage.read(key: _keyName);
      if (value == null) return null;
      return base64Decode(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  /// Store the encryption key in OS keychain.
  ///
  /// Returns false if the write fails.
  Future<bool> writeKey(Uint8List key) async {
    try {
      await _storage.write(key: _keyName, value: base64Encode(key));
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Remove the encryption key from OS keychain.
  Future<void> deleteKey() async {
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
  }
}
