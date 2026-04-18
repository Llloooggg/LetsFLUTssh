import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Manages optional master password protection.
///
/// When enabled, the AES-256 encryption key is derived from the user's password
/// via PBKDF2 (600k iterations, SHA-256) instead of being stored in a key file.
///
/// Detection: presence of `credentials.salt` = master password is enabled.
/// Verification: `credentials.verify` contains AES-256-GCM encrypted known
/// plaintext, validated on unlock to detect wrong passwords without needing
/// to decrypt the full credential store.
class MasterPasswordManager {
  static const _saltFileName = 'credentials.salt';
  static const _verifierFileName = 'credentials.verify';
  static const _keyFileName = 'credentials.key';
  static const _saltLength = 32;
  static const _keyLength = 32;
  static const _ivLength = 12;
  static const _pbkdf2IterationsProd = 600000;

  /// PBKDF2 iteration count. Constant in production — tests may lower it
  /// via [debugSetPbkdf2Iterations] so enable/verify cycles don't spend
  /// 500 ms each, stretching the full suite into minutes.
  static int _pbkdf2Iterations = _pbkdf2IterationsProd;

  /// Lower PBKDF2 iterations for tests. Restores to production value when
  /// called with null. NEVER call from production code.
  static void debugSetPbkdf2Iterations(int? iterations) {
    _pbkdf2Iterations = iterations ?? _pbkdf2IterationsProd;
  }

  /// Known plaintext encrypted in the verifier file.
  static const _verifierPlaintext = 'LetsFLUTssh-verify';

  String? _basePath;

  /// Inject base path for testing.
  MasterPasswordManager({String? basePath}) : _basePath = basePath;

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Whether master password protection is enabled (salt file exists).
  Future<bool> isEnabled() async {
    final basePath = await _getBasePath();
    return File('$basePath/$_saltFileName').exists();
  }

  /// Derive a 256-bit key from password + salt using PBKDF2-SHA256.
  ///
  /// Runs in an isolate because 600k iterations is CPU-heavy (~500ms).
  Future<Uint8List> deriveKey(String password) async {
    final basePath = await _getBasePath();
    final saltFile = File('$basePath/$_saltFileName');
    if (!await saltFile.exists()) {
      throw const MasterPasswordException('Master password is not enabled');
    }
    final salt = await saltFile.readAsBytes();
    // Capture the current iteration count in the main isolate so
    // debugSetPbkdf2Iterations (tests only) crosses the isolate boundary.
    final iterations = _pbkdf2Iterations;
    return Isolate.run(() => _deriveKeySync(password, salt, iterations));
  }

  /// Verify a password against the stored verifier.
  ///
  /// Returns true if the password is correct.
  ///
  /// Prefer [verifyAndDerive] when the caller will immediately need the
  /// derived key — that variant runs the 600k-iteration PBKDF2 once
  /// instead of twice.
  Future<bool> verify(String password) async {
    final derived = await verifyAndDerive(password);
    return derived != null;
  }

  /// Single-PBKDF2 unlock: verify the password and, on success, return
  /// the derived DB key; return null on wrong password.
  ///
  /// The legacy unlock path called [verify] and then [deriveKey] back
  /// to back — two isolate spawns + two 600k-iteration KDF runs for
  /// each unlock. Users on mid-tier mobiles reported 3-5 s between
  /// tapping unlock and the UI advancing. This combined variant runs
  /// the KDF once inside a single isolate and returns the same bytes
  /// the verifier was checked against, halving unlock latency on
  /// every platform.
  Future<Uint8List?> verifyAndDerive(String password) async {
    final basePath = await _getBasePath();
    final saltFile = File('$basePath/$_saltFileName');
    final verifierFile = File('$basePath/$_verifierFileName');

    if (!await saltFile.exists() || !await verifierFile.exists()) {
      throw const MasterPasswordException('Master password is not enabled');
    }

    final salt = await saltFile.readAsBytes();
    final verifierData = await verifierFile.readAsBytes();
    final iterations = _pbkdf2Iterations;

    return Isolate.run(() {
      final key = _deriveKeySync(password, salt, iterations);
      if (!_verifySync(key, verifierData)) return null;
      return key;
    });
  }

