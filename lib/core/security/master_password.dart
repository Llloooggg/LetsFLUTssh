import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'kdf_params.dart';

/// Manages optional master password protection.
///
/// When enabled, the AES-256 encryption key is derived from the user's
/// password via Argon2id (see [KdfParams.productionDefaults]) instead of
/// being stored in a key file.
///
/// **File format** (`credentials.kdf`, v1):
/// ```
///   offset 0   magic 'LFKD'          (4)
///   offset 4   file version 0x01     (1)
///   offset 5   KDF algorithm id      (1)
///   offset 6   KDF params            (varies by algo; Argon2id = 9)
///   offset N   salt                  (32)
/// ```
/// Verification: `credentials.verify` contains AES-256-GCM encrypted known
/// plaintext, validated on unlock to detect wrong passwords without needing
/// to decrypt the full credential store. Its on-disk layout is unchanged.
///
/// **Legacy PBKDF2 format** (old `credentials.salt`) is no longer readable —
/// this is a force-breaking migration. [hasLegacyFormat] lets the app detect
/// it and prompt the user to reset credentials or exit.
class MasterPasswordManager {
  /// New Argon2id salt file.
  static const _kdfFileName = 'credentials.kdf';

  /// Legacy PBKDF2 raw-salt file — detected but no longer decrypted.
  static const _legacySaltFileName = 'credentials.salt';

  static const _verifierFileName = 'credentials.verify';
  static const _keyFileName = 'credentials.key';
  static const _fileMagic = <int>[0x4C, 0x46, 0x4B, 0x44]; // 'LFKD'
  static const _fileVersion = 0x01;
  static const _headerBaseLen = 6; // magic(4) + version(1) + algoId(1)
  static const _saltLength = 32;
  static const _keyLength = 32;
  static const _ivLength = 12;

  /// The Argon2id profile used for fresh enable/changePassword calls.
  /// Tests may lower it via [debugSetKdfParams] so enable/verify cycles
  /// don't spend seconds each, stretching the full suite into minutes.
  static KdfParams _defaultParams = KdfParams.productionDefaults;

  /// Lower KDF cost for tests. Restores to production defaults when
  /// called with null. NEVER call from production code.
  static void debugSetKdfParams(KdfParams? params) {
    _defaultParams = params ?? KdfParams.productionDefaults;
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

  /// Whether master password protection is enabled — either the new
  /// Argon2id KDF file or the legacy PBKDF2 salt exists. Callers that
  /// must differentiate should also check [hasLegacyFormat].
  Future<bool> isEnabled() async {
    final basePath = await _getBasePath();
    if (await File('$basePath/$_kdfFileName').exists()) return true;
    if (await File('$basePath/$_legacySaltFileName').exists()) return true;
    return false;
  }

  /// True when the install still carries the legacy PBKDF2 `credentials.salt`
  /// file and no migrated `credentials.kdf`. The startup flow shows a
  /// reset-or-exit dialog in this case.
  Future<bool> hasLegacyFormat() async {
    final basePath = await _getBasePath();
    final hasNew = await File('$basePath/$_kdfFileName').exists();
    if (hasNew) return false;
    return File('$basePath/$_legacySaltFileName').exists();
  }

  /// Derive a 256-bit key from password using the on-disk KDF params.
  ///
  /// Runs in an isolate because Argon2id is CPU + memory heavy
  /// (400-1500ms wall-clock at the production profile).
  Future<Uint8List> deriveKey(String password) async {
    final record = await _readKdfRecord();
    return Isolate.run(
      () => _deriveKeySync(password, record.salt, record.params),
    );
  }

  /// Verify a password against the stored verifier.
  ///
  /// Returns true if the password is correct.
  ///
  /// Prefer [verifyAndDerive] when the caller will immediately need the
  /// derived key — that variant runs the KDF once instead of twice.
  Future<bool> verify(String password) async {
    final derived = await verifyAndDerive(password);
    return derived != null;
  }

  /// Single-KDF unlock: verify the password and, on success, return the
  /// derived DB key; return null on wrong password.
  ///
  /// The legacy unlock path called [verify] and then [deriveKey] back to
  /// back — two isolate spawns + two KDF runs for each unlock. This
  /// combined variant runs the KDF once inside a single isolate and
  /// returns the same bytes the verifier was checked against.
  Future<Uint8List?> verifyAndDerive(String password) async {
    final record = await _readKdfRecord();
    final basePath = await _getBasePath();
    final verifierFile = File('$basePath/$_verifierFileName');
    if (!await verifierFile.exists()) {
      throw const MasterPasswordException('Master password is not enabled');
    }
    final verifierData = await verifierFile.readAsBytes();
    final params = record.params;
    final salt = record.salt;

    return Isolate.run(() {
      final key = _deriveKeySync(password, salt, params);
      if (!_verifySync(key, verifierData)) return null;
      return key;
    });
  }

  /// Enable master password protection.
  ///
  /// 1. Generates random salt
  /// 2. Derives key with the production Argon2id profile
  /// 3. Writes `credentials.kdf` (magic + version + algo + params + salt)
  ///    and `credentials.verify` atomically
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

    final params = _defaultParams;
    final key = await Isolate.run(() => _deriveKeySync(password, salt, params));

    final verifierData = _encryptVerifier(key);
    final kdfFileBytes = _encodeKdfRecord(params, salt);

    await writeBytesAtomic('$basePath/$_kdfFileName', kdfFileBytes);
    await writeBytesAtomic('$basePath/$_verifierFileName', verifierData);

    AppLogger.instance.log(
      'Master password enabled (Argon2id)',
      name: 'MasterPassword',
    );
    return key;
  }

