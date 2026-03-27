import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Encrypted credential store — file-based AES-256-GCM.
///
/// Stores secrets (passwords, PEM keys, passphrases) in an encrypted JSON file
/// separate from the plaintext session data. Uses a machine-local key derived
/// from a random salt stored alongside.
class CredentialStore {
  static const _credFileName = 'credentials.enc';
  static const _keyFileName = 'credentials.key';

  String? _basePath;

  /// Guards concurrent key generation to prevent race conditions.
  Completer<Uint8List>? _keyGenCompleter;

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Load all credentials. Returns map of sessionId → CredentialData.
  ///
  /// Throws [CredentialStoreException] if decryption fails (corrupted key/data).
  /// Returns empty map only when no credential files exist yet.
  Future<Map<String, CredentialData>> loadAll() async {
    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');
    final keyFile = File('$basePath/$_keyFileName');

    if (!await credFile.exists() || !await keyFile.exists()) {
      return {};
    }

    try {
      final keyBytes = await keyFile.readAsBytes();
      final encData = await credFile.readAsBytes();
      final json = _decrypt(encData, keyBytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, CredentialData.fromJson(v as Map<String, dynamic>)));
    } catch (e) {
      AppLogger.instance.log('Failed to load credentials: $e', name: 'CredentialStore');
      throw CredentialStoreException(
        'Failed to decrypt credentials. Key file may be corrupted.',
        cause: e,
      );
    }
  }

  /// Load all credentials, returning empty map on any error.
  ///
  /// Use [loadAll] when you need to distinguish between "no credentials"
  /// and "decryption failed". This method is for non-critical reads.
  Future<Map<String, CredentialData>> loadAllSafe() async {
    try {
      return await loadAll();
    } on CredentialStoreException {
      return {};
    }
  }

  /// Save all credentials.
  Future<void> saveAll(Map<String, CredentialData> credentials) async {
    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');
    final keyFile = File('$basePath/$_keyFileName');

    // Load or generate key with guard against concurrent generation
    final keyBytes = await _loadOrGenerateKey(keyFile);

    final json = jsonEncode(
      credentials.map((k, v) => MapEntry(k, v.toJson())),
    );
    final encData = _encrypt(json, keyBytes);
    await writeBytesAtomic(credFile.path, encData);
  }

  /// Load existing key or generate a new one with concurrency guard.
  Future<Uint8List> _loadOrGenerateKey(File keyFile) async {
    if (await keyFile.exists()) {
      return await keyFile.readAsBytes();
    }

    // Guard against concurrent key generation using Completer
    final existing = _keyGenCompleter;
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<Uint8List>();
    _keyGenCompleter = completer;
    try {
      // Double-check after acquiring guard
      if (await keyFile.exists()) {
        final bytes = await keyFile.readAsBytes();
        completer.complete(bytes);
        return bytes;
      }
      final keyBytes = _generateKey();
      await writeBytesAtomic(keyFile.path, keyBytes);
      completer.complete(keyBytes);
      return keyBytes;
    } catch (e) {
      completer.completeError(e);
      // Prevent unhandled error when no concurrent caller awaits the completer.
      unawaited(completer.future.then<void>((_) {}, onError: (_) {}));
      rethrow;
    } finally {
      _keyGenCompleter = null;
    }
  }

  /// Get credentials for a session.
  Future<CredentialData?> get(String sessionId) async {
    final all = await loadAll();
    return all[sessionId];
  }

  /// Set credentials for a session.
  Future<void> set(String sessionId, CredentialData data) async {
    final all = await loadAll();
    all[sessionId] = data;
    await saveAll(all);
  }

  /// Delete credentials for a session.
  ///
  /// Uses [loadAllSafe] to avoid failing when the credential file is
  /// corrupted — deleting a session should never be blocked by a
  /// decryption error.
  Future<void> delete(String sessionId) async {
    final all = await loadAllSafe();
    all.remove(sessionId);
    await saveAll(all);
  }

  Uint8List _generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
  }

  Uint8List _encrypt(String plaintext, Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(12, (_) => random.nextInt(256)),
    );

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);

    // Format: [iv (12)] [ciphertext+tag]
    return Uint8List.fromList([...iv, ...output]);
  }

  String _decrypt(Uint8List data, Uint8List key) {
    final iv = data.sublist(0, 12);
    final ciphertext = data.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );

    final output = cipher.process(ciphertext);
    return utf8.decode(output);
  }
}

/// Credential data for a single session.
class CredentialData {
  final String password;
  final String keyData;
  final String passphrase;

  const CredentialData({
    this.password = '',
    this.keyData = '',
    this.passphrase = '',
  });

  bool get isEmpty => password.isEmpty && keyData.isEmpty && passphrase.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CredentialData &&
          password == other.password &&
          keyData == other.keyData &&
          passphrase == other.passphrase;

  @override
  int get hashCode => Object.hash(password, keyData, passphrase);

  Map<String, dynamic> toJson() => {
    'password': password,
    'key_data': keyData,
    'passphrase': passphrase,
  };

  factory CredentialData.fromJson(Map<String, dynamic> json) {
    return CredentialData(
      password: json['password'] as String? ?? '',
      keyData: json['key_data'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
    );
  }
}

/// Thrown when credential store operations fail (decryption, corrupted key).
class CredentialStoreException implements Exception {
  final String message;
  final Object? cause;

  const CredentialStoreException(this.message, {this.cause});

  @override
  String toString() => 'CredentialStoreException: $message';
}