  /// Enable master password protection.
  ///
  /// 1. Generates random salt
  /// 2. Derives key from password
  /// 3. Creates verifier file
  /// 4. Returns the derived key (caller re-encrypts stores with it)
  ///
  /// The caller is responsible for:
  /// - Re-encrypting SessionStore, KeyStore, and KnownHostsManager with
  ///   the returned key
  Future<Uint8List> enable(String password) async {
    final basePath = await _getBasePath();
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );

    final iterations = _pbkdf2Iterations;
    final key = await Isolate.run(
      () => _deriveKeySync(password, salt, iterations),
    );

    // Create verifier: encrypt known plaintext
    final verifierData = _encryptVerifier(key);

    // Write salt and verifier atomically
    await writeBytesAtomic('$basePath/$_saltFileName', salt);
    await writeBytesAtomic('$basePath/$_verifierFileName', verifierData);

    AppLogger.instance.log('Master password enabled', name: 'MasterPassword');
    return key;
  }

  /// Change master password.
  ///
  /// 1. Verify old password
  /// 2. Generate new salt + derive new key
  /// 3. Update verifier
  /// 4. Returns the new key (caller re-encrypts stores)
  Future<Uint8List> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    final isValid = await verify(oldPassword);
    if (!isValid) {
      throw const MasterPasswordException('Current password is incorrect');
    }

    final basePath = await _getBasePath();
    final random = Random.secure();
    final newSalt = Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );

    final iterations = _pbkdf2Iterations;
    final newKey = await Isolate.run(
      () => _deriveKeySync(newPassword, newSalt, iterations),
    );

    final verifierData = _encryptVerifier(newKey);

    await writeBytesAtomic('$basePath/$_saltFileName', newSalt);
    await writeBytesAtomic('$basePath/$_verifierFileName', verifierData);

    AppLogger.instance.log('Master password changed', name: 'MasterPassword');
    return newKey;
  }

  /// Disable master password protection.
  ///
  /// Deletes salt and verifier files. The caller is responsible for
  /// re-encrypting stores with a new random key and saving it to
  /// `credentials.key`.
  Future<void> disable() async {
    final basePath = await _getBasePath();
    final saltFile = File('$basePath/$_saltFileName');
    final verifierFile = File('$basePath/$_verifierFileName');

    if (await saltFile.exists()) await saltFile.delete();
    if (await verifierFile.exists()) await verifierFile.delete();

    AppLogger.instance.log('Master password disabled', name: 'MasterPassword');
  }

  /// Reset all encrypted data (used when password is forgotten).
  ///
  /// Deletes salt, verifier, key, and all encrypted store files.
  /// This is destructive — all saved passwords and keys are lost.
  Future<void> reset() async {
    final basePath = await _getBasePath();
    final files = [
      '$basePath/$_saltFileName',
      '$basePath/$_verifierFileName',
      '$basePath/$_keyFileName',
      '$basePath/credentials.enc',
      '$basePath/keys.enc',
    ];
    for (final path in files) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    AppLogger.instance.log(
      'Master password reset — all encrypted data deleted',
      name: 'MasterPassword',
    );
  }

  // ── Static helpers (run in isolate) ──────────────────────────────

  static Uint8List _deriveKeySync(
    String password,
    Uint8List salt,
    int iterations,
  ) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _keyLength));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  static bool _verifySync(Uint8List key, Uint8List verifierData) {
    if (verifierData.length < _ivLength + 1) return false;
    final iv = verifierData.sublist(0, _ivLength);
    final ciphertext = verifierData.sublist(_ivLength);

    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final output = cipher.process(ciphertext);
      return utf8.decode(output) == _verifierPlaintext;
    } catch (_) {
      return false;
    }
  }

  /// Encrypt the known verifier plaintext with the given key.
  static Uint8List _encryptVerifier(Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(_ivLength, (_) => random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final plainBytes = Uint8List.fromList(utf8.encode(_verifierPlaintext));
    final output = cipher.process(plainBytes);
    return Uint8List.fromList([...iv, ...output]);
  }
}

/// Thrown when master password operations fail.
class MasterPasswordException implements Exception {
  final String message;

  const MasterPasswordException(this.message);

  @override
  String toString() => 'MasterPasswordException: $message';
}
