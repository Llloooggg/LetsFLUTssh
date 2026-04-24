import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Cross-class gate that stops libsecret probes from firing on Linux
/// installs where the keyring daemon is not reachable.
///
/// Background: `flutter_secure_storage` on Linux uses libsecret, which
/// emits a non-recoverable `g_warning` to stderr the moment it cannot
/// talk to a running / unlocked keyring daemon. That makes a cold
/// `containsKey` / `read` on a system where the keyring was never
/// touched (WSL, containers, minimal desktops without
/// `gnome-keyring-daemon` / `kwalletd`) spam stderr on every launch.
///
/// Every class that reads the OS keychain behind
/// `flutter_secure_storage` (`SecureKeyStorage` for L1 DB key,
/// `BiometricKeyVault` for the biometric-gated fallback) refuses to
/// talk to libsecret until this marker file says the user has already
/// completed a successful keychain write — i.e. the keyring was
/// reachable at least once, so subsequent calls are safe to attempt.
///
/// The marker itself holds nothing sensitive (`'1'`), but sits next
/// to `credentials.*` in the app-support dir at 0600 so the whole
/// directory keeps a single perm contract.
///
/// Instance-based so tests can inject a temp-dir [pathFactory] without
/// binding `path_provider` channels. Production callers use
/// [LinuxKeychainMarker.defaultInstance].
class LinuxKeychainMarker {
  static const _fileName = 'keychain_enabled';

  /// Shared production instance — wraps the real
  /// `getApplicationSupportDirectory()` path. Used by
  /// [SecureKeyStorage] and the default [BiometricKeyVault]
  /// construction path. Tests build their own instance against a
  /// temp dir.
  static final LinuxKeychainMarker defaultInstance = LinuxKeychainMarker();

  final Future<String> Function() _pathFactory;

  LinuxKeychainMarker({Future<String> Function()? pathFactory})
    : _pathFactory = pathFactory ?? _defaultPath;

  static Future<String> _defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _fileName);
  }

  /// True when the marker file is on disk, meaning at least one
  /// prior session wrote a secret into the keychain successfully.
  /// Callers use this as the gate before any `containsKey` / `read`
  /// on Linux to avoid triggering libsecret warnings in absence of
  /// the keyring daemon.
  ///
  /// Non-Linux platforms always return `true` — the keyring APIs do
  /// not emit stderr warnings on other OSs, so no gating is needed.
  Future<bool> exists({bool skipOnNonLinux = true}) async {
    if (skipOnNonLinux && !Platform.isLinux) return true;
    try {
      return File(await _pathFactory()).exists();
    } catch (_) {
      return false;
    }
  }

  /// Lay down the marker after a successful keychain write. Safe to
  /// call from multiple keychain-using classes — the file is a flag,
  /// not a counter.
  Future<void> set() async {
    try {
      final file = File(await _pathFactory());
      await file.parent.create(recursive: true);
      await file.writeAsString('1');
      await hardenFilePerms(file.path);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to write keychain marker: $e',
        name: 'LinuxKeychainMarker',
      );
    }
  }

  /// Drop the marker when the last keychain entry across all users is
  /// removed. Called from `SecureKeyStorage.deleteKey` — see the full
  /// lifecycle contract there. Other classes do NOT clear on their
  /// own delete because a different class may still have an entry on
  /// disk.
  Future<void> clear() async {
    try {
      final file = File(await _pathFactory());
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to clear keychain marker: $e',
        name: 'LinuxKeychainMarker',
      );
    }
  }
}
