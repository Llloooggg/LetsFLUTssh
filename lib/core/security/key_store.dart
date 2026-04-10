import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import 'aes_gcm.dart';
import 'security_level.dart';

/// Supported SSH key types for generation.
enum SshKeyType {
  ed25519('Ed25519'),
  rsa2048('RSA 2048'),
  rsa4096('RSA 4096');

  const SshKeyType(this.label);
  final String label;
}

/// An SSH key entry stored in the key manager.
class SshKeyEntry {
  final String id;
  final String label;
  final String privateKey;
  final String publicKey;
  final String keyType;
  final DateTime createdAt;
  final bool isGenerated;

  const SshKeyEntry({
    required this.id,
    required this.label,
    required this.privateKey,
    required this.publicKey,
    required this.keyType,
    required this.createdAt,
    this.isGenerated = false,
  });

  SshKeyEntry copyWith({String? label}) => SshKeyEntry(
    id: id,
    label: label ?? this.label,
    privateKey: privateKey,
    publicKey: publicKey,
    keyType: keyType,
    createdAt: createdAt,
    isGenerated: isGenerated,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'private_key': privateKey,
    'public_key': publicKey,
    'key_type': keyType,
    'created_at': createdAt.toIso8601String(),
    'is_generated': isGenerated,
  };

