import 'dart:convert';
import 'dart:io' show Platform;
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
  final bool _skipPlatformCheck;

  /// When [storage] is provided (tests), platform pre-checks are skipped.
  SecureKeyStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _skipPlatformCheck = storage != null;

  /// Probe whether OS keychain is available at runtime.
  ///
  /// On Linux, checks for a D-Bus session bus and absence of WSL before
  /// attempting any libsecret calls — this avoids the native `g_warning()`
  /// that libsecret emits when the keyring daemon is missing.
  ///
  /// On all platforms, performs a full write → read → delete cycle with a
  /// disposable key. Returns false if any step fails.
  Future<bool> isAvailable() async {
    if (!_hasKeychainSupport()) return false;

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

  /// Quick pre-flight check before touching the native keychain API.
  ///
  /// On Linux, libsecret requires a running keyring daemon reachable via
  /// D-Bus. Without it, every call logs a noisy `g_warning` to stderr that
  /// we cannot suppress from Dart. Detect this early and skip.
  bool _hasKeychainSupport() {
    if (_skipPlatformCheck || !Platform.isLinux) return true;

    // WSL has no keyring daemon.
    if (Platform.environment.containsKey('WSL_DISTRO_NAME')) {
      AppLogger.instance.log(
        'WSL detected — skipping keychain probe',
        name: 'SecureKeyStorage',
      );
      return false;
    }

    // No D-Bus session → no keyring.
    final dbus = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
    if (dbus == null || dbus.isEmpty) {
      AppLogger.instance.log(
        'No D-Bus session bus — skipping keychain probe',
        name: 'SecureKeyStorage',
      );
      return false;
    }

    return true;
  }

  /// Read the encryption key from OS keychain.
  ///
  /// Returns null if the key does not exist or keychain is unavailable.
  Future<Uint8List?> readKey() async {
    if (!_hasKeychainSupport()) return null;
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
    if (!_hasKeychainSupport()) return false;
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
    if (!_hasKeychainSupport()) return;
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