  /// Change master password.
  ///
  /// 1. Verify old password
  /// 2. Generate new salt + derive new key with the current default params
  /// 3. Update verifier + `credentials.kdf`
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

    final params = _defaultParams;
    final newKey = await Isolate.run(
      () => _deriveKeySync(newPassword, newSalt, params),
    );

    final verifierData = _encryptVerifier(newKey);
    final kdfFileBytes = _encodeKdfRecord(params, newSalt);

    await writeBytesAtomic('$basePath/$_kdfFileName', kdfFileBytes);
    await writeBytesAtomic('$basePath/$_verifierFileName', verifierData);

    AppLogger.instance.log(
      'Master password changed (Argon2id)',
      name: 'MasterPassword',
    );
    return newKey;
  }

  /// Disable master password protection.
  ///
  /// Deletes salt and verifier files (both legacy and new paths). The
  /// caller is responsible for re-encrypting stores with a new random key
  /// and saving it to `credentials.key`.
  Future<void> disable() async {
    final basePath = await _getBasePath();
    for (final name in [_kdfFileName, _legacySaltFileName, _verifierFileName]) {
      final f = File('$basePath/$name');
      if (await f.exists()) await f.delete();
    }
    AppLogger.instance.log('Master password disabled', name: 'MasterPassword');
  }

  /// Reset all encrypted data (used when password is forgotten or when the
  /// legacy PBKDF2 format is detected on a force-breaking upgrade).
  ///
  /// Deletes KDF salt (both formats), verifier, key, and all encrypted
  /// store files. This is destructive — all saved passwords and keys are
  /// lost.
  Future<void> reset() async {
    final basePath = await _getBasePath();
    final files = [
      '$basePath/$_kdfFileName',
      '$basePath/$_legacySaltFileName',
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

  // ── Encoding ─────────────────────────────────────────────────────

  static Uint8List _encodeKdfRecord(KdfParams params, Uint8List salt) {
    if (salt.length != _saltLength) {
      throw ArgumentError.value(salt.length, 'salt.length', 'must be 32');
    }
    final paramsBytes = params.encode();
    final out = Uint8List(_headerBaseLen + paramsBytes.length + salt.length);
    var offset = 0;
    out.setRange(offset, offset + _fileMagic.length, _fileMagic);
    offset += _fileMagic.length;
    out[offset++] = _fileVersion;
    // params[0] is the algorithm id — the header's algo field mirrors it
    // so a reader can skip ahead without fully parsing params.
    out[offset++] = paramsBytes[0];
    out.setRange(offset, offset + paramsBytes.length, paramsBytes);
    offset += paramsBytes.length;
    out.setRange(offset, offset + salt.length, salt);
    return out;
  }

  Future<_KdfRecord> _readKdfRecord() async {
    final basePath = await _getBasePath();
    final kdfFile = File('$basePath/$_kdfFileName');
    if (!await kdfFile.exists()) {
      if (await File('$basePath/$_legacySaltFileName').exists()) {
        throw const MasterPasswordException(
          'Legacy PBKDF2 format detected. Reset credentials to continue.',
        );
      }
      throw const MasterPasswordException('Master password is not enabled');
    }
    final bytes = await kdfFile.readAsBytes();
    return _decodeKdfRecord(bytes);
  }

  /// Decode a `credentials.kdf` record. Exposed for tests.
  static _KdfRecord _decodeKdfRecord(Uint8List bytes) {
    if (bytes.length < _headerBaseLen + 1 + _saltLength) {
      throw const FormatException('credentials.kdf: truncated header');
    }
    for (var i = 0; i < _fileMagic.length; i++) {
      if (bytes[i] != _fileMagic[i]) {
        throw const FormatException('credentials.kdf: bad magic');
      }
    }
    final version = bytes[_fileMagic.length];
    if (version != _fileVersion) {
      throw FormatException(
        'credentials.kdf: unsupported version 0x'
        '${version.toRadixString(16).padLeft(2, '0')}',
      );
    }
    // Params block starts at headerBaseLen; its first byte is the
    // algorithm id, which must also match the header's id byte for
    // consistency.
    const paramsStart = _headerBaseLen;
    final params = KdfParams.decode(Uint8List.sublistView(bytes, paramsStart));
    final saltStart = paramsStart + params.encodedLength;
    if (bytes.length < saltStart + _saltLength) {
      throw const FormatException('credentials.kdf: truncated salt');
    }
    final salt = Uint8List.fromList(
      bytes.sublist(saltStart, saltStart + _saltLength),
    );
    return _KdfRecord(params: params, salt: salt);
  }

  // ── Static helpers (run in isolate) ──────────────────────────────

  static Uint8List _deriveKeySync(
    String password,
    Uint8List salt,
    KdfParams params,
  ) {
    switch (params.algorithm) {
      case KdfAlgorithm.argon2id:
        final argon2Params = Argon2Parameters(
          Argon2Parameters.ARGON2_id,
          salt,
          desiredKeyLength: _keyLength,
          iterations: params.iterations,
          memory: params.memoryKiB,
          lanes: params.parallelism,
          version: Argon2Parameters.ARGON2_VERSION_13,
        );
        final generator = Argon2BytesGenerator()..init(argon2Params);
        final out = Uint8List(_keyLength);
        generator.deriveKey(
          Uint8List.fromList(utf8.encode(password)),
          0,
          out,
          0,
        );
        return out;
    }
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

/// KDF salt file record — parsed form of `credentials.kdf`.
class _KdfRecord {
  final KdfParams params;
  final Uint8List salt;
  const _KdfRecord({required this.params, required this.salt});
}

/// Thrown when master password operations fail.
class MasterPasswordException implements Exception {
  final String message;

  const MasterPasswordException(this.message);

  @override
  String toString() => 'MasterPasswordException: $message';
}
