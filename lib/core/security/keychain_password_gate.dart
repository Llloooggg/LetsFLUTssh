import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/keychain_pepper_prompt.dart' as rust_pepper_gate;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '_crypto_compat.dart';
import 'password_rate_limiter.dart';

/// UX-only password gate for L2 (keychain + password).
///
/// Design: the DB key lives in the OS keychain exactly like L1.
/// A short user-typed password is held as a salted HMAC so the
/// unlock dialog can reject the wrong value *before* touching the
/// keychain. The hash is stored split across disk + keychain —
/// salt + stored-HMAC on disk in `security_pass_hash.bin`, HMAC
/// pepper in the OS keychain under `letsflutssh_l2_pepper`.
///
/// **This gate is UX-only, by design.** An attacker who has access
/// to both the disk AND the OS keychain already has every
/// ingredient needed to decrypt the DB directly — they do not need
/// to guess the password at all. The gate exists to frustrate a
/// casual bystander reaching for the app on an unlocked machine.
/// The [PersistedRateLimiter] layered on top of it slows manual
/// guessing across process restarts without trying to protect
/// against offline attack.
///
/// Wire format + HMAC composition + salt/pepper generation live in
/// `lfs_core::security::keychain_password_gate` so the on-disk
/// envelope shape stays in sync with future bumps. This Dart class
/// orchestrates the file I/O + keychain plugin calls; the
/// crypto-shaped operations route through the compat wrappers in
/// `_crypto_compat.dart`.
class KeychainPasswordGate {
  KeychainPasswordGate({
    FlutterSecureStorage? keychain,
    Future<File> Function()? hashFileFactory,
  }) : _keychain = keychain ?? const FlutterSecureStorage(),
       _hashFile = hashFileFactory ?? _defaultHashFile;

  static const _pepperKey = 'letsflutssh_l2_pepper';
  static const _hashFileName = 'security_pass_hash.bin';

  final FlutterSecureStorage _keychain;
  final Future<File> Function() _hashFile;

