import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../../src/rust/api/master_password.dart' as rust_mp;
import '../../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../../utils/logger.dart';
import 'kdf_params.dart';
import 'password_rate_limiter.dart';
import 'tier_unlock_attempt.dart';

/// Manages optional master password protection.
///
/// Thin façade over `lfs_core::security::master_password`. The Rust
/// side owns the on-disk file format (`credentials.kdf` /
/// `credentials.verify`), the Argon2id wall-clock cost, the AES-GCM
/// verifier round-trip, **and** the support-dir resolution (pinned
/// at `configStoreInit` time in main.dart). This class is a thin FRB
/// shim plus the rate-limiter wrapper for the unlock UI.
///
/// **File format** (owned Rust-side, mirror in `lfs_core::security::
/// master_password::decode_kdf_record`):
/// ```
///   offset 0   magic 'LFKD'          (4)
///   offset 4   file version 0x01     (1)
///   offset 5   KDF algorithm id      (1)
///   offset 6   KDF params            (10 for Argon2id)
///   offset N   salt                  (32)
/// ```
class MasterPasswordManager {
  /// The Argon2id profile used for fresh enable / changePassword calls.
  /// Tests pass an explicit cheap `kdfParams` so the enable / verify
  /// cycles don't spend seconds each. Production passes nothing — the
  /// default lands on `KdfParams.productionDefaults`, the Dart mirror
  /// of `lfs_core::security::master_password::KdfParams::defaults`.
  final KdfParams _kdfParams;

  /// Per-instance rate limiter for [verifyAndDerive] attempts. In-
  /// memory by design — the real brake against offline brute-force is
  /// the Argon2id KDF's wall-clock cost; a persisted counter here
  /// would be security theatre (attacker runs Argon2id directly
  /// against `credentials.kdf` without ever touching our UI) and
  /// user-hostile (forgot-password cooldown survives restart for no
  /// extra protection). This limiter exists to frustrate a coworker
  /// at the desk poking at the unlock dialog.
  final PasswordRateLimiter _rateLimiter;

  /// Inject rate limiter + KDF params for testing. Production code
  /// passes nothing; a fresh `InMemoryRateLimiter` lives per
  /// [MasterPasswordManager] instance, and `kdfParams` defaults to
  /// [KdfParams.productionDefaults]. Tests pass an explicit cheap
  /// `kdfParams` (memoryKiB: 8, iterations: 1) so the Argon2id KDF
  /// runs in milliseconds instead of seconds.
  MasterPasswordManager({
    PasswordRateLimiter? rateLimiter,
    KdfParams? kdfParams,
  }) : _rateLimiter = rateLimiter ?? InMemoryRateLimiter(),
       _kdfParams = kdfParams ?? KdfParams.productionDefaults;

  /// Current rate-limit status. UI reads this to render a cooldown
  /// countdown in place of the password field when
  /// [RateLimitStatus.isLocked] is true.
  RateLimitStatus rateLimitStatus() => _rateLimiter.status();

  static rust_mp.DbKdfParams _wireParams(KdfParams params) {
    // The Rust file-format reader rejects non-Argon2id algorithm ids,
    // so even if a future enum case lands Dart-side it cannot leak
    // into a `credentials.kdf` write without a matching Rust update.
    return rust_mp.DbKdfParams(
      memoryKib: params.memoryKiB,
      iterations: params.iterations,
      parallelism: params.parallelism,
    );
  }

  /// Whether master password protection is enabled — the Argon2id
  /// KDF file exists.
  Future<bool> isEnabled() async {
    return rust_mp.masterPasswordIsEnabled();
  }

  /// Verify a password against the stored verifier.
  ///
  /// Returns true if the password is correct. No rate-limit gating,
  /// no cascade — internal verify callers (settings password change
  /// confirmation, tests) need the raw boolean without dragging the
  /// unlock listener into a non-unlock flow.
  Future<bool> verify(Uint8List password) async {
    final derived = await verifyAndDerive(password);
    return derived != null;
  }

