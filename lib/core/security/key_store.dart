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

/// Encrypted key store — file-based AES-256-GCM.
///
/// Stores SSH keys in `keys.enc`, encrypted with the same key as
/// [CredentialStore] (`credentials.key`).
class KeyStore {
  static const _keysFileName = 'keys.enc';
  static const _keyFileName = 'credentials.key';
  static const _keyLength = 32;
  static const _minEncryptedLength = 13;

  String? _basePath;
  Map<String, SshKeyEntry>? _cache;

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
    final keysFile = File('$basePath/$_keysFileName');
    final keyFile = File('$basePath/$_keyFileName');

    if (!await keysFile.exists() || !await keyFile.exists()) {
      return {};
    }

    try {
      final keyBytes = await keyFile.readAsBytes();
      if (keyBytes.length != _keyLength) {
        throw KeyStoreException(
          'Invalid key length: ${keyBytes.length} bytes (expected $_keyLength)',
        );
      }
      final encData = await keysFile.readAsBytes();
      final json = _decrypt(encData, keyBytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      final result = map.map(
        (k, v) => MapEntry(k, SshKeyEntry.fromJson(v as Map<String, dynamic>)),
      );
      _cache = result;
      return Map.of(result);
    } catch (e) {
      AppLogger.instance.log('Failed to load keys: $e', name: 'KeyStore');
      if (e is KeyStoreException) rethrow;
      throw KeyStoreException(
        'Failed to decrypt keys. Key file may be corrupted.',
        cause: e,
      );
    }
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
    final keysFile = File('$basePath/$_keysFileName');
    final keyFile = File('$basePath/$_keyFileName');

    final keyBytes = await _loadKey(keyFile);
    final json = jsonEncode(keys.map((k, v) => MapEntry(k, v.toJson())));
    final encData = _encrypt(json, keyBytes);
    await writeBytesAtomic(keysFile.path, encData);
    _cache = Map.of(keys);
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

  // ── AES-256-GCM encryption (same as CredentialStore) ─────────────

  Future<Uint8List> _loadKey(File keyFile) async {
    if (!await keyFile.exists()) {
      throw const KeyStoreException(
        'Encryption key file not found. Save a session first to create it.',
      );
    }
    final bytes = await keyFile.readAsBytes();
    if (bytes.length != _keyLength) {
      throw KeyStoreException(
        'Invalid key length: ${bytes.length} bytes (expected $_keyLength)',
      );
    }
    return bytes;
  }

  Uint8List _encrypt(String plaintext, Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(12, (_) => random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);
    return Uint8List.fromList([...iv, ...output]);
  }

  String _decrypt(Uint8List data, Uint8List key) {
    if (data.length < _minEncryptedLength) {
      throw KeyStoreException(
        'Encrypted data too short (${data.length} bytes) — file is corrupted',
      );
    }
    final iv = data.sublist(0, 12);
    final ciphertext = data.sublist(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final output = cipher.process(ciphertext);
    return utf8.decode(output);
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
