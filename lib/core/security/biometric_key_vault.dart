import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/secure_key_storage.dart' as rust_storage;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'linux/fprintd_client.dart';
import 'linux/tpm_client.dart';
import 'linux_keychain_marker.dart';

/// Secure storage of the master-password-derived DB key, gated by
/// device biometrics.
///
/// Design: the user's master password remains the root secret. When
/// they opt in to "unlock with biometrics", we save the
/// already-derived 32-byte DB key here under a platform-specific
/// protection layer. On app start we query this vault first; if the
/// platform returns the key we hand it straight to drift and skip
/// the KDF prompt, otherwise we fall back to the master-password
/// dialog.
///
/// Per-platform protection:
///
/// - **Apple (iOS + macOS)** — `lfs_os_security::secure_key_storage::write_biometric`
///   wraps the key in a `SecAccessControl` carrying
///   `kSecAccessControlBiometryCurrentSet` on top of
///   `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. Any change
///   to the biometric enrolment invalidates the stored key and
///   forces a master-password re-entry. Pure FRB call — no
///   `flutter_secure_storage` plugin in the chain.
///
/// - **Android** — `lfs_os_security::android::keystore::write_biometric`
///   via direct JNI to `java.security.KeyStore` provider
///   `"AndroidKeyStore"`. The wrap key carries
///   `setUserAuthenticationRequired(true)` +
///   `setUserAuthenticationValidityDurationSeconds(60)`, paired
///   with a preceding `BiometricPrompt` invocation by the caller.
///
/// - **Windows** — `lfs_os_security::secure_key_storage::write_biometric`
///   via direct `CredWriteW` extern "system" call. Credential
///   Manager doesn't offer a biometric-bound storage class, so the
///   biometric gate is enforced by `BiometricAuth.authenticate`
///   ahead of the read (Hello prompt fires first; on success the
///   stored key is fetched). Same protection model the historical
///   `flutter_secure_storage` Windows path used.
///
/// - **Linux** — when a TPM2 is present (`/dev/tpmrm0` reachable +
///   `tpm2-tools` installed), the DB key is sealed under a fresh
///   primary with the auth value set to the SHA-256 of the current
///   fprintd enrolled-finger list. The sealed blob lands in a file
///   under `getApplicationSupportDirectory()`. The TPM holds the
///   key (not RAM-readable libsecret), and any biometric-enrolment
///   change flips the auth hash → unseal fails → user back on
///   master password. Without a TPM, Linux falls back to
///   `lfs_os_security::secure_key_storage::write_biometric` (Rust
///   `secret-service` crate, libsecret D-Bus) — software-labelled
///   in the UI so the weaker guarantee is visible. The libsecret
///   fallback is gated by [LinuxKeychainMarker] so a torn write
///   never reads back as "stored but garbage".
class BiometricKeyVault {
  static const _keyName = 'letsflutssh_bio_db_key';
  static const _linuxSealFilename = 'biometric_vault.tpm';

  final TpmClient _tpm;
  final FprintdClient _fprintd;
  final Future<File> Function() _linuxSealFileFactory;
  final LinuxKeychainMarker _marker;

  BiometricKeyVault({
    TpmClient? tpmClient,
    FprintdClient? fprintdClient,
    Future<File> Function()? linuxSealFileFactory,
    LinuxKeychainMarker? marker,
  }) : _tpm = tpmClient ?? TpmClient(),
       _fprintd = fprintdClient ?? FprintdClient(),
       _linuxSealFileFactory = linuxSealFileFactory ?? _defaultLinuxSealFile,
       _marker = marker ?? LinuxKeychainMarker.defaultInstance;

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
  ///
  /// Linux first checks the TPM-sealed file, then the
  /// libsecret-marker-gated fallback. All other platforms route
  /// through the unified Rust dispatch in
  /// `lfs_os_security::secure_key_storage::read_biometric`.
  Future<bool> isStored() async {
    if (Platform.isLinux) {
      try {
        final file = await _linuxSealFileFactory();
        if (await file.exists()) return true;
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.isStored: Linux seal-file probe failed: $e',
          name: 'BiometricKeyVault',
        );
      }
      if (!await _marker.exists()) return false;
    }
    try {
      final outcome = await rust_storage.secureStorageReadBiometric(
        alias: _keyName,
      );
      return outcome is rust_storage.DbSecureStorageOutcome_Found;
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
      // TPM unavailable on this Linux box — fall through to
      // libsecret-via-Rust path; mark so subsequent isStored()
      // probes return true even before the keyring unlocks.
    }
    try {
      await rust_storage.secureStorageWriteBiometric(
        alias: _keyName,
        value: key,
      );
      if (Platform.isLinux) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.store failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  /// Read the stashed DB key. Returns null if nothing stored or
  /// read fails (user cancelled passcode prompt, device locked,
  /// TPM policy mismatch after re-enrolment, etc.).
  Future<Uint8List?> read() async {
    if (Platform.isLinux) {
      final unsealed = await _linuxUnseal();
      if (unsealed != null) return unsealed;
      if (!await _marker.exists()) return null;
    }
    try {
      final outcome = await rust_storage.secureStorageReadBiometric(
        alias: _keyName,
      );
      if (outcome is rust_storage.DbSecureStorageOutcome_Found) {
        return Uint8List.fromList(outcome.field0);
      }
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.read failed: $e',
        name: 'BiometricKeyVault',
      );
      return null;
    }
  }

  /// Drop the stashed DB key — called when the user disables
  /// biometric unlock or changes the master password.
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
      await rust_storage.secureStorageDeleteBiometric(alias: _keyName);
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.clear failed: $e',
        name: 'BiometricKeyVault',
      );
    }
    if (Platform.isLinux) {
      try {
        await _marker.clear();
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.clear (linux marker) failed: $e',
          name: 'BiometricKeyVault',
        );
      }
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
      // Atomic rename: a crash mid-flush otherwise truncates the
      // sealed blob, `isStored()` still returns true on next
      // launch, unseal reads garbage, and the app silently drops
      // biometric unlock — on L3+biometric the user has to type the
      // PIN every launch with no "vault broken" hint.
      // `writeBytesAtomic` applies 0600 perms on the tmp file
      // before the rename, matching the old `hardenFilePerms` call.
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
