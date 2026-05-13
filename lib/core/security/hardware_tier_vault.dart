import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/hardware_tier_vault.dart' as rust_vault;
import '../../utils/logger.dart';

/// Hardware-bound DB-key vault for T2 (Hardware + PIN) tier.
///
/// The DB key is sealed inside a hardware module under an auth value
/// derived from the user's PIN. The platform's hardware-enforced
/// rate limit on the auth value is what makes a short PIN
/// cryptographically meaningful — brute force against a 4-6 digit
/// PIN is infeasible when the hardware locks out after N wrong
/// attempts.
///
/// Platform dispatch — every supported platform now lives behind FRB
/// inside the Rust workspace; there is no remaining native-plugin
/// path:
/// - **Linux** — `lfs_core::security::hardware_tier_vault::linux`.
///   The orchestrator runs `tpm2-tools` as a Rust subprocess and
///   writes `hardware_vault.bin` (salt + sealed blob co-located)
///   atomically — no shell-out from Dart.
/// - **iOS / macOS** — `lfs_os_security::hardware_tier_vault::apple`.
///   Direct `security-framework` + `objc2` calls; SE-bound wrap
///   (`ECIESEncryptionCofactorVariableIVX963SHA256AESGCM`) +
///   on-disk envelope.
/// - **Android** — `lfs_os_security::android::hardware_vault`.
///   Direct JNI to `java.security.KeyStore` provider
///   `"AndroidKeyStore"` with `setIsStrongBoxBacked(true)` (API 28+,
///   silent fallback to TEE on `StrongBoxUnavailableException`).
/// - **Windows** — `lfs_os_security::windows::hardware_vault`. CNG
///   `NCrypt` on the Microsoft Platform Crypto Provider (TPM 2.0)
///   with RSA-OAEP-SHA-256 wrap; persistent key
///   `letsflutssh_hardware_vault_v1` lives in the user-scoped key
///   container with `NCRYPT_UI_PROTECT_KEY_FLAG`.
///
/// The PIN itself cannot be the auth value on Apple / Android /
/// Windows because those APIs do not accept arbitrary secrets —
/// they gate on biometrics / Hello. The PIN is therefore an
/// **external HMAC gate**: the user-typed PIN crosses FRB once into
/// the combined `hardwareTierVaultStoreWithPin` /
/// `hardwareTierVaultReadWithPin` / `…StoreFromSecretWithPin` call,
/// Rust HMACs it under the per-install salt, and the native side
/// refuses to unseal unless the gate matches the value saved on
/// `store`. Wrong PIN fails locally without waking the biometric
/// prompt. On Apple / Android / Windows the salt lives in
/// `hardware_vault_salt.bin` next to the wrapped key; on Linux it's
/// co-located inside `hardware_vault.bin` since the entire envelope
/// is one file.
class HardwareTierVault {
  HardwareTierVault();

  /// True when the current platform can host the Hardware tier
  /// *today*. The Rust FRB shim covers every supported OS — Apple
  /// SE / Android Keystore / Windows CNG via `lfs_os_security`,
  /// Linux TPM2 via `lfs_core::platform::linux::tpm` (CLI shell-out
  /// is a Rust subprocess).
  Future<bool> isAvailable() async {
    return await rust_vault.hardwareTierVaultIsAvailable();
  }

  /// Classified hardware-unavailable reason. Returns an opaque
  /// platform-specific string code (`windowsSoftwareOnly`,
  /// `macosNoSecureEnclave`, `androidBiometricNotEnrolled`, …) or
  /// `available` when the tier is reachable. `unknown` on platforms
  /// that do not implement the native `probeDetail` method yet, or
  /// when the channel call fails. The Dart-side provider maps this
  /// to the `HardwareProbeDetail` enum and the localised hint copy.
  ///
  /// Linux is handled by the provider-layer FRB call into
  /// `lfs_core::platform::linux::tpm::probe` and never enters this
  /// method.
  Future<String> probeDetail() async {
    return await rust_vault.hardwareTierVaultProbeDetail();
  }

