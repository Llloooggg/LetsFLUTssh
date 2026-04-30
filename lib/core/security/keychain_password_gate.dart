import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/keychain_op_prompt.dart' as rust_op_gate;
import '../../src/rust/api/keychain_password_gate.dart' as rust_gate;
import '../../src/rust/api/keychain_pepper_prompt.dart' as rust_pepper_gate;
import '../../utils/logger.dart';
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
/// Wire format + HMAC composition + salt/pepper generation +
/// disk I/O all live in
/// `lfs_core::security::keychain_password_gate_actor`. This Dart
/// class is a thin façade — the actor publishes
/// `KeychainOpPromptRequest` events when it needs the keychain
/// plugin (Dart-only territory), and `KeychainOpPromptListener`
/// answers them against `flutter_secure_storage`.
class KeychainPasswordGate {
  KeychainPasswordGate({Future<File> Function()? hashFileFactory})
    : _hashFile = hashFileFactory ?? _defaultHashFile;

  static const _hashFileName = 'security_pass_hash.bin';

  final Future<File> Function() _hashFile;

  static Future<File> _defaultHashFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _hashFileName));
  }

  /// True when a gate is configured on this install via
  /// `lfs_core::security::keychain_password_gate_actor::is_configured`
  /// (FRB async) — disk presence check + the
  /// `flutter_secure_storage.containsKey` round-trip live in Rust.
  Future<bool> isConfigured() async {
    final file = await _hashFile();
    return rust_op_gate.keychainPasswordGateIsConfigured(
      supportDir: file.parent.path,
    );
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
    final file = await _hashFile();
    await file.parent.create(recursive: true);
    await rust_op_gate.keychainPasswordGateSetPassword(
      supportDir: file.parent.path,
      password: password,
    );
  }

  /// True when [password] matches the stored hash. False on any
  /// failure (missing state, tampered blob, keychain unreadable).
  /// Never throws — callers treat false as "wrong password" and
  /// route through the rate limiter.
  ///
  /// Routes through `lfs_core::security::keychain_password_gate_actor::
  /// verify_password` (FRB async) — the disk-blob read +
  /// Decision-1 prompt round-trip + HMAC compare live in Rust.
  Future<bool> verify(String password) async {
    final file = await _hashFile();
    return rust_pepper_gate.keychainPasswordGateVerify(
      supportDir: file.parent.path,
      password: password,
    );
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
      final decoded = rust_gate.keychainGateDecodeBlob(blob: utf8.decode(raw));
      return PersistedRateLimiter(hmacKey: decoded.hmac);
    } on AnyhowException catch (_) {
      // Disk blob unparseable — caller treats null as "no rate
      // limiter available, fall through to wrong-password path".
      return null;
    } catch (e) {
      AppLogger.instance.log(
        'KeychainPasswordGate.rateLimiter failed: $e',
        name: 'KeychainPasswordGate',
      );
      return null;
    }
  }

  /// Drop every artifact the gate writes via
  /// `lfs_core::security::keychain_password_gate_actor::clear` —
  /// the disk delete + the `flutter_secure_storage.delete`
  /// round-trip live in Rust. Called on tier switch away from L2
  /// and on breaking-change reset.
  Future<void> clear() async {
    final file = await _hashFile();
    await rust_op_gate.keychainPasswordGateClear(supportDir: file.parent.path);
  }
}
