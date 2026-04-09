import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'aes_gcm.dart';

/// Encrypted credential store — file-based AES-256-GCM.
///
/// Stores secrets (passwords, PEM keys, passphrases) in an encrypted JSON file
/// separate from the plaintext session data. Uses a machine-local key derived
/// from a random salt stored alongside.
class CredentialStore {
  static const _credFileName = 'credentials.enc';
  static const _keyFileName = 'credentials.key';

  /// AES-256 key length in bytes.
  static const keyLength = 32;

  String? _basePath;

  /// In-memory credential cache. Populated on first [loadAll], invalidated
  /// on [saveAll]. Avoids re-reading + re-decrypting on every [get]/[set].
  Map<String, CredentialData>? _cache;

  /// Guards concurrent key generation to prevent race conditions.
  Completer<Uint8List>? _keyGenCompleter;

  /// External key injected by master password flow.
  ///
  /// When set, this key is used instead of reading `credentials.key`.
  /// Set via [setExternalKey], cleared via [clearExternalKey].
  Uint8List? _externalKey;

  /// Set the encryption key externally (master password derived key).
  ///
  /// Clears the in-memory cache so data is re-decrypted with the new key.
  void setExternalKey(Uint8List key) {
    _externalKey = key;
    _cache = null;
  }

  /// Clear the external key, reverting to file-based key.
  void clearExternalKey() {
    _externalKey = null;
    _cache = null;
  }

  /// Whether the store is locked (master password enabled but no key provided).
  ///
  /// When locked, [loadAll] will throw — the caller must provide the key
  /// via [setExternalKey] first.
  Future<bool> get isLocked async {
    final basePath = await _getBasePath();
    final saltExists = await File('$basePath/credentials.salt').exists();
    return saltExists && _externalKey == null;
  }

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
  ///
  /// Results are cached in memory — subsequent calls return the cached copy
  /// until [saveAll] updates it.
  Future<Map<String, CredentialData>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);

    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');

    if (!await credFile.exists()) return {};

    // When no external key is set, the file-based key must exist.
    if (_externalKey == null &&
        !await File('$basePath/$_keyFileName').exists()) {
      return {};
    }

    // Resolve encryption key
    final keyBytes = await _resolveKey(basePath);

    try {
      final encData = await credFile.readAsBytes();
      final json = AesGcm.decrypt(encData, keyBytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final result = map.map(
        (k, v) =>
            MapEntry(k, CredentialData.fromJson(v as Map<String, dynamic>)),
      );
      _cache = result;
      return Map.of(result);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load credentials: $e',
        name: 'CredentialStore',
      );
      if (e is CredentialStoreException) rethrow;
      throw CredentialStoreException(
        'Failed to decrypt credentials. Key file may be corrupted.',
        cause: e,
      );
    }
  }

  /// Load all credentials, returning empty map on any error.
  ///
  /// Use [loadAll] when you need to distinguish between "no credentials"
  /// and "decryption failed". This method is for non-critical reads
  /// (e.g. delete, export preview).
  Future<Map<String, CredentialData>> loadAllSafe() async {
    try {
      return await loadAll();
    } on CredentialStoreException catch (e) {
      AppLogger.instance.log(
        'loadAllSafe: returning empty map due to decryption error — $e',
        name: 'CredentialStore',
      );
      return {};
    }
  }

  /// Save all credentials and update the in-memory cache.
  Future<void> saveAll(Map<String, CredentialData> credentials) async {
    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');

    // Resolve encryption key (external or file-based)
    final keyBytes = await _resolveKey(basePath);

    final json = jsonEncode(credentials.map((k, v) => MapEntry(k, v.toJson())));
    final encData = AesGcm.encrypt(json, keyBytes);
    await writeBytesAtomic(credFile.path, encData);
    _cache = Map.of(credentials);
  }

  /// Resolve the encryption key: external key if set, otherwise from file.
  Future<Uint8List> _resolveKey(String basePath) async {
    if (_externalKey != null) return _externalKey!;
    final keyFile = File('$basePath/$_keyFileName');
    return _loadOrGenerateKey(keyFile);
  }

  /// Load existing key or generate a new one with concurrency guard.
  ///
  /// Validates that an existing key is exactly [keyLength] bytes.
  Future<Uint8List> _loadOrGenerateKey(File keyFile) async {
    if (await keyFile.exists()) {
      final bytes = await keyFile.readAsBytes();
      if (bytes.length != keyLength) {
        throw CredentialStoreException(
          'Invalid key length: ${bytes.length} bytes (expected $keyLength)',
        );
      }
      return bytes;
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
  ///
  /// Uses [loadAllSafe] so that a corrupted credential file does not block
  /// saving new credentials.
  Future<void> set(String sessionId, CredentialData data) async {
    final all = await loadAllSafe();
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

  Uint8List _generateKey() => AesGcm.generateKey();
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