  /// True when a sealed blob is on disk. Linux inspects
  /// `hardware_vault.bin`; other platforms ask the native side plus
  /// verify that the Dart-side salt file is present (both halves
  /// required — a half-wiped state is a reset, not an unlock).
  Future<bool> isStored() async {
    try {
      if (Platform.isLinux) {
        // Linux orchestrator co-locates salt + sealed inside
        // `hardware_vault.bin` — single-file presence is the
        // whole contract.
        final dir = await getApplicationSupportDirectory();
        return await rust_vault.hardwareTierVaultIsStored(supportDir: dir.path);
      }
      // Apple / Android / Windows keep the wrapped key inside the
      // platform vault; the salt rides next to it on disk under
      // `hardware_vault_salt.bin`. Both halves required —
      // half-wiped state is a reset, not an unlock.
      final dir = await getApplicationSupportDirectory();
      final salt = await rust_vault.hardwareTierVaultReadSalt(
        supportDir: dir.path,
      );
      if (salt == null) return false;
      return await rust_vault.hardwareTierVaultIsStored(supportDir: dir.path);
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.isStored failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Seal [dbKey] under `HMAC(pin, salt)`. Generates a fresh salt,
  /// writes `{salt, sealedBlob}` to disk, returns true on success.
  ///
  /// When [pin] is null or empty the auth value is a fixed empty
  /// byte string — the "passwordless T2" path from the bank-style
  /// modifier model. An attacker still needs TPM / Secure Enclave
  /// access to unseal (cold-disk-theft is still mitigated); there
  /// is simply no user-typed gate on top. The [read] path mirrors
  /// this: passing null there unseals without prompting.
  Future<bool> store({required Uint8List dbKey, String? pin}) async {
    try {
      if (!await isAvailable()) return false;
      try {
        final dir = await getApplicationSupportDirectory();
        // Salt provision, HMAC, and platform-vault store all run
        // inside the same Rust task — the PIN crosses FRB once
        // into `hardwareTierVaultStoreWithPin` and the derived
        // auth value never leaves Rust. Salt-then-vault ordering
        // still applies: a crash between the salt write and the
        // vault store leaves the next launch with a sibling salt
        // and no wrapped key, which `is_stored` surfaces as
        // "not configured" and the next attempt re-provisions
        // cleanly.
        await rust_vault.hardwareTierVaultStoreWithPin(
          supportDir: dir.path,
          dbKey: dbKey,
          pin: pin ?? '',
        );
        return true;
      } catch (e) {
        AppLogger.instance.log(
          'HardwareTierVault.store (Rust): $e',
          name: 'HardwareTierVault',
        );
        return false;
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.store failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// SecretRef variant — pulls the DB key from the Rust-side
  /// `SecretStore` under [secretId] instead of materialising it as
  /// `Uint8List` Dart-side. Routes through
  /// `hardware_tier_vault_store_from_secret_with_pin` so neither the
  /// DB-key bytes nor the derived auth value cross the FRB boundary.
  Future<bool> storeFromSecret({required String secretId, String? pin}) async {
    try {
      if (!await isAvailable()) return false;
      try {
        final dir = await getApplicationSupportDirectory();
        // Salt-then-vault ordering: same rationale as `store`.
        // Failing the salt provision before touching the vault
        // means the live state stays whatever it was before this
        // call started; the user's prior entry (if any) is intact
        // and the next attempt re-derives a fresh salt cleanly.
        // On Linux the salt rides inside `hardware_vault.bin`,
        // so the provision call returns the bytes without writing
        // a sibling file. The PIN crosses FRB once into the
        // combined call and the HMAC happens Rust-side.
        await rust_vault.hardwareTierVaultStoreFromSecretWithPin(
          supportDir: dir.path,
          secretId: secretId,
          pin: pin ?? '',
        );
        return true;
      } catch (e) {
        AppLogger.instance.log(
          'HardwareTierVault.storeFromSecret (Rust): $e',
          name: 'HardwareTierVault',
        );
        return false;
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.storeFromSecret failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Unseal the DB key using [pin]. Returns null on wrong PIN,
  /// missing state, or any other failure — the rate limiter layered
  /// on top is responsible for backoff.
  ///
  /// When [pin] is null or empty the derivation mirrors [store]'s
  /// passwordless branch (empty auth value), so a vault sealed
  /// without a PIN unseals without a PIN.
  Future<Uint8List?> read(String? pin) async {
    try {
      if (!await isAvailable()) return null;
      try {
        final dir = await getApplicationSupportDirectory();
        // Combined read: salt resolution (Linux co-located inside
        // `hardware_vault.bin`, others sibling
        // `hardware_vault_salt.bin`), HMAC under that salt, and
        // platform-vault unwrap all run inside the same Rust
        // task. The PIN crosses FRB once into
        // `hardwareTierVaultReadWithPin` and the derived auth
        // value never leaves Rust.
        return await rust_vault.hardwareTierVaultReadWithPin(
          supportDir: dir.path,
          pin: pin ?? '',
        );
      } catch (e) {
        AppLogger.instance.log(
          'HardwareTierVault.read (Rust): $e',
          name: 'HardwareTierVault',
        );
        return null;
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.read failed: $e',
        name: 'HardwareTierVault',
      );
      return null;
    }
  }

  /// True when a platform-bound biometric overlay (sealed master
  /// password) is on disk for the Hardware tier. The overlay is a
  /// shortcut that releases the typed password from an
  /// OS-biometric-gated slot; absent overlay means the user has to
  /// type the password every time.
  ///
  /// Apple (Secure Enclave + `kSecAccessControlBiometryCurrentSet`),
  /// Android (Hardware Keystore + biometric-bound wrap key alias
  /// `lfs.hardware_tier_vault.l3.bio`), Windows (NCrypt persistent
  /// key `letsflutssh_hardware_vault_bio_v1` gated by
  /// `NCRYPT_UI_PROTECT_KEY_FLAG`), and Linux (TPM2-sealed
  /// `hardware_vault_password_overlay_linux.bin` keyed by the
  /// fprintd enrolment hash) all support the overlay. The Linux
  /// arm needs `fprintd` running with at least one enrolled finger;
  /// a missing daemon surfaces as the `vaultPlatformUnsupported`
  /// FRB envelope on store / read, and `isBiometricPasswordStored`
  /// reports the file's presence regardless so wipe can still clean
  /// it up.
  Future<bool> isBiometricPasswordStored() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return await rust_vault.hardwareTierVaultIsBiometricPasswordStored(
        supportDir: dir.path,
      );
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.isBiometricPasswordStored failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Drop the sealed blob. Called on tier switch away from T2 and
  /// on PIN change (before a new [store]).
  Future<void> clear() async {
    try {
      try {
        final dir = await getApplicationSupportDirectory();
        await rust_vault.hardwareTierVaultClear(supportDir: dir.path);
      } catch (e) {
        // Best-effort — the salt file is authoritative for "is
        // stored" on Apple / Android / Windows, so failing the
        // Rust-side clear still degrades safely into "locked out".
        // Log so a support trace points at a stale native-side
        // blob the next tier-switch has to tolerate. Linux
        // co-locates both halves so the Rust clear *is* the whole
        // clear; failure there leaves a stuck file the next
        // attempt overwrites.
        AppLogger.instance.log(
          'HardwareTierVault.clear (Rust) failed (salt delete continues): $e',
          name: 'HardwareTierVault',
        );
      }
      // Apple / Android / Windows keep the salt in a sibling
      // file; drop it Rust-side now. Linux co-locates the salt
      // inside the envelope and is already cleared above.
      if (!Platform.isLinux) {
        final dir = await getApplicationSupportDirectory();
        await rust_vault.hardwareTierVaultDeleteSalt(supportDir: dir.path);
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.clear failed: $e',
        name: 'HardwareTierVault',
      );
    }
  }

  /// Resolve the TPM / hw-vault auth value for a (password, biometric)
  /// modifier combo — shared across platforms, not just Linux/TPM2.
  /// Matches the "universal bank-style" model documented in the
  /// 3-tier plan:
  ///
  /// * password=false, biometric=false → empty `Uint8List(0)`
  ///   (isolation-only; wrong callers still need TPM / Secure Enclave
  ///   access, but there is no user-typed gate).
  /// * password=true, biometric=false → `HMAC(typedPassword, salt)`.
  /// * biometric=true → `HMAC(fprintdHash, salt)`. The `password`
  ///   flag must also be true by wizard invariant (biometric is a
  ///   shortcut for entering the password, never its replacement),
  ///   but the resolver itself treats biometric as the authoritative
  ///   auth source when both are requested.
  ///
  /// Returns null for an inconsistent request (password=true without
  /// a typed password bound, biometric=true without an fprintd hash).
  /// Callers surface null as "modifier resolution failed — treat as a
  /// cancelled unlock" so we never silently fall back to an empty auth.
  ///
  /// Routes through `lfs_core::security::hardware_tier_vault::
  /// resolve_auth_value` (FRB sync) so the (password, biometric) →
  /// auth-bytes contract lives one place across the Linux TPM
  /// path + the per-platform Rust vault paths.
  @visibleForTesting
  static Uint8List? resolveAuthValue({
    required bool password,
    required bool biometric,
    required Uint8List salt,
    String? typedPassword,
    Uint8List? fprintdHash,
  }) {
    final v = rust_vault.hardwareTierVaultResolveAuthValue(
      password: password,
      biometric: biometric,
      salt: salt,
      typedPassword: typedPassword,
      fprintdHash: fprintdHash,
    );
    return v == null ? null : Uint8List.fromList(v);
  }
}