  /// Single-KDF derive: verify the password and, on success, return
  /// the derived DB key; return null on wrong password. Hits the raw
  /// `master_password_verify_and_derive` shim — no rate limiter, no
  /// orchestrator cascade. Used by re-key flows (changePassword) and
  /// settings-side password confirmation where the caller wants the
  /// bytes for an immediate non-unlock action.
  ///
  /// UI unlock paths (UnlockDialog, LockScreen) MUST NOT call this —
  /// they use [unlockAttempt] which routes through the Paranoid
  /// orchestrator (stages key + emits cascade) so the listener
  /// pattern owns the post-unlock cascade.
  Future<Uint8List?> verifyAndDerive(Uint8List password) async {
    try {
      final out = await rust_mp.masterPasswordVerifyAndDerive(
        password: password,
      );
      return out == null ? null : Uint8List.fromList(out);
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// SecretRef variant of [verifyAndDerive]. Stages the derived
  /// key directly into the SecretStore under [secretId] — bytes
  /// never cross the FRB boundary. Returns true when the password
  /// was correct + bytes landed under [secretId]; false on wrong
  /// password (no SecretStore mutation). Throws
  /// [MasterPasswordException] on tier-not-enabled / file-corrupt.
  Future<bool> verifyAndDeriveToSecret(
    Uint8List password,
    String secretId,
  ) async {
    try {
      return await rust_mp.masterPasswordVerifyAndDeriveToSecret(
        password: password,
        secretId: secretId,
      );
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// User-typed unlock attempt. Routes through the
  /// `tier_unlock_paranoid` orchestrator which:
  ///   1. dispatches `UnlockRequested` against `tier_machine`,
  ///   2. runs Argon2id to derive the DB key,
  ///   3. on success: stages the key under
  ///      `tier_unlock_orchestrator::TIER_UNLOCK_KEY_ID` + dispatches
  ///      `UnlockSucceeded` (the `TierUnlockedListener` takes the
  ///      bytes via `secrets_take` on the cascade event),
  ///   4. on wrong password / corruption: dispatches `UnlockFailed`.
  ///
  /// Returns the [TierUnlockAttempt] discriminant — bytes never
  /// cross FRB on the return value (plaintext discipline). The
  /// in-memory rate limiter still gates UI re-attempts; the real
  /// brake against offline brute is the Argon2id wall-clock.
  Future<TierUnlockAttempt> unlockAttempt(Uint8List password) async {
    if (_rateLimiter.status().isLocked) {
      return TierUnlockAttempt.wrongSecret;
    }
    final outcome = await rust_orch.tierUnlockParanoid(password: password);
    final attempt = mapUnlockOutcome(outcome);
    if (attempt == TierUnlockAttempt.staged) {
      _rateLimiter.recordSuccess();
    } else if (attempt == TierUnlockAttempt.wrongSecret) {
      _rateLimiter.recordFailure();
    }
    return attempt;
  }

  /// Enable master password protection.
  ///
  /// 1. Generates random salt (Rust-side `OsRng`)
  /// 2. Derives key with the production Argon2id profile
  /// 3. Writes `credentials.kdf` + `credentials.verify` atomically
  /// 4. Returns the derived key (caller re-encrypts stores with it)
  ///
  /// The caller is responsible for re-encrypting SessionStore,
  /// KeyStore, and KnownHostsManager with the returned key.
  Future<Uint8List> enable(Uint8List password) async {
    try {
      final out = await rust_mp.masterPasswordEnable(
        password: password,
        params: _wireParams(_kdfParams),
      );
      AppLogger.instance.log(
        'Master password enabled (Argon2id)',
        name: 'MasterPassword',
      );
      return Uint8List.fromList(out);
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// SecretRef variant of [enable]. Stages the derived key directly
  /// into the Rust-side `SecretStore` under [secretId] instead of
  /// returning the bytes — caller routes the same id through
  /// `dbRekeyFromSecret` / `setFromSecret` so the AES bytes never
  /// touch the Dart heap.
  Future<void> enableToSecret(Uint8List password, String secretId) async {
    try {
      await rust_mp.masterPasswordEnableToSecret(
        password: password,
        params: _wireParams(_kdfParams),
        secretId: secretId,
      );
      AppLogger.instance.log(
        'Master password enabled (Argon2id, SecretRef)',
        name: 'MasterPassword',
      );
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// Change master password.
  ///
  /// 1. Verify old password
  /// 2. Generate new salt + derive new key with the current default
  ///    params
  /// 3. Update verifier + `credentials.kdf`
  /// 4. Returns the new key (caller re-encrypts stores)
  Future<Uint8List> changePassword(
    Uint8List oldPassword,
    Uint8List newPassword,
  ) async {
    try {
      final out = await rust_mp.masterPasswordChange(
        oldPassword: oldPassword,
        newPassword: newPassword,
        params: _wireParams(_kdfParams),
      );
      AppLogger.instance.log(
        'Master password changed (Argon2id)',
        name: 'MasterPassword',
      );
      return Uint8List.fromList(out);
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// SecretRef variant of [changePassword]. Stages the freshly-
  /// derived key directly into the Rust-side `SecretStore` under
  /// [secretId] instead of returning the bytes — caller routes the
  /// same id through `dbRekeyFromSecret` so the new AES bytes
  /// never touch the Dart heap. Finishes the master-password
  /// SecretRef family alongside [enableToSecret] and
  /// [verifyAndDeriveToSecret].
  Future<void> changePasswordToSecret(
    Uint8List oldPassword,
    Uint8List newPassword,
    String secretId,
  ) async {
    try {
      await rust_mp.masterPasswordChangeToSecret(
        oldPassword: oldPassword,
        newPassword: newPassword,
        params: _wireParams(_kdfParams),
        secretId: secretId,
      );
      AppLogger.instance.log(
        'Master password changed (Argon2id, SecretRef)',
        name: 'MasterPassword',
      );
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// Disable master password protection.
  ///
  /// Deletes KDF and verifier files. The caller is responsible for
  /// re-encrypting stores with a new random key and saving it to
  /// `credentials.key`.
  Future<void> disable() async {
    try {
      rust_mp.masterPasswordDisable();
      AppLogger.instance.log(
        'Master password disabled',
        name: 'MasterPassword',
      );
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// Reset all encrypted data (used when password is forgotten).
  ///
  /// Deletes KDF salt, verifier, and key files. Destructive — all
  /// saved passwords and keys are lost.
  Future<void> reset() async {
    try {
      rust_mp.masterPasswordReset();
      AppLogger.instance.log(
        'Master password reset — all encrypted data deleted',
        name: 'MasterPassword',
      );
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }
}

/// Thrown when master password operations fail. Wraps the Rust
/// error string so callers can branch on "Master password is not
/// enabled" / "Current password is incorrect" without parsing
/// exception types.
class MasterPasswordException implements Exception {
  final String message;

  const MasterPasswordException(this.message);

  @override
  String toString() => 'MasterPasswordException: $message';
}
