import 'dart:io' show Platform;
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
/// marker is written on a successful [writeKeyFromSecret] and
/// cleared by [deleteKey].
class SecureKeyStorage {
  // Slot names come from `lfs_frb::api::secure_key_storage::
  // ALIAS_*` so a rename on the Rust side (which also owns
  // `wipe_keychain::MANAGED_KEYS`) is the single source of truth.
  // Dart hits the sync FRB getter once per accessor call —
  // microsecond cost against compile-time-constant Rust statics.
  static String get _keyName => rust_storage.secureStorageAliasEncryptionKey();
  static String get _biometricKeyName =>
      rust_storage.secureStorageAliasBiometricEncryptionKey();
  static String get _probeName =>
      rust_storage.secureStorageAliasKeychainProbe();

  final LinuxKeychainMarker _marker;

  /// Whether [probe] should hit the Linux secret-service reachability
  /// check (zbus connect against `org.freedesktop.secrets`). Production
  /// (`main.dart`) constructs the storage with the default `true`;
  /// widget tests that don't want a live D-Bus probe pass `false` and
  /// read back `KeyringProbeResult.available` without touching the
  /// session bus.
  final bool _probeSecretServiceReachability;

  SecureKeyStorage({
    LinuxKeychainMarker? marker,
    bool probeSecretServiceReachability = true,
  }) : _marker = marker ?? LinuxKeychainMarker.defaultInstance,
       _probeSecretServiceReachability = probeSecretServiceReachability;

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
  /// and report the round-trip outcome. Linux: zbus connect to the
  /// session secret-service to distinguish "no daemon" from "probe
  /// failed". The reachability check only runs when the storage is
  /// constructed with `probeSecretServiceReachability: true` (the
  /// default); widget tests that pass `false` bypass it so a
  /// missing session bus cannot pollute test output with
  /// classification noise.
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

    if (!_probeSecretServiceReachability) {
      return KeyringProbeResult.available;
    }
    try {
      // Routes through `lfs_os_security::secure_key_storage::
      // secret_service_reachable` — `zbus`-driven `SecretService::
      // connect` against `org.freedesktop.secrets`. Same signal
      // libsecret itself runs before every API call; running it
      // up front lets the wizard classify "no daemon" without
      // spamming stderr on failure. No subprocess spawn — the
      // probe lives in the same Rust runtime as every other
      // platform-data path.
      final reachable = await rust_storage
          .secureStorageSecretServiceReachable();
      if (reachable) return KeyringProbeResult.available;
      AppLogger.instance.log(
        'secret-service unreachable (zbus connect failed); '
        'classifying as linuxNoSecretService',
        name: 'SecureKeyStorage',
      );
      return KeyringProbeResult.linuxNoSecretService;
    } catch (e) {
      AppLogger.instance.log(
        'secret-service probe threw: $e',
        name: 'SecureKeyStorage',
        level: LogLevel.warn,
      );
      return KeyringProbeResult.linuxNoSecretService;
    }
  }

  /// SecretRef-only read. Reads the OS keychain entry and stages
  /// it directly under [secretId] in the Rust-side `SecretStore` —
  /// bytes never cross the FRB boundary. Returns true on success,
  /// false when the alias was absent or the read returned empty.
  Future<bool> readKeyToSecret(String secretId) async {
    if (!await _linuxGatePass()) return false;
    try {
      return await rust_storage.secureStorageReadToSecret(
        alias: _keyName,
        secretId: secretId,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read key (secret) from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// SecretRef-only write — pulls the key bytes from the Rust-side
  /// `SecretStore` under [secretId] instead of marshalling them as
  /// `Uint8List` over the FRB boundary. Used by the first-launch +
  /// tier-apply flows that stage the key via
  /// `cryptoAesGcmRandomKeyToSecret` so the bytes never touch the
  /// Dart heap on the way to the OS keychain.
  Future<bool> writeKeyFromSecret(String secretId) async {
    try {
      await rust_storage.secureStorageWriteFromSecret(
        alias: _keyName,
        secretId: secretId,
      );
      if (Platform.isLinux) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write key (secret) to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  Future<void> deleteBiometricKey() async {
    // Delete must always run — even on Linux without the marker.
    // The marker only gates *read* paths so a fresh install does
    // not poke libsecret's session bus before the user opts in;
    // the delete path may run on a wipe / tier-switch flow that
    // followed an earlier write under the marker, and skipping
    // it would leave a stale entry behind. The Rust delete is
    // idempotent on a missing alias.
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
    // Same reasoning as `deleteBiometricKey` — the wipe flow must
    // be able to clear leftover entries regardless of marker state.
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