  static Future<File> _defaultHashFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _hashFileName));
  }

  /// True when a gate is configured on this install.
  Future<bool> isConfigured() async {
    try {
      final file = await _hashFile();
      if (!await file.exists()) return false;
      return await _keychain.containsKey(key: _pepperKey);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.isConfigured failed: $e',
        name: 'KeychainPasswordGate',
      );
      return false;
    }
  }

  /// Configure the gate with [password]. Generates a fresh salt on
  /// disk and a fresh pepper in the OS keychain; the resulting HMAC
  /// is also written to disk.
  ///
  /// Also drops any persisted rate-limit state tied to the *previous*
  /// HMAC. Without this step a fresh password write would flip the
  /// `PersistedRateLimiter`'s HMAC key while the leftover
  /// `rate_limit_state.bin` still carried a signature keyed to the
  /// old hash — the next status load would hit the HMAC-mismatch
  /// tamper branch and throw the user into the worst-case 60-second
  /// cooldown on first launch. Wiping the state here aligns the
  /// counter with the new password.
  Future<void> setPassword(String password) async {
    final seed = keychainGateRandomSeedCompat();
    final hmac = keychainGateComputeHmacCompat(
      seed.pepper,
      seed.salt,
      password,
    );

    final file = await _hashFile();
    await file.parent.create(recursive: true);
    final blob = keychainGateEncodeBlobCompat(seed.salt, hmac);
    // Two invariants, both load-bearing for L2:
    //
    //   (1) Atomic write of the disk hash. A `File.writeAsBytes` crash
    //       mid-flush yields torn JSON; next launch `verify()` throws
    //       on decode and falls back to plaintext-tier unlock — the
    //       user thought L2 protected them, wakes up on L0.
    //   (2) Disk before keychain. Old order (keychain-first) could
    //       crash between steps and leave keychain holding the NEW
    //       pepper while disk holds the OLD salt+HMAC; on next launch
    //       the correct password fails to verify (HMAC mismatch),
    //       forcing "forgot password" wipe. Disk-first means a crash
    //       between steps leaves the OLD state fully verifiable under
    //       the OLD pepper still in the keychain.
    await writeBytesAtomic(file.path, utf8.encode(blob));
    try {
      await _keychain.write(key: _pepperKey, value: base64.encode(seed.pepper));
    } catch (e) {
      // Keychain write failed after the disk hash landed. The gate is
      // now half-configured — pepper missing, disk hash present but
      // unverifiable. Delete the disk hash so `isConfigured()` returns
      // false and the next open routes through the wizard instead of
      // perma-rejecting the correct password.
      try {
        await file.delete();
      } catch (rollbackErr) {
        // Disk rollback itself failed — the next launch will see a
        // half-configured gate. Log both errors so a support trace
        // captures why `isConfigured()` will report true but
        // `verify()` can never succeed.
        AppLogger.instance.log(
          'KeychainPasswordGate: rollback delete failed after keychain '
          'write failed: $rollbackErr (original error: $e)',
          name: 'KeychainPasswordGate',
        );
      }
      rethrow;
    }

    await _clearRateLimitState();
  }

  /// Delete the persisted rate-limit state file so the next
  /// [rateLimiter] starts with a zero failure counter. Best-effort —
  /// a log + swallow is preferable to blocking the password write
  /// on a filesystem hiccup.
  Future<void> _clearRateLimitState() async {
    try {
      final hashFile = await _hashFile();
      final stateFile = File(
        p.join(hashFile.parent.path, 'rate_limit_state.bin'),
      );
      if (await stateFile.exists()) await stateFile.delete();
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate: failed to clear rate-limit state: $e',
        name: 'KeychainPasswordGate',
      );
    }
  }

  /// True when [password] matches the stored hash. False on any
  /// failure (missing state, tampered blob, keychain unreadable).
  /// Never throws — callers treat false as "wrong password" and
  /// route through the rate limiter.
  ///
  /// Routes through `lfs_core::security::keychain_password_gate_actor::
  /// verify_password` (FRB async) so the disk-blob read +
  /// Decision-1 prompt round-trip + HMAC compare lives one
  /// place. Falls back to the inline Dart pipeline when the
  /// FRB native lib is not loaded (flutter_test contexts that
  /// don't load `RustLib`).
  Future<bool> verify(String password) async {
    try {
      final file = await _hashFile();
      final supportDir = file.parent.path;
      return await rust_pepper_gate.keychainPasswordGateVerify(
        supportDir: supportDir,
        password: password,
      );
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.verify FRB unreachable, '
        'falling back to Dart pipeline: $e',
        name: 'KeychainPasswordGate',
      );
    }
    try {
      final file = await _hashFile();
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final decoded = keychainGateDecodeBlobCompat(utf8.decode(raw));
      if (decoded == null) return false;

      final pepperB64 = await _keychain.read(key: _pepperKey);
      if (pepperB64 == null) return false;
      final pepper = base64.decode(pepperB64);

      final computed = keychainGateComputeHmacCompat(
        pepper,
        decoded.salt,
        password,
      );
      return constantTimeEqCompat(computed, decoded.hmac);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.verify failed: $e',
        name: 'KeychainPasswordGate',
      );
      return false;
    }
  }

  /// Build a [PersistedRateLimiter] bound to the current stored HMAC.
  /// The HMAC is the secret: anyone who can forge a tampered
  /// rate-limit state file would need to also have both disk-hash +
  /// keychain-pepper, i.e. already enough to decrypt the DB.
  ///
  /// Returns null when the gate has never been configured — caller
  /// should fall through to "wrong password" without rate-limiting
  /// (there is nothing to guard).
  Future<PasswordRateLimiter?> rateLimiter() async {
    try {
      final file = await _hashFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsBytes();
      final decoded = keychainGateDecodeBlobCompat(utf8.decode(raw));
      if (decoded == null) return null;
      return PersistedRateLimiter(hmacKey: decoded.hmac);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.rateLimiter failed: $e',
        name: 'KeychainPasswordGate',
      );
      return null;
    }
  }

  /// Drop every artifact the gate writes. Called on tier switch
  /// away from L2 and on breaking-change reset.
  Future<void> clear() async {
    try {
      final file = await _hashFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.clear hash file failed: $e',
        name: 'KeychainPasswordGate',
      );
    }
    try {
      await _keychain.delete(key: _pepperKey);
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.clear pepper failed: $e',
        name: 'KeychainPasswordGate',
      );
    }
  }
}
