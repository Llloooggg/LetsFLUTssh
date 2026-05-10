import 'dart:io' show Platform;

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/biometric_key_vault.dart' as rust_bio_vault;
import '../../src/rust/api/secure_key_storage.dart' as rust_storage;
import '../../utils/logger.dart';
import 'active_dbkey.dart';
import 'linux_keychain_marker.dart';

/// Secure storage of the master-password-derived DB key, gated by
/// device biometrics.
///
/// Design: the user's master password remains the root secret. When
/// they opt in to "unlock with biometrics", we save the
/// already-derived 32-byte DB key here under a platform-specific
/// protection layer. On app start we query this vault first; if the
/// platform returns the key we feed it into rusqlite/SQLCipher via
/// `dbInit` and skip the KDF prompt, otherwise we fall back to the
/// master-password dialog.
///
/// **Bytes never touch the Dart heap.** Every store / read path is a
/// SecretRef shim — Dart hands a `secretId` to Rust, the orchestrator
/// pulls the bytes from the process-singleton
/// `lfs_core::secrets::SecretStore` and writes / reads them through
/// the platform vault entirely Rust-internally. Dart only sees a
/// boolean outcome.
///
/// Per-platform protection:
///
/// - **Apple (iOS + macOS)** — `lfs_os_security::secure_key_storage::write_biometric_from_secret`
///   wraps the key in a `SecAccessControl` carrying
///   `kSecAccessControlBiometryCurrentSet` on top of
///   `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. Any change
///   to the biometric enrolment invalidates the stored key and
///   forces a master-password re-entry.
///
/// - **Android** — `lfs_os_security::android::keystore::write_biometric_from_secret`
///   via direct JNI to `java.security.KeyStore` provider
///   `"AndroidKeyStore"`. The wrap key carries
///   `setUserAuthenticationRequired(true)` +
///   `setUserAuthenticationValidityDurationSeconds(60)`, paired
///   with a preceding `BiometricPrompt` invocation by the caller.
///
/// - **Windows** — `lfs_os_security::secure_key_storage::write_biometric_from_secret`
///   via direct `CredWriteW` extern "system" call. Credential
///   Manager doesn't offer a biometric-bound storage class, so the
///   biometric gate is enforced by `BiometricAuth.authenticate`
///   ahead of the read (Hello prompt fires first; on success the
///   stored key is fetched).
///
/// - **Linux** — when a TPM2 is present (`/dev/tpmrm0` reachable +
///   `tpm2-tools` installed), the dispatch routes to
///   [`rust_bio_vault.biometricVaultLinuxStoreFromSecret`]
///   (`lfs_core::security::biometric_key_vault::linux`). The Rust
///   orchestrator pulls the DB key from the SecretStore, computes
///   the fprintd enrolment-hash (`lfs_core::platform::linux::fprintd`),
///   seals through `lfs_core::platform::linux::tpm`, and writes the
///   blob to `biometric_vault.tpm` atomically — all without the bytes
///   crossing the FRB boundary. Without a TPM, Linux falls back to
///   `lfs_os_security::secure_key_storage::write_biometric_from_secret`
///   (Rust `secret-service` crate, libsecret D-Bus) — software-labelled
///   in the UI so the weaker guarantee is visible. The libsecret
///   fallback is gated by [LinuxKeychainMarker] so a torn write
///   never reads back as "stored but garbage".
class BiometricKeyVault {
  static const _keyName = 'letsflutssh_bio_db_key';

  final LinuxKeychainMarker _marker;
  final Future<String> Function() _supportDirPath;

  BiometricKeyVault({
    LinuxKeychainMarker? marker,
    Future<String> Function()? supportDirPath,
  }) : _marker = marker ?? LinuxKeychainMarker.defaultInstance,
       _supportDirPath = supportDirPath ?? _defaultSupportDir;

  static Future<String> _defaultSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// True on Linux when a TPM2 device + `tpm2-tools` are both
  /// reachable. Callers use this to decide whether the backing-level
  /// label should read "hardware" or "software" — the storage layer
  /// itself falls back silently, but the UI must not lie about it.
  Future<bool> linuxTpmReady() async {
    if (!Platform.isLinux) return false;
    return rust_bio_vault.biometricVaultLinuxTpmReady();
  }

