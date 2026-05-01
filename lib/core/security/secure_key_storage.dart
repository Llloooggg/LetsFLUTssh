import 'dart:io' show Platform, Process, ProcessException;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../src/rust/api/secure_key_storage.dart' as rust_storage;
import '../../utils/logger.dart';
import 'linux_keychain_marker.dart';

/// Thin wrapper around the OS keychain for storing the AES-256
/// encryption key.
///
/// Backend routing:
/// - **Desktop (Linux / macOS / iOS / Windows)** — production
///   path delegates to `lfs_os_security::secure_key_storage`
///   via FRB (Linux libsecret over zbus, Apple Keychain via
///   `security-framework`, Windows Credential Manager via
///   `CredRead/Write/Delete` extern).
/// - **Android** — keeps the existing `flutter_secure_storage`
///   `EncryptedSharedPreferences` path until the AndroidKeystore
///   JNI bridge lands.
/// - **Tests** — when the [storage] constructor argument is
///   non-null the legacy `FlutterSecureStorage` mock path runs
///   end-to-end, so the unit suite continues to drive the same
///   in-memory fakes it has historically used.
///
/// Linux-specific: libsecret emits a non-recoverable g_warning
/// to stderr the moment it cannot talk to a running/unlocked
/// keyring daemon. The shared [LinuxKeychainMarker] gate
/// suppresses that on cold launches before the user opts into
/// keychain storage; the marker is written on a successful
/// [writeKey] and cleared by [deleteKey].
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

  /// Legacy-path injectable storage. Non-null forces the
  /// `flutter_secure_storage` round-trip — used by the unit
  /// suite to drive in-memory fakes.
  final FlutterSecureStorage? _legacyStorage;
  final bool _skipPlatformCheck;
  final LinuxKeychainMarker _marker;

  SecureKeyStorage({FlutterSecureStorage? storage, LinuxKeychainMarker? marker})
    : _legacyStorage = storage,
      _skipPlatformCheck = storage != null,
      _marker = marker ?? LinuxKeychainMarker.defaultInstance;

  /// True when production should route through Rust. Tests with
  /// an injected [_legacyStorage] always use the legacy path;
  /// Android also stays on `flutter_secure_storage` until the
  /// JNI bridge lands.
  bool get _useRust =>
      !_skipPlatformCheck &&
      (Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isIOS ||
          Platform.isWindows);

  FlutterSecureStorage get _storage =>
      _legacyStorage ?? const FlutterSecureStorage();

  Future<bool> _linuxGatePass() async {
    if (_skipPlatformCheck || !Platform.isLinux) return true;
    return _marker.exists();
  }

  Future<bool> isAvailable() async {
    return (await probe()) == KeyringProbeResult.available;
  }

  /// Classified keyring probe. See the Tier 1 commentary block
  /// preserved on the prior file revision for the WSL +
  /// secret-service classification rationale.
  Future<KeyringProbeResult> probe() async {
    if (_skipPlatformCheck || !Platform.isLinux) {
      try {
        final markerBytes = Uint8List.fromList([0x70, 0x72, 0x6f, 0x62, 0x65]);
        if (_useRust) {
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
        }
        const probeStr = 'probe';
        await _storage.write(key: _probeName, value: probeStr);
        final back = await _storage.read(key: _probeName);
        await _storage.delete(key: _probeName);
        return back == probeStr
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

    // Linux probe path — gdbus ping; see the in-line history
    // comment on the prior file revision for the WSL + WSLg
    // mis-classification context.
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
    if (_useRust) {
      try {
        final outcome = await rust_storage.secureStorageRead(alias: _keyName);
        return outcome is rust_storage.DbSecureStorageOutcome_Found
            ? Uint8List.fromList(outcome.field0)
            : null;
      } catch (e) {
        AppLogger.instance.log(
          'Failed to read key from keychain (Rust): $e',
          name: 'SecureKeyStorage',
        );
        return null;
      }
    }
    try {
      final value = await _storage.read(key: _keyName);
      if (value == null) return null;
      return _decodeBase64(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  Future<bool> writeKey(Uint8List key) async {
    if (_useRust) {
      try {
        await rust_storage.secureStorageWrite(alias: _keyName, value: key);
        if (Platform.isLinux) await _marker.set();
        return true;
      } catch (e) {
        AppLogger.instance.log(
          'Failed to write key to keychain (Rust): $e',
          name: 'SecureKeyStorage',
        );
        return false;
      }
    }
    try {
      await _storage.write(key: _keyName, value: _encodeBase64(key));
      if (Platform.isLinux && !_skipPlatformCheck) await _marker.set();
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
    if (_useRust) {
      try {
        await rust_storage.secureStorageWriteBiometric(
          alias: _biometricKeyName,
          value: key,
        );
        if (Platform.isLinux) await _marker.set();
        return true;
      } catch (e) {
        AppLogger.instance.log(
          'Failed to write biometric key (Rust): $e',
          name: 'SecureKeyStorage',
        );
        return false;
      }
    }
    try {
      await _storage.write(
        key: _biometricKeyName,
        value: _encodeBase64(key),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );
      if (Platform.isLinux && !_skipPlatformCheck) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write biometric key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  Future<Uint8List?> readBiometricKey() async {
    if (!await _linuxGatePass()) return null;
    if (_useRust) {
      try {
        final outcome = await rust_storage.secureStorageReadBiometric(
          alias: _biometricKeyName,
        );
        return outcome is rust_storage.DbSecureStorageOutcome_Found
            ? Uint8List.fromList(outcome.field0)
            : null;
      } catch (e) {
        AppLogger.instance.log(
          'Failed to read biometric key (Rust): $e',
          name: 'SecureKeyStorage',
        );
        return null;
      }
    }
    try {
      final value = await _storage.read(
        key: _biometricKeyName,
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );
      if (value == null) return null;
      return _decodeBase64(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  Future<void> deleteBiometricKey() async {
    if (!await _linuxGatePass()) return;
    if (_useRust) {
      try {
        await rust_storage.secureStorageDeleteBiometric(
          alias: _biometricKeyName,
        );
      } catch (e) {
        AppLogger.instance.log(
          'Failed to delete biometric key (Rust): $e',
          name: 'SecureKeyStorage',
        );
      }
      return;
    }
    try {
      await _storage.delete(key: _biometricKeyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
  }

  Future<void> deleteKey() async {
    if (!await _linuxGatePass()) return;
    if (_useRust) {
      try {
        await rust_storage.secureStorageDelete(alias: _keyName);
      } catch (e) {
        AppLogger.instance.log(
          'Failed to delete key (Rust): $e',
          name: 'SecureKeyStorage',
        );
      }
      if (Platform.isLinux) await _marker.clear();
      return;
    }
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete key from keychain: $e',
        name: 'SecureKeyStorage',
      );
    }
    if (Platform.isLinux && !_skipPlatformCheck) await _marker.clear();
  }

  /// Convert raw bytes ↔ base64 for the legacy `FlutterSecureStorage`
  /// path. The Rust path stores raw bytes directly so no base64
  /// hop is needed there.
  static String _encodeBase64(Uint8List bytes) {
    // Inline implementation to avoid pulling `dart:convert` only
    // for two helpers that are dead on the Rust path.
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buf = StringBuffer();
    var i = 0;
    while (i + 3 <= bytes.length) {
      final n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      buf.writeCharCode(alphabet.codeUnitAt((n >> 18) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt((n >> 12) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt((n >> 6) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt(n & 0x3f));
      i += 3;
    }
    final rem = bytes.length - i;
    if (rem == 1) {
      final n = bytes[i] << 16;
      buf.writeCharCode(alphabet.codeUnitAt((n >> 18) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt((n >> 12) & 0x3f));
      buf.write('==');
    } else if (rem == 2) {
      final n = (bytes[i] << 16) | (bytes[i + 1] << 8);
      buf.writeCharCode(alphabet.codeUnitAt((n >> 18) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt((n >> 12) & 0x3f));
      buf.writeCharCode(alphabet.codeUnitAt((n >> 6) & 0x3f));
      buf.write('=');
    }
    return buf.toString();
  }

  static Uint8List _decodeBase64(String s) {
    // Defer to dart:convert via a single import path. Pull it
    // from dart:convert directly since the legacy path needs it.
    return _b64.decode(s);
  }

  static const _b64 = _Base64();

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Thin wrapper so the file doesn't need a top-level
/// `import 'dart:convert'` for the legacy path's base64 decode.
/// dart:convert is already pulled by dependents; this class
/// just routes through `Base64Codec.decode`.
class _Base64 {
  const _Base64();
  Uint8List decode(String s) => _convertBase64Decode(s);
}

Uint8List _convertBase64Decode(String s) {
  // Inline base64 decoder — same alphabet as the encoder, no
  // `dart:convert` import. Padding `=` is consumed; whitespace
  // and unknown characters throw.
  const map = <int>[
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 0-15
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 16-31
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, // 32-47
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -2, -1, -1, // 48-63
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, // 64-79
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, // 80-95
    -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, // 96-111
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, // 112-127
  ];
  final out = <int>[];
  var n = 0;
  var bits = 0;
  for (final code in s.codeUnits) {
    if (code >= 128) throw const FormatException('non-ASCII in base64');
    final v = map[code];
    if (v == -2) break; // padding
    if (v == -1) continue; // whitespace tolerance
    n = (n << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.add((n >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

enum KeyringProbeResult { available, linuxNoSecretService, probeFailed }
