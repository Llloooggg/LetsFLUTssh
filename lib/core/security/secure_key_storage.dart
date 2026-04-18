import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Thin wrapper around OS keychain for storing the AES-256 encryption key.
///
/// Uses [FlutterSecureStorage] (Keychain on iOS/macOS, Credential Manager on
/// Windows, libsecret on Linux, EncryptedSharedPreferences on Android).
///
/// All methods catch platform exceptions and return null/false — the caller
/// must handle graceful fallback to plaintext or master-password mode.
///
/// Linux-specific: libsecret emits a non-recoverable g_warning to stderr the
/// moment it cannot talk to a running/unlocked keyring daemon. That makes a
/// cold `read` on a system where the keyring was never touched spam stderr
/// on every launch. We sidestep it with a local marker file (see
/// [_markerPath]): on Linux the storage APIs refuse to talk to libsecret
/// unless the marker says the user has previously opted into keychain
/// storage. The marker is written on a successful [writeKey] and cleared by
/// [deleteKey]. Other platforms keep the original behaviour.
class SecureKeyStorage {
  static const _keyName = 'letsflutssh_encryption_key';
  static const _probeName = 'letsflutssh_keychain_probe';
  static const _markerFile = 'keychain_enabled';

  final FlutterSecureStorage _storage;
  final bool _skipPlatformCheck;

  /// When [storage] is provided (tests), platform pre-checks are skipped.
  SecureKeyStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _skipPlatformCheck = storage != null;

  String? _cachedMarkerPath;

  Future<String> _markerPath() async {
    final cached = _cachedMarkerPath;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, _markerFile);
    _cachedMarkerPath = path;
    return path;
  }

  Future<bool> _markerExists() async {
    try {
      return File(await _markerPath()).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeMarker() async {
    try {
      final file = File(await _markerPath());
      await file.parent.create(recursive: true);
      await file.writeAsString('1');
      // Marker itself holds nothing sensitive (`'1'`) but lives next
      // to `credentials.kdf` and every other secret file in the app
      // support dir. Keeping it at 0600 is a consistency win — the
      // whole directory shouldn't have one file with a weaker mode
      // than the rest.
      await hardenFilePerms(file.path);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write keychain marker: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  Future<void> _clearMarker() async {
    try {
      final file = File(await _markerPath());
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to clear keychain marker: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  /// Gate that prevents libsecret calls on Linux until the user has at least
  /// once successfully written to the keychain. On non-Linux platforms (and
  /// in tests with an injected storage) this always lets the call through.
  Future<bool> _linuxGatePass() async {
    if (_skipPlatformCheck || !Platform.isLinux) return true;
    return _markerExists();
  }

  /// Probe whether OS keychain is available at runtime.
  ///
  /// On Linux, checks for a D-Bus session bus and absence of WSL before
  /// attempting any libsecret calls — this avoids the native `g_warning()`
  /// that libsecret emits when the keyring daemon is missing. When the
  /// marker file from a prior [writeKey] is absent, we also skip the live
  /// probe (which itself would unlock the keyring and emit the warning on
  /// a locked one) and report availability purely from the env check. The
  /// first [writeKey] the user triggers will surface any real failure via
  /// the normal error path.
  ///
  /// On all other platforms, performs a full write → read → delete cycle
  /// with a disposable key. Returns false if any step fails.
  Future<bool> isAvailable() async {
    if (!_hasKeychainSupport()) return false;
    if (Platform.isLinux && !_skipPlatformCheck && !await _markerExists()) {
      return true;
    }

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
  /// On Linux also returns null without touching libsecret when the marker
  /// file is missing — that's the path used at every app startup before the
  /// user opts into keychain storage, and it's what used to trigger the
  /// `libsecret_error: Failed to unlock the keyring` warning.
  Future<Uint8List?> readKey() async {
    if (!_hasKeychainSupport()) return null;
    if (!await _linuxGatePass()) return null;
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
  /// Returns false if the write fails. On a successful write on Linux also
  /// lays down the marker file that unlocks subsequent [readKey] calls.
  Future<bool> writeKey(Uint8List key) async {
    if (!_hasKeychainSupport()) return false;
    try {
      await _storage.write(key: _keyName, value: base64Encode(key));
      if (Platform.isLinux && !_skipPlatformCheck) await _writeMarker();
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
  ///
  /// On Linux: if the marker is absent we never stored a key through this
  /// install, so there is nothing to delete and no libsecret call is made.
  /// When the marker is present we delete the secret and then clear the
  /// marker so the next launch doesn't probe libsecret again.
  Future<void> deleteKey() async {
    if (!_hasKeychainSupport()) return;
    if (!await _linuxGatePass()) return;
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
    if (Platform.isLinux && !_skipPlatformCheck) await _clearMarker();
  }
}
