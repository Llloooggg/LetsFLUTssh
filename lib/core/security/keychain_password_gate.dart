import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
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
/// Wiring into the wizard / unlock flow lands on top of this class.
class KeychainPasswordGate {
  KeychainPasswordGate({
    FlutterSecureStorage? keychain,
    Future<File> Function()? hashFileFactory,
    Random? random,
  }) : _keychain = keychain ?? const FlutterSecureStorage(),
       _hashFile = hashFileFactory ?? _defaultHashFile,
       _random = random ?? Random.secure();

  static const _pepperKey = 'letsflutssh_l2_pepper';
  static const _hashFileName = 'security_pass_hash.bin';
  static const _saltLength = 32;
  static const _pepperLength = 32;

  final FlutterSecureStorage _keychain;
  final Future<File> Function() _hashFile;
  final Random _random;

  static Future<File> _defaultHashFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _hashFileName));
  }

  Uint8List _rand(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// Derive the comparison HMAC for [password] given [salt] and
  /// [pepper]. Same function used for both set and verify — any
  /// divergence between the two paths is a bug.
  Uint8List _computeHmac(String password, Uint8List salt, Uint8List pepper) {
    final mac = Hmac(sha256, pepper);
    final sb = BytesBuilder()
      ..add(salt)
      ..add(utf8.encode(password));
    return Uint8List.fromList(mac.convert(sb.toBytes()).bytes);
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
  Future<void> setPassword(String password) async {
    final salt = _rand(_saltLength);
    final pepper = _rand(_pepperLength);
    final hmac = _computeHmac(password, salt, pepper);

    await _keychain.write(key: _pepperKey, value: base64.encode(pepper));

    final file = await _hashFile();
    await file.parent.create(recursive: true);
    final blob = jsonEncode({
      'salt': base64.encode(salt),
      'hmac': base64.encode(hmac),
    });
    await file.writeAsBytes(utf8.encode(blob), flush: true);
    await hardenFilePerms(file.path);
  }

  /// True when [password] matches the stored hash. False on any
  /// failure (missing state, tampered blob, keychain unreadable).
  /// Never throws — callers treat false as "wrong password" and
  /// route through the rate limiter.
  Future<bool> verify(String password) async {
    try {
      final file = await _hashFile();
      if (!await file.exists()) return false;
      final raw = await file.readAsBytes();
      final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final saltB64 = decoded['salt'];
      final hmacB64 = decoded['hmac'];
      if (saltB64 is! String || hmacB64 is! String) return false;
      final salt = base64.decode(saltB64);
      final storedHmac = base64.decode(hmacB64);

      final pepperB64 = await _keychain.read(key: _pepperKey);
      if (pepperB64 == null) return false;
      final pepper = base64.decode(pepperB64);

      final computed = _computeHmac(password, salt, pepper);
      return _constantTimeEqual(computed, storedHmac);
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
      final decoded = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final hmacB64 = decoded['hmac'];
      if (hmacB64 is! String) return null;
      final storedHmac = base64.decode(hmacB64);
      return PersistedRateLimiter(hmacKey: Uint8List.fromList(storedHmac));
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

  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
