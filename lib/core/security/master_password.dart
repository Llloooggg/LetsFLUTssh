import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/master_password.dart' as rust_mp;
import '../../utils/logger.dart';
import 'kdf_params.dart';
import 'password_rate_limiter.dart';

/// Manages optional master password protection.
///
/// Thin façade over `lfs_core::security::master_password`. The Rust
/// side owns the on-disk file format (`credentials.kdf` /
/// `credentials.verify`), the Argon2id wall-clock cost, and the
/// AES-GCM verifier round-trip. This class translates the platform
/// app-support path into FRB calls and hands the rate-limiter wrapper
/// to the unlock UI.
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
  /// Tests may lower it via [debugSetKdfParams] so enable / verify
  /// cycles don't spend seconds each, stretching the full suite into
  /// minutes.
  static KdfParams _defaultParams = KdfParams.productionDefaults;

  /// Lower KDF cost for tests. Restores to production defaults when
  /// called with null. NEVER call from production code.
  @visibleForTesting
  static void debugSetKdfParams(KdfParams? params) {
    _defaultParams = params ?? KdfParams.productionDefaults;
  }

  String? _basePath;

  /// Per-instance rate limiter for [verifyAndDerive] attempts. In-
  /// memory by design — the real brake against offline brute-force is
  /// the Argon2id KDF's wall-clock cost; a persisted counter here
  /// would be security theatre (attacker runs Argon2id directly
  /// against `credentials.kdf` without ever touching our UI) and
  /// user-hostile (forgot-password cooldown survives restart for no
  /// extra protection). This limiter exists to frustrate a coworker
  /// at the desk poking at the unlock dialog.
  final PasswordRateLimiter _rateLimiter;

  /// Inject base path + rate limiter for testing. Production code
  /// passes neither; a fresh `InMemoryRateLimiter` lives per
  /// [MasterPasswordManager] instance.
  MasterPasswordManager({String? basePath, PasswordRateLimiter? rateLimiter})
    : _basePath = basePath,
      _rateLimiter = rateLimiter ?? InMemoryRateLimiter();

  /// Current rate-limit status. UI reads this to render a cooldown
  /// countdown in place of the password field when
  /// [RateLimitStatus.isLocked] is true.
  RateLimitStatus rateLimitStatus() => _rateLimiter.status();

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

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
    final basePath = await _getBasePath();
    return rust_mp.masterPasswordIsEnabled(supportDir: basePath);
  }

  /// Derive a 256-bit key from password using the on-disk KDF params.
  ///
  /// Runs on the Rust core's blocking pool — Argon2id is CPU + memory
  /// heavy (400-1500ms wall-clock at the production profile) but the
  /// FRB worker thread isn't pinned for the duration.
  Future<Uint8List> deriveKey(String password) async {
    final basePath = await _getBasePath();
    try {
      final out = await rust_mp.masterPasswordDeriveKey(
        supportDir: basePath,
        password: password,
      );
      return Uint8List.fromList(out);
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
  }

  /// Verify a password against the stored verifier.
  ///
  /// Returns true if the password is correct.
  ///
  /// Prefer [verifyAndDerive] when the caller will immediately need
  /// the derived key — that variant runs the KDF once instead of twice.
  Future<bool> verify(String password) async {
    final derived = await verifyAndDerive(password);
    return derived != null;
  }

  /// Single-KDF unlock: verify the password and, on success, return
  /// the derived DB key; return null on wrong password.
  ///
  /// One Argon2id pass instead of two — the legacy Dart path called
  /// `verify` then `deriveKey` back-to-back, both running KDF.
  Future<Uint8List?> verifyAndDerive(
    String password, {
    bool useRateLimit = false,
  }) async {
    // Rate limit is opt-in for UI unlock paths (UnlockDialog,
    // LockScreen). Internal call sites — changePassword, tests —
    // keep the default false so a sequence of password verifications
    // the user didn't type one by one never trips the bystander
    // cooldown.
    if (useRateLimit && _rateLimiter.status().isLocked) return null;

    final basePath = await _getBasePath();
    Uint8List? key;
    try {
      final out = await rust_mp.masterPasswordVerifyAndDerive(
        supportDir: basePath,
        password: password,
      );
      key = out == null ? null : Uint8List.fromList(out);
    } on AnyhowException catch (e) {
      throw MasterPasswordException(e.message);
    }
    if (useRateLimit) {
      if (key == null) {
        _rateLimiter.recordFailure();
      } else {
        _rateLimiter.recordSuccess();
      }
    }
    return key;
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
  Future<Uint8List> enable(String password) async {
    final basePath = await _getBasePath();
    try {
      final out = await rust_mp.masterPasswordEnable(
        supportDir: basePath,
        password: password,
        params: _wireParams(_defaultParams),
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

  /// Change master password.
  ///
  /// 1. Verify old password
  /// 2. Generate new salt + derive new key with the current default
  ///    params
  /// 3. Update verifier + `credentials.kdf`
  /// 4. Returns the new key (caller re-encrypts stores)
  Future<Uint8List> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    final basePath = await _getBasePath();
    try {
      final out = await rust_mp.masterPasswordChange(
        supportDir: basePath,
        oldPassword: oldPassword,
        newPassword: newPassword,
        params: _wireParams(_defaultParams),
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

  /// Disable master password protection.
  ///
  /// Deletes KDF and verifier files. The caller is responsible for
  /// re-encrypting stores with a new random key and saving it to
  /// `credentials.key`.
  Future<void> disable() async {
    final basePath = await _getBasePath();
    try {
      rust_mp.masterPasswordDisable(supportDir: basePath);
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
    final basePath = await _getBasePath();
    try {
      rust_mp.masterPasswordReset(supportDir: basePath);
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
