import 'dart:convert';
import 'dart:io' show File, Platform, Process, ProcessException;
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
  static const _biometricKeyName = 'letsflutssh_biometric_encryption_key';
  static const _probeName = 'letsflutssh_keychain_probe';
  static const _markerFile = 'keychain_enabled';

  /// Production flag flipped by [main.dart] at app startup. Widget
  /// tests running under `FakeAsync` do not set this, so the Linux-
  /// only `Process.run('gdbus', …)` path inside [probe] stays off in
  /// them — any real subprocess spawn leaks a Timer onto FakeAsync's
  /// pending-timer list and makes unrelated widget tests fail. In
  /// production the flag is true from the first frame and the
  /// classified probe runs normally.
  static bool _runtimeSubprocessProbesEnabled = false;

  /// Called from production entry points (`main.dart`) to unlock the
  /// subprocess-backed secret-service ping used by [probe] on Linux.
  /// Widget tests intentionally do not call it.
  static void enableRuntimeSubprocessProbes() {
    _runtimeSubprocessProbesEnabled = true;
  }

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
  /// Delegates to the classified [probe] so `isAvailable` and
  /// `probe` never disagree — earlier revisions split the two paths
  /// (fast env check vs gdbus ping), which left
  /// `probeCapabilities` on Linux seeing the optimistic
  /// env-variable answer (`DBUS_SESSION_BUS_ADDRESS` set → "ok")
  /// while the Settings reason line saw the concrete gdbus answer
  /// ("no secret-service"). On WSL + WSLg the split caused the
  /// first-launch flow to auto-select T1, silently hit a libsecret
  /// write failure, and fall through to plaintext without the user
  /// ever seeing the reduced-wizard T0-vs-Paranoid prompt.
  ///
  /// Widget tests that run without `enableRuntimeSubprocessProbes`
  /// skip the gdbus path inside [probe] and receive an optimistic
  /// `KeyringProbeResult.available`, which maps back to `true`
  /// here — same behaviour as the earlier fast-path, same harness
  /// compatibility.
  Future<bool> isAvailable() async {
    return (await probe()) == KeyringProbeResult.available;
  }

  /// Classified keyring probe — concrete backend ping, no env-var
  /// heuristics.
  ///
  /// Design: *actually talk to the service.* Every signal short of a
  /// real round-trip was lying on some platform. Pattern-matching
  /// `WSL_DISTRO_NAME` mis-classified WSL installs with libsecret
  /// configured; checking `DBUS_SESSION_BUS_ADDRESS` mis-classified
  /// WSL2 + WSLg (session bus up, no keyring daemon). The only
  /// signal that matches "can libsecret read/write a secret right
  /// now" is either libsecret itself round-tripping a value, or a
  /// D-Bus ping to the secret-service daemon — the same step
  /// libsecret runs internally before any API call.
  ///
  ///   * Non-Linux platforms (Windows / macOS / iOS / Android) —
  ///     live write/read/delete against `flutter_secure_storage`.
  ///     The backing service is always up on a user device; any
  ///     failure is a real platform-channel error, classified as
  ///     `probeFailed`.
  ///   * Linux — `gdbus call --session --dest
  ///     org.freedesktop.secrets --object-path
  ///     /org/freedesktop/secrets --method
  ///     org.freedesktop.DBus.Peer.Ping`. Exit 0 = the service is
  ///     registered on the session bus and responds. Any non-zero
  ///     exit (D-Bus down, no daemon, service unregistered) =
  ///     `linuxNoSecretService`. `gdbus` binary missing is treated
  ///     the same way — GLib not installed almost certainly means
  ///     the desktop keyring stack is not there either, and the
  ///     user is better served by the "install gnome-keyring / KWallet"
  ///     hint than by a mysterious "probe could not run" fallback.
  ///
  /// Linux probe is guarded by [_runtimeSubprocessProbesEnabled]:
  /// widget tests running under FakeAsync do not set the flag, so
  /// they skip the subprocess entirely (any `Process.run` inside
  /// FakeAsync-managed code ends up leaking a Timer onto the
  /// pending-timer list and fails unrelated widget tests). Tests
  /// that skip the gdbus path fall through to an optimistic
  /// `available` — correct for the fixture data they operate on.
  /// In production the flag is set from `main.dart` before the
  /// first provider evaluates.
  Future<KeyringProbeResult> probe() async {
    if (_skipPlatformCheck || !Platform.isLinux) {
      try {
        const marker = 'probe';
        await _storage.write(key: _probeName, value: marker);
        final back = await _storage.read(key: _probeName);
        await _storage.delete(key: _probeName);
        return back == marker
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

    // ── Linux ────────────────────────────────────────────────────
    if (!_runtimeSubprocessProbesEnabled) {
      // Test path — subprocess probes disabled; optimistic fallback.
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

  /// Pre-flight gate — unconditional pass-through now that the
  /// classified [probe] does a concrete `gdbus` ping against the
  /// secret-service daemon instead of pattern-matching environment
  /// variables. Kept as a single entry point so the read / write /
  /// delete paths below all share one gate call and the classification
  /// behaviour can be extended later without re-threading every call
  /// site. On non-Linux this was always a no-op; on Linux the earlier
  /// `DBUS_SESSION_BUS_ADDRESS` check was a proxy (D-Bus present ≠
  /// keyring working — WSL2 + WSLg ships the bus but not
  /// `gnome-keyring-daemon`), so removing it matches the concrete
  /// probe model already used for TPM / Secure Enclave / StrongBox.
  bool _hasKeychainSupport() => true;

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

  /// Variant of [writeKey] that stores the key under a biometric-
  /// gated access-control policy.
  ///
  /// On Apple (iOS / macOS) the entry is written with
  /// `AccessControlFlag.biometryCurrentSet` so any biometric
  /// enrolment change (adding / removing a finger, re-enrolling Face
  /// ID) invalidates the stored key and forces re-entry of the typed
  /// password. On Android `flutter_secure_storage`'s
  /// `AndroidOptions(encryptedSharedPreferences: true)` does the
  /// best available job inside the package's current API surface;
  /// the stronger native-backed biometric-gated Keystore flow routes
  /// through the hardware-vault plugin (`storeBiometricPassword` /
  /// `readBiometricPassword`) rather than this path. On Linux and
  /// Windows `flutter_secure_storage` does not expose a biometric
  /// ACL option in this package — the write falls through to a
  /// plain entry and the caller is responsible for gating access
  /// via the platform's own biometric prompt before calling
  /// [readBiometricKey].
  ///
  /// Paired with [readBiometricKey]; the two share the alias so a
  /// biometric-written key cannot be read back via [readKey] and
  /// vice versa.
  Future<bool> writeBiometricKey(Uint8List key) async {
    if (!_hasKeychainSupport()) return false;
    try {
      await _storage.write(
        key: _biometricKeyName,
        value: base64Encode(key),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
        mOptions: const MacOsOptions(
          accessibility: KeychainAccessibility.passcode,
          accessControlFlags: [AccessControlFlag.biometryCurrentSet],
        ),
      );
      if (Platform.isLinux && !_skipPlatformCheck) await _writeMarker();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write biometric key to keychain: $e',
        name: 'SecureKeyStorage',
      );
      return false;
    }
  }

  /// Pair of [writeBiometricKey]. Returns null when:
  ///   * no biometric entry exists;
  ///   * the user failed / cancelled the biometric prompt;
  ///   * enrolment changed since the write (Apple
  ///     `biometryCurrentSet` invalidation).
  Future<Uint8List?> readBiometricKey() async {
    if (!_hasKeychainSupport()) return null;
    if (!await _linuxGatePass()) return null;
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
      return base64Decode(value);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
      return null;
    }
  }

  /// Drop the biometric-gated key. Always called in lockstep with
  /// [deleteKey] — the two never exist together on the same install.
  Future<void> deleteBiometricKey() async {
    if (!_hasKeychainSupport()) return;
    if (!await _linuxGatePass()) return;
    try {
      await _storage.delete(key: _biometricKeyName);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to delete biometric key from keychain: $e',
        name: 'SecureKeyStorage',
      );
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

/// Classified keyring probe outcome. Settings UI consumes this to
/// render an actionable line under a disabled Keychain tier card
/// instead of a generic "unavailable" note.
enum KeyringProbeResult {
  /// Keychain reachable — Linux: gdbus ping to `org.freedesktop.secrets`
  /// returned 0; non-Linux: live write/read/delete round-trip
  /// succeeded.
  available,

  /// Linux `gdbus` ping failed — any of: no session bus reachable,
  /// no `gnome-keyring-daemon` / `kwalletd` running, or `gdbus`
  /// binary missing. The earlier `linuxNoDbusSession` case was
  /// merged in here; distinguishing the two required another env-var
  /// proxy (present session bus address vs absent) and the user
  /// action for both is the same — install / start a secret-service
  /// daemon. One actionable line, no fake specificity.
  linuxNoSecretService,

  /// Non-Linux host's keychain returned an error — rare, usually a
  /// locked macOS login keychain or a corrupted Windows Credential
  /// Manager. UI shows the generic fallback copy.
  probeFailed,
}
