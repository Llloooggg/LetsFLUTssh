import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/hardware_tier_vault.dart' as rust_vault;
import '../../utils/file_utils.dart';
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
/// **external HMAC gate**: Dart computes `HMAC(pin, salt)` and hands
/// it to the native side, which refuses to unseal unless the gate
/// matches the value saved on `store`. Wrong PIN fails locally
/// without waking the biometric prompt. On Apple / Android / Windows
/// the salt lives in `hardware_vault_salt.bin` next to the wrapped
/// key; on Linux it's co-located inside `hardware_vault.bin` since
/// the entire envelope is one file.
class HardwareTierVault {
  HardwareTierVault({Future<File> Function()? saltFileFactory, Random? random})
    : _saltFile = saltFileFactory ?? _defaultSaltFile,
      _random = random ?? Random.secure();

  static const _saltFileName = 'hardware_vault_salt.bin';
  static const _saltLength = 32;

  final Future<File> Function() _saltFile;
  final Random _random;

  static Future<File> _defaultSaltFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _saltFileName));
  }

  /// Every supported platform routes through Rust FRB —
  /// Apple SE + Android Keystore + Windows CNG via `lfs_os_security`,
  /// Linux TPM2 via `lfs_core::security::hardware_tier_vault::linux`
  /// (TPM CLI shell-out is a Rust subprocess; the FRB layer
  /// dispatches by `cfg(target_os = ...)`). No native-plugin path
  /// remains; Dart only paints the UI and forwards the PIN HMAC.
  bool get _usesRust =>
      Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isLinux ||
      Platform.isWindows;

  /// True when the current platform can host the Hardware tier
  /// *today*. The Rust FRB shim covers every supported OS — Apple
  /// SE / Android Keystore / Windows CNG via `lfs_os_security`,
  /// Linux TPM2 via `lfs_core::platform::linux::tpm` (CLI shell-out
  /// is a Rust subprocess).
  Future<bool> isAvailable() async {
    if (_usesRust) {
      return rust_vault.hardwareTierVaultIsAvailable();
    }
    return false;
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
    if (_usesRust) {
      return rust_vault.hardwareTierVaultProbeDetail();
    }
    return 'unknown';
  }

  /// True when a sealed blob is on disk. Linux inspects
  /// `hardware_vault.bin`; other platforms ask the native side plus
  /// verify that the Dart-side salt file is present (both halves
  /// required — a half-wiped state is a reset, not an unlock).
  Future<bool> isStored() async {
    try {
      if (_usesRust) {
        if (Platform.isLinux) {
          // Linux orchestrator co-locates salt + sealed inside
          // `hardware_vault.bin` — single-file presence is the
          // whole contract.
          final dir = await getApplicationSupportDirectory();
          return rust_vault.hardwareTierVaultIsStored(supportDir: dir.path);
        }
        // Apple / Android / Windows keep the wrapped key inside the
        // platform vault; the salt rides next to it on disk under
        // `hardware_vault_salt.bin`. Both halves required —
        // half-wiped state is a reset, not an unlock.
        final saltFile = await _saltFile();
        if (!await saltFile.exists()) return false;
        final dir = await getApplicationSupportDirectory();
        return rust_vault.hardwareTierVaultIsStored(supportDir: dir.path);
      }
      return false;
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
      final salt = _randomBytes(_saltLength);
      final authValue = _deriveAuth(pin, salt);
      if (_usesRust) {
        try {
          final dir = await getApplicationSupportDirectory();
          // Write the salt file BEFORE calling into the platform
          // vault — see `storeFromSecret` for the full rationale.
          // Salt-then-vault keeps the live state consistent against
          // a crash between the two writes; vault-then-salt would
          // leave the native side wrapping bytes against a salt
          // that no longer exists on disk → permanent lockout.
          // Linux co-locates the salt inside `hardware_vault.bin`
          // itself so no separate write is needed there.
          if (!Platform.isLinux) {
            await _writeSaltFile(salt);
          }
          await rust_vault.hardwareTierVaultStore(
            supportDir: dir.path,
            dbKey: dbKey,
            salt: salt,
            pinHmac: authValue,
          );
          return true;
        } catch (e) {
          AppLogger.instance.log(
            'HardwareTierVault.store (Rust): $e',
            name: 'HardwareTierVault',
          );
          return false;
        }
      }
      return false;
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
  /// `hardware_tier_vault_store_from_secret` so the bytes never
  /// cross the FRB boundary.
  Future<bool> storeFromSecret({required String secretId, String? pin}) async {
    try {
      if (!await isAvailable()) return false;
      final salt = _randomBytes(_saltLength);
      final authValue = _deriveAuth(pin, salt);
      if (_usesRust) {
        try {
          final dir = await getApplicationSupportDirectory();
          // Write the salt file BEFORE calling into the platform
          // vault. A crash between the vault commit and the salt
          // write would otherwise leave the native side wrapping
          // bytes against a salt that no longer exists on disk —
          // permanent lockout because the next read re-derives
          // `_deriveAuth(pin, fresh_salt)` and the chip refuses to
          // unwrap. Failing the salt write before touching the
          // vault means the live state stays whatever it was
          // before this call started; the user's prior entry (if
          // any) is intact and the next attempt re-derives a
          // fresh salt cleanly. Linux co-locates the salt inside
          // `hardware_vault.bin` itself so no separate write is
          // needed there.
          if (!Platform.isLinux) {
            await _writeSaltFile(salt);
          }
          await rust_vault.hardwareTierVaultStoreFromSecret(
            supportDir: dir.path,
            secretId: secretId,
            salt: salt,
            pinHmac: authValue,
          );
          return true;
        } catch (e) {
          AppLogger.instance.log(
            'HardwareTierVault.storeFromSecret (Rust): $e',
            name: 'HardwareTierVault',
          );
          return false;
        }
      }
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.storeFromSecret failed: $e',
        name: 'HardwareTierVault',
      );
      return false;
    }
  }

  /// Unseal the DB key using [pin]. Returns null on wrong PIN,
  /// missing state, unsupported platform, or any other failure —
  /// the rate limiter layered on top is responsible for backoff.
  ///
  /// When [pin] is null or empty the derivation mirrors [store]'s
  /// passwordless branch (empty auth value), so a vault sealed
  /// without a PIN unseals without a PIN.
  Future<Uint8List?> read(String? pin) async {
    try {
      if (!await isAvailable()) return null;
      if (_usesRust) {
        try {
          final dir = await getApplicationSupportDirectory();
          // Linux co-locates salt inside `hardware_vault.bin` and
          // exposes it via `hardwareTierVaultReadBlobSalt`. Apple /
          // Android / Windows keep it on disk in the sibling
          // `hardware_vault_salt.bin`.
          final salt = Platform.isLinux
              ? rust_vault.hardwareTierVaultReadBlobSalt(supportDir: dir.path)
              : await _readSaltFile();
          if (salt == null) return null;
          final authValue = _deriveAuth(pin, salt);
          return await rust_vault.hardwareTierVaultRead(
            supportDir: dir.path,
            pinHmac: authValue,
          );
        } catch (e) {
          AppLogger.instance.log(
            'HardwareTierVault.read (Rust): $e',
            name: 'HardwareTierVault',
          );
          return null;
        }
      }
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.read failed: $e',
        name: 'HardwareTierVault',
      );
      return null;
    }
  }

  /// Drop the sealed blob. Called on tier switch away from T2 and
  /// on PIN change (before a new [store]).
  Future<void> clear() async {
    try {
      if (_usesRust) {
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
        // Apple / Android / Windows keep the salt in a sibling file
        // Dart-side; drop it now. Linux co-locates and is already
        // cleared above.
        if (!Platform.isLinux) {
          final saltFile = await _saltFile();
          if (await saltFile.exists()) await saltFile.delete();
        }
        return;
      }
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault.clear failed: $e',
        name: 'HardwareTierVault',
      );
    }
  }

  Future<void> _writeSaltFile(Uint8List salt) async {
    final file = await _saltFile();
    await file.parent.create(recursive: true);
    // Salt is half of the unseal contract on every non-Linux platform
    // (the other half lives inside the Rust vault file); a torn salt
    // file from a mid-write crash would fail HMAC derivation and
    // permanently lock the user out. Atomic write rules out that
    // tear — the previous salt survives on failure.
    await writeBytesAtomic(file.path, salt);
  }

  Future<Uint8List?> _readSaltFile() async {
    try {
      final file = await _saltFile();
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length != _saltLength) return null;
      return bytes;
    } catch (e) {
      AppLogger.instance.log(
        'HardwareTierVault._readSaltFile failed: $e',
        name: 'HardwareTierVault',
      );
      return null;
    }
  }

  /// Derive a 32-byte auth value from the user's PIN + the
  /// per-install salt. HMAC-SHA256 rather than Argon2id because the
  /// hardware lockout is the rate limiter; slowing this derivation
  /// would only slow the legitimate user. Salting still matters —
  /// it keeps the sealed blob device-specific even when two users
  /// pick the same PIN.
  ///
  /// HMAC the typed pin under the per-install [salt], or return an
  /// empty auth value when the caller passed null / empty — the
  /// "passwordless T2" path. The empty value is a stable choice:
  /// every store / read pair derived this way agrees byte-for-byte,
  /// so a vault sealed passwordless always unseals passwordless.
  Uint8List _deriveAuth(String? pin, Uint8List salt) {
    if (pin == null || pin.isEmpty) return Uint8List(0);
    return rust_crypto.cryptoHmacSha256(
      key: salt,
      message: Uint8List.fromList(utf8.encode(pin)),
    );
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

  Uint8List _randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
