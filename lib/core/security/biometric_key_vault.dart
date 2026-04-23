import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'linux/fprintd_client.dart';
import 'linux/tpm_client.dart';

/// Secure storage of the master-password-derived DB key, gated by device
/// biometrics.
///
/// Design: the user's master password remains the root secret. When they
/// opt in to "unlock with biometrics", we save the already-derived 32-byte
/// DB key here under a platform-specific protection layer. On app start
/// we query this vault first; if the platform returns the key we hand it
/// straight to drift and skip the KDF prompt, otherwise we fall back to
/// the master-password dialog.
///
/// Apple platforms (iOS + macOS): the key is wrapped with a `SecAccessControl`
/// that requires [AccessControlFlag.biometryCurrentSet] on top of the
/// `.whenPasscodeSetThisDeviceOnly` tier. This binds the stored DB key to
/// the Secure Enclave and to the *current* biometric enrolment — adding,
/// removing, or changing a fingerprint/Face ID invalidates the stored key
/// and forces a master-password re-entry on the next unlock. Android still
/// rides on the default `flutter_secure_storage` EncryptedSharedPreferences
/// until a dedicated Keystore + `BiometricPrompt.CryptoObject` plugin
/// lands.
///
/// Linux: when a TPM2 is present (`/dev/tpmrm0` + `tpm2-tools` installed),
/// the DB key is sealed under a fresh primary with the auth value set to
/// the SHA-256 of the current fprintd enrolled-finger list. The sealed
/// blob lands in a file under [getApplicationSupportDirectory]. Result:
/// (a) the key is held by the TPM, not in RAM-readable libsecret; and (b)
/// any change to the biometric enrolment flips the auth hash, the unseal
/// fails, and the user is back on master password — same invariant as
/// Apple's `biometryCurrentSet`. Without a TPM, Linux falls back to the
/// same `flutter_secure_storage` (libsecret) path other platforms use —
/// software-labelled in the UI so the weaker guarantee is visible.
class BiometricKeyVault {
  static const _keyName = 'letsflutssh_bio_db_key';
  static const _linuxSealFilename = 'biometric_vault.tpm';

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
  final TpmClient _tpm;
  final FprintdClient _fprintd;
  final Future<File> Function() _linuxSealFileFactory;

  BiometricKeyVault({
    FlutterSecureStorage? storage,
    TpmClient? tpmClient,
    FprintdClient? fprintdClient,
    Future<File> Function()? linuxSealFileFactory,
  }) : _storage = storage ?? _defaultStorage(),
       _tpm = tpmClient ?? TpmClient(),
       _fprintd = fprintdClient ?? FprintdClient(),
       _linuxSealFileFactory = linuxSealFileFactory ?? _defaultLinuxSealFile;

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: iosOptions,
      aOptions: AndroidOptions(),
      mOptions: macOsOptions,
    );
  }

  static Future<File> _defaultLinuxSealFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _linuxSealFilename));
  }

  /// True on Linux when a TPM2 device + `tpm2-tools` are both
  /// reachable. Callers use this to decide whether the backing-level
  /// label should read "hardware" or "software" — the storage layer
  /// itself falls back silently, but the UI must not lie about it.
  Future<bool> linuxTpmReady() async {
    if (!Platform.isLinux) return false;
    return _tpm.isAvailable();
  }

  /// True if a biometric-protected DB key is currently stashed.
  Future<bool> isStored() async {
    if (Platform.isLinux) {
      try {
        final file = await _linuxSealFileFactory();
        if (await file.exists()) return true;
      } catch (_) {}
    }
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
    if (Platform.isLinux) {
      final sealed = await _linuxSeal(key);
      if (sealed) return true;
      // TPM not available / enrolment missing → software fallback.
    }
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
  /// (user cancelled passcode prompt, device locked, TPM policy mismatch
  /// after re-enrolment, etc.).
  Future<Uint8List?> read() async {
    if (Platform.isLinux) {
      final unsealed = await _linuxUnseal();
      if (unsealed != null) return unsealed;
      // Fall through to libsecret in case the vault was written
      // before TPM support was wired, or the TPM became unusable.
    }
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
    if (Platform.isLinux) {
      try {
        final file = await _linuxSealFileFactory();
        if (await file.exists()) await file.delete();
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.clear (linux seal file) failed: $e',
          name: 'BiometricKeyVault',
        );
      }
    }
    try {
      await _storage.delete(key: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.clear failed: $e',
        name: 'BiometricKeyVault',
      );
    }
  }

  Future<bool> _linuxSeal(Uint8List key) async {
    try {
      if (!await _tpm.isAvailable()) return false;
      final authHash = await _fprintd.getEnrolmentHash();
      if (authHash == null) return false;
      final sealed = await _tpm.seal(key, authValue: authHash);
      if (sealed == null) return false;
      final file = await _linuxSealFileFactory();
      // Atomic rename: a crash mid-flush otherwise truncates the sealed
      // blob, `isStored()` still returns true on next launch, unseal
      // reads garbage, and the app silently drops biometric unlock —
      // on L3+biometric the user has to type the PIN every launch with
      // no "vault broken" hint. `writeBytesAtomic` applies 0600 perms
      // on the tmp file before the rename, matching the old
      // `hardenFilePerms` call.
      await writeBytesAtomic(file.path, sealed);
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault Linux seal failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  Future<Uint8List?> _linuxUnseal() async {
    try {
      final file = await _linuxSealFileFactory();
      if (!await file.exists()) return null;
      if (!await _tpm.isAvailable()) return null;
      final authHash = await _fprintd.getEnrolmentHash();
      if (authHash == null) return null;
      final blob = await file.readAsBytes();
      return _tpm.unseal(blob, authValue: authHash);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault Linux unseal failed: $e',
        name: 'BiometricKeyVault',
      );
      return null;
    }
  }
}