  /// True if a biometric-protected DB key is currently stashed.
  ///
  /// Linux first checks the TPM-sealed file via Rust, then the
  /// libsecret-marker-gated fallback. All other platforms route
  /// through the unified Rust dispatch in
  /// `lfs_os_security::secure_key_storage::read_biometric`.
  Future<bool> isStored() async {
    if (Platform.isLinux) {
      try {
        final dir = await _supportDirPath();
        final tpmStored = await rust_bio_vault.biometricVaultLinuxIsStored(
          supportDir: dir,
        );
        if (tpmStored) return true;
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.isStored: Linux Rust probe failed: $e',
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

  /// SecretRef-only store. Pulls the bytes from the active SecretStore
  /// slot Rust-side and never materialises them on the Dart heap.
  /// Convenience wrapper around [storeFromSecret] for the common
  /// "stash whatever the active tier just unlocked" case.
  Future<bool> storeFromActive() => storeFromSecret(kActiveDbKeySecretId);

  /// SecretRef store from any caller-chosen [secretId]. Bytes flow
  /// SecretStore → vault entirely Rust-internally; Dart sees a
  /// boolean. On Linux the TPM seal is also fully Rust-internal —
  /// the Rust orchestrator reads the SecretStore entry, derives the
  /// fprintd hash, seals via `tpm2-tools` subprocess, and writes
  /// the file. The SecretStore entry survives so downstream
  /// consumers (e.g. `db_init_from_secret` for rusqlite/SQLCipher
  /// open) can still read it.
  Future<bool> storeFromSecret(String secretId) async {
    if (Platform.isLinux) {
      try {
        final dir = await _supportDirPath();
        await rust_bio_vault.biometricVaultLinuxStoreFromSecret(
          supportDir: dir,
          secretId: secretId,
        );
        return true;
      } catch (e) {
        // TPM unavailable / fprintd unavailable / seal failure —
        // fall through to the libsecret fallback below. The Rust
        // error string carries the classified reason for the log.
        AppLogger.instance.log(
          'BiometricKeyVault: Linux Rust seal unavailable, '
          'falling back to libsecret: $e',
          name: 'BiometricKeyVault',
        );
      }
    }
    try {
      await rust_storage.secureStorageWriteBiometricFromSecret(
        alias: _keyName,
        secretId: secretId,
      );
      if (Platform.isLinux) await _marker.set();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.storeFromSecret failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  /// Read the stashed DB key into the active SecretStore slot. Returns
  /// true when bytes landed under [kActiveDbKeySecretId], false when
  /// nothing stored / read failed (user cancelled passcode prompt,
  /// device locked, TPM policy mismatch after re-enrolment, etc.).
  /// The bytes never cross the FRB boundary.
  Future<bool> readToActive() async {
    if (Platform.isLinux) {
      try {
        final dir = await _supportDirPath();
        final ok = await rust_bio_vault.biometricVaultLinuxReadToSecret(
          supportDir: dir,
          secretId: kActiveDbKeySecretId,
        );
        if (ok) return true;
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.readToActive (Linux Rust): $e',
          name: 'BiometricKeyVault',
        );
      }
      if (!await _marker.exists()) return false;
    }
    try {
      return await rust_storage.secureStorageReadBiometricToSecret(
        alias: _keyName,
        secretId: kActiveDbKeySecretId,
      );
    } catch (e) {
      AppLogger.instance.log(
        'BiometricKeyVault.readToActive failed: $e',
        name: 'BiometricKeyVault',
      );
      return false;
    }
  }

  /// Drop the stashed DB key — called when the user disables
  /// biometric unlock or changes the master password.
  Future<void> clear() async {
    if (Platform.isLinux) {
      try {
        final dir = await _supportDirPath();
        await rust_bio_vault.biometricVaultLinuxClear(supportDir: dir);
      } catch (e) {
        AppLogger.instance.log(
          'BiometricKeyVault.clear (Linux Rust): $e',
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
}
