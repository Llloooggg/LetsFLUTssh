import 'dart:io' show Platform, Process, ProcessException;
import 'dart:typed_data';

import '../../src/rust/api/secure_key_storage.dart' as rust_storage;
import '../../utils/logger.dart';
import 'linux_keychain_marker.dart';

/// Thin wrapper around the OS keychain for storing the AES-256
/// encryption key.
///
/// Every platform routes through `lfs_os_security::secure_key_storage`
/// over FRB:
///
/// - **Linux** — libsecret over zbus (`secret-service` crate).
/// - **macOS / iOS** — Apple Keychain via `security-framework`.
/// - **Windows** — Credential Manager via `CredRead/Write/Delete` extern.
/// - **Android** — direct JNI to `java.security.KeyStore` provider
///   `"AndroidKeyStore"` (see `lfs_os_security::android::keystore`).
///
/// Linux-specific: libsecret emits a non-recoverable g_warning to
/// stderr the moment it cannot talk to a running/unlocked keyring
/// daemon. The shared [LinuxKeychainMarker] gate suppresses that on
/// cold launches before the user opts into keychain storage; the
/// marker is written on a successful [writeKey] and cleared by
/// [deleteKey].
class SecureKeyStorage {
  static const _keyName = 'letsflutssh_encryption_key';
  static const _biometricKeyName = 'letsflutssh_biometric_encryption_key';
  static const _probeName = 'letsflutssh_keychain_probe';

  /// Production flag flipped by `main.dart` at startup. Widget
  /// tests don't set it, so the Linux subprocess probe inside
  /// [probe] stays off in them.
  static bool _runtimeSubprocessProbesEnabled = false;

  static void enableRuntimeSubprocessProbes() {
    _runtimeSubprocessProbesEnabled = true;
  }

  final LinuxKeychainMarker _marker;

  SecureKeyStorage({LinuxKeychainMarker? marker})
    : _marker = marker ?? LinuxKeychainMarker.defaultInstance;

  Future<bool> _linuxGatePass() async {
    if (!Platform.isLinux) return true;
    return _marker.exists();
  }

  Future<bool> isAvailable() async {
    return (await probe()) == KeyringProbeResult.available;
  }

  /// Classified keyring probe.
  ///
  /// Non-Linux: write/read/delete a sentinel via the Rust path
  /// and report the round-trip outcome. Linux: gdbus ping the
  /// secret-service to distinguish "no daemon" from "probe failed".
  /// The gdbus ping only runs when [enableRuntimeSubprocessProbes]
  /// has been called by main.dart — under flutter_test the flag
  /// stays off so a missing `gdbus` binary cannot pollute test
  /// output with classification noise.
  Future<KeyringProbeResult> probe() async {
    if (!Platform.isLinux) {
      try {
        final markerBytes = Uint8List.fromList([0x70, 0x72, 0x6f, 0x62, 0x65]);
        await rust_storage.secureStorageWrite(
          alias: _probeName,
          value: markerBytes,
        );
        final back = await rust_storage.secureStorageRead(alias: _probeName);
        await rust_storage.secureStorageDelete(alias: _probeName);
        final ok =
            back is rust_storage.DbSecureStorageOutcome_Found &&
            _bytesEqual(back.field0, markerBytes);
        return ok
            ? KeyringProbeResult.available
            : KeyringProbeResult.probeFailed;
      } catch (e) {
        AppLogger.instance.log(
          'Keychain probe failed on ${Platform.operatingSystem}: $e',
          name: 'SecureKeyStorage',
        );
        return KeyringProbeResult.probeFailed;
      }
    }

    if (!_runtimeSubprocessProbesEnabled) {
      return KeyringProbeResult.available;
    }
    try {
      final result = await Process.run('gdbus', const [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.secrets',
        '--object-path',
        '/org/freedesktop/secrets',
        '--method',
        'org.freedesktop.DBus.Peer.Ping',
      ], runInShell: false);
      if (result.exitCode == 0) {
        return KeyringProbeResult.available;
      }
      AppLogger.instance.log(
        'gdbus secret-service ping exit=${result.exitCode} '
        'stderr=${result.stderr}',
        name: 'SecureKeyStorage',
      );
      return KeyringProbeResult.linuxNoSecretService;
    } on ProcessException catch (e) {
      AppLogger.instance.log(
        'gdbus binary missing — classifying as no secret-service: $e',
        name: 'SecureKeyStorage',
        level: LogLevel.warn,
      );
      return KeyringProbeResult.linuxNoSecretService;
    }
  }

  Future<Uint8List?> readKey() async {
    if (!await _linuxGatePass()) return null;
    try {
      final outcome = await rust_storage.secureStorageRead(alias: _keyName);
      return outcome is rust_storage.DbSecureStorageOutcome_Found
          ? Uint8List.fromList(outcome.field0)
          : null;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  Future<bool> writeKey(Uint8List key) async {
    try {
      await rust_storage.secureStorageWrite(alias: _keyName, value: key);
      if (Platform.isLinux) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  Future<bool> writeBiometricKey(Uint8List key) async {
    try {
      await rust_storage.secureStorageWriteBiometric(
        alias: _biometricKeyName,
        value: key,
      );
      if (Platform.isLinux) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write biometric key: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  Future<Uint8List?> readBiometricKey() async {
    if (!await _linuxGatePass()) return null;
    try {
      final outcome = await rust_storage.secureStorageReadBiometric(
        alias: _biometricKeyName,
      );
      return outcome is rust_storage.DbSecureStorageOutcome_Found
          ? Uint8List.fromList(outcome.field0)
          : null;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read biometric key: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  Future<void> deleteBiometricKey() async {
    if (!await _linuxGatePass()) return;
    try {
      await rust_storage.secureStorageDeleteBiometric(alias: _biometricKeyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete biometric key: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  Future<void> deleteKey() async {
    if (!await _linuxGatePass()) return;
    try {
      await rust_storage.secureStorageDelete(alias: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete key: $e',
        name: 'SecureKeyStorage',
      );
    }
    if (Platform.isLinux) await _marker.clear();
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum KeyringProbeResult { available, linuxNoSecretService, probeFailed }