  factory SshKeyEntry.fromJson(Map<String, dynamic> json) => SshKeyEntry(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    privateKey: json['private_key'] as String? ?? '',
    publicKey: json['public_key'] as String? ?? '',
    keyType: json['key_type'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    isGenerated: json['is_generated'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshKeyEntry &&
          id == other.id &&
          label == other.label &&
          privateKey == other.privateKey;

  @override
  int get hashCode => Object.hash(id, label, privateKey);
}

/// SSH key store with three-level security.
///
/// - [SecurityLevel.plaintext]: `keys.json` in cleartext.
/// - [SecurityLevel.keychain] / [SecurityLevel.masterPassword]: `keys.enc`
///   encrypted with AES-256-GCM.
class KeyStore {
  static const _jsonFileName = 'keys.json';
  static const _encFileName = 'keys.enc';

  String? _basePath;
  Map<String, SshKeyEntry>? _cache;

  SecurityLevel _level;
  Uint8List? _encryptionKey;

  KeyStore({SecurityLevel level = SecurityLevel.plaintext}) : _level = level;

  /// Current security level.
  SecurityLevel get securityLevel => _level;

  /// Set the encryption key (from keychain or master password).
  void setEncryptionKey(Uint8List key, SecurityLevel level) {
    _encryptionKey = key;
    _level = level;
    _cache = null;
  }

  /// Clear the encryption key (revert to plaintext).
  void clearEncryptionKey() {
    _encryptionKey = null;
    _level = SecurityLevel.plaintext;
    _cache = null;
  }

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Load all stored keys.
  Future<Map<String, SshKeyEntry>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);

    final basePath = await _getBasePath();

    if (_encryptionKey != null) {
      // Encrypted mode.
      final encFile = File('$basePath/$_encFileName');
      if (!await encFile.exists()) return {};
      try {
        final encData = await encFile.readAsBytes();
        final json = AesGcm.decrypt(encData, _encryptionKey!);
        return _parseAndCache(json);
      } catch (e) {
        AppLogger.instance.log('Failed to load keys: $e', name: 'KeyStore');
        if (e is KeyStoreException) rethrow;
        throw KeyStoreException(
          'Failed to decrypt keys. Key may be incorrect.',
          cause: e,
        );
      }
    } else {
      // Plaintext mode.
      final jsonFile = File('$basePath/$_jsonFileName');
      if (!await jsonFile.exists()) return {};
      try {
        final json = await jsonFile.readAsString();
        return _parseAndCache(json);
      } catch (e) {
        AppLogger.instance.log('Failed to load keys: $e', name: 'KeyStore');
        throw KeyStoreException('Failed to parse keys file.', cause: e);
      }
    }
  }

  Map<String, SshKeyEntry> _parseAndCache(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final result = map.map(
      (k, v) => MapEntry(k, SshKeyEntry.fromJson(v as Map<String, dynamic>)),
    );
    _cache = result;
    return Map.of(result);
  }

  /// Load all keys, returning empty map on any error.
  Future<Map<String, SshKeyEntry>> loadAllSafe() async {
    try {
      return await loadAll();
    } on KeyStoreException catch (e) {
      AppLogger.instance.log(
        'loadAllSafe: returning empty map — $e',
        name: 'KeyStore',
      );
      return {};
    }
  }

  /// Save all keys.
  Future<void> saveAll(Map<String, SshKeyEntry> keys) async {
    final basePath = await _getBasePath();
    final json = jsonEncode(keys.map((k, v) => MapEntry(k, v.toJson())));

    if (_encryptionKey != null) {
      final encData = AesGcm.encrypt(json, _encryptionKey!);
      await writeBytesAtomic('$basePath/$_encFileName', encData);
    } else {
      await writeFileAtomic(
        '$basePath/$_jsonFileName',
        const JsonEncoder.withIndent(
          '  ',
        ).convert(keys.map((k, v) => MapEntry(k, v.toJson()))),
      );
    }
    _cache = Map.of(keys);
  }

  /// Re-encrypt all data with a new key and security level.
  Future<void> reEncrypt(Uint8List? newKey, SecurityLevel newLevel) async {
    final basePath = await _getBasePath();
    final data = await loadAllSafe();

    _encryptionKey = newKey;
    _level = newLevel;
    _cache = null;
    await saveAll(data);

    // Clean up opposite format file.
    if (newKey != null) {
      final jsonFile = File('$basePath/$_jsonFileName');
      if (await jsonFile.exists()) await jsonFile.delete();
    } else {
      final encFile = File('$basePath/$_encFileName');
      if (await encFile.exists()) await encFile.delete();
    }
  }

  /// Get a single key entry.
  Future<SshKeyEntry?> get(String id) async {
    final all = await loadAll();
    return all[id];
  }

  /// Add or update a key entry.
  Future<void> save(SshKeyEntry entry) async {
    final all = await loadAllSafe();
    all[entry.id] = entry;
    await saveAll(all);
  }

  /// Delete a key entry.
  Future<void> delete(String id) async {
    final all = await loadAllSafe();
    all.remove(id);
    await saveAll(all);
  }

  /// Import a key from PEM text. Returns the created entry.
  SshKeyEntry importKey(String pem, String label) {
    final pairs = SSHKeyPair.fromPem(pem);
    if (pairs.isEmpty) {
      throw const KeyStoreException('No valid key found in PEM data');
    }
    final pair = pairs.first;
    final publicKey = _publicKeyToOpenSSH(pair, label);

    return SshKeyEntry(
      id: const Uuid().v4(),
      label: label,
      privateKey: pair.toPem(),
      publicKey: publicKey,
      keyType: pair.type,
      createdAt: DateTime.now(),
    );
  }

  /// Generate a new SSH key pair. Runs synchronously (fast for Ed25519,
  /// slow for RSA — caller should run in isolate for RSA).
  static SshKeyEntry generateKeyPair(SshKeyType type, String label) {
    final SSHKeyPair pair;
    switch (type) {
      case SshKeyType.ed25519:
        pair = _generateEd25519(label);
      case SshKeyType.rsa2048:
        pair = _generateRsa(2048, label);
      case SshKeyType.rsa4096:
        pair = _generateRsa(4096, label);
    }

    return SshKeyEntry(
      id: const Uuid().v4(),
      label: label,
      privateKey: pair.toPem(),
      publicKey: _publicKeyToOpenSSH(pair, label),
      keyType: pair.type,
      createdAt: DateTime.now(),
      isGenerated: true,
    );
  }

  static SSHKeyPair _generateEd25519(String comment) {
    final signingKey = ed25519.SigningKey.generate();
    final publicKeyBytes = Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final privateKeyBytes = Uint8List.fromList(signingKey.asTypedList);
    return OpenSSHEd25519KeyPair(publicKeyBytes, privateKeyBytes, comment);
  }

  static SSHKeyPair _generateRsa(int bitStrength, String comment) {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), bitStrength, 64),
          secureRandom,
        ),
      );

    final pair = keyGen.generateKeyPair();
    final pub = pair.publicKey;
    final priv = pair.privateKey;

    final iqmp = priv.q!.modInverse(priv.p!);

    return OpenSSHRsaKeyPair(
      pub.modulus!,
      pub.publicExponent!,
      priv.privateExponent!,
      iqmp,
      priv.p!,
      priv.q!,
      comment,
    );
  }

  /// Format public key in OpenSSH authorized_keys format.
  static String _publicKeyToOpenSSH(SSHKeyPair pair, String comment) {
    final hostKey = pair.toPublicKey();
    final encoded = base64Encode(hostKey.encode());
    return '${pair.type} $encoded $comment';
  }
}

/// Thrown when key store operations fail.
class KeyStoreException implements Exception {
  final String message;
  final Object? cause;

  const KeyStoreException(this.message, {this.cause});

  @override
  String toString() => 'KeyStoreException: $message';
}
