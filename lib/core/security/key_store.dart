import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../db/database.dart';

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

/// SSH key store backed by drift database.
///
/// Keeps the same public API as the old file-based store. Call [setDatabase]
/// before [loadAll] — without a database, reads return empty and writes are
/// no-ops.
class KeyStore {
  AppDatabase? _db;
  Map<String, SshKeyEntry>? _cache;

  /// Inject the opened database. Replaces the old `setEncryptionKey()`.
  void setDatabase(AppDatabase db) {
    _db = db;
    _cache = null;
  }

  /// Load all stored keys.
  Future<Map<String, SshKeyEntry>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);
    final db = _db;
    if (db == null) return {};

    try {
      final dbKeys = await db.sshKeyDao.getAll();
      final result = <String, SshKeyEntry>{};
      for (final k in dbKeys) {
        result[k.id] = SshKeyEntry(
          id: k.id,
          label: k.label,
          privateKey: k.privateKey,
          publicKey: k.publicKey,
          keyType: k.keyType,
          createdAt: k.createdAt,
          isGenerated: k.isGenerated,
        );
      }
      _cache = result;
      return Map.of(result);
    } catch (e) {
      AppLogger.instance.log('Failed to load keys', name: 'KeyStore', error: e);
      throw KeyStoreException('Failed to load keys.', cause: e);
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

  /// Save all keys (replaces entire store).
  Future<void> saveAll(Map<String, SshKeyEntry> keys) async {
    final db = _db;
    if (db == null) return;

    // Delete all existing, then re-insert
    final existing = await db.sshKeyDao.getAll();
    for (final k in existing) {
      await db.sshKeyDao.deleteById(k.id);
    }
    for (final entry in keys.values) {
      await db.sshKeyDao.insert(_toCompanion(entry));
    }
    _cache = Map.of(keys);
  }

  /// Get a single key entry.
  Future<SshKeyEntry?> get(String id) async {
    final all = await loadAll();
    return all[id];
  }

  /// Add or update a key entry.
  Future<void> save(SshKeyEntry entry) async {
    final db = _db;
    if (db == null) return;

    final existing = await db.sshKeyDao.getById(entry.id);
    if (existing != null) {
      await db.sshKeyDao.update(_toCompanion(entry));
    } else {
      await db.sshKeyDao.insert(_toCompanion(entry));
    }
    _cache?[entry.id] = entry;
  }

  /// Delete a key entry.
  Future<void> delete(String id) async {
    await _db?.sshKeyDao.deleteById(id);
    _cache?.remove(id);
  }

  /// Find the id of a stored key whose material matches [entry].
  /// Returns null if no match.
  ///
  /// Prefers the public-key fingerprint — public key bytes never leave
  /// the secure store via this path, so dedup runs without pulling
  /// private material through an isolate just to hash it. Falls back to
  /// the private-key fingerprint only when [entry.publicKey] is empty
  /// (a rare path for keys imported without an extracted public half).
  Future<String?> findIdByKeyMaterial(SshKeyEntry entry) async {
    final all = await loadAll();
    final publicTarget = publicKeyFingerprint(entry.publicKey);
    if (publicTarget.isNotEmpty) {
      for (final stored in all.values) {
        if (publicKeyFingerprint(stored.publicKey) == publicTarget) {
          return stored.id;
        }
      }
      return null;
    }
    final privateTarget = privateKeyFingerprint(entry.privateKey);
    if (privateTarget.isEmpty) return null;
    for (final stored in all.values) {
      if (privateKeyFingerprint(stored.privateKey) == privateTarget) {
        return stored.id;
      }
    }
    return null;
  }

  /// Import a key from another source (QR/.lfs), deduplicating by content.
  ///
  /// - If a stored key has the same public-key fingerprint (or private-
  ///   key fingerprint as fallback), returns its id without writing
  ///   anything — no duplicates.
  /// - Otherwise, inserts a new entry. The id is replaced with a fresh
  ///   UUID to avoid colliding with an unrelated stored key that
  ///   happens to share the imported id. If the label already exists, a
  ///   "(copy)"/"(copy N)" suffix is appended — mirrors session
  ///   duplication semantics.
  Future<String> importForMerge(SshKeyEntry entry) async {
    final all = await loadAll();
    final existingId = await findIdByKeyMaterial(entry);
    if (existingId != null) return existingId;

    final labels = all.values.map((e) => e.label).toSet();
    final takenIds = all.keys.toSet();
    final newLabel = _uniqueLabel(entry.label, labels);
    final newId = takenIds.contains(entry.id) ? const Uuid().v4() : entry.id;

    final deduped = SshKeyEntry(
      id: newId,
      label: newLabel,
      privateKey: entry.privateKey,
      publicKey: entry.publicKey,
      keyType: entry.keyType,
      createdAt: entry.createdAt,
      isGenerated: entry.isGenerated,
    );
    await save(deduped);
    return newId;
  }

  static String _uniqueLabel(String base, Set<String> taken) {
    if (base.isEmpty || !taken.contains(base)) return base;
    final copy = '$base (copy)';
    if (!taken.contains(copy)) return copy;
    var n = 2;
    while (taken.contains('$base (copy $n)')) {
      n++;
    }
    return '$base (copy $n)';
  }

  /// SHA-256 hex of a normalized public key (OpenSSH single-line form).
  /// Used as a content-addressable id for deduplicating imported manager
  /// keys without running the hash over private material.
  ///
  /// Public keys are normalized by trimming surrounding whitespace and
  /// collapsing CRLF — the key-type prefix and base64 body are stable
  /// enough that this matches OpenSSH's own dedup behaviour.
  static String publicKeyFingerprint(String publicKey) {
    final normalized = publicKey.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return '';
    return _sha256Hex(utf8.encode(normalized));
  }

  /// SHA-256 hex of a normalized private key PEM. Retained only as a
  /// fallback for entries that lack an extracted public half. Prefer
  /// [publicKeyFingerprint] everywhere else.
  static String privateKeyFingerprint(String privateKey) {
    final normalized = privateKey.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return '';
    return _sha256Hex(utf8.encode(normalized));
  }

  static String _sha256Hex(List<int> bytes) {
    final digest = SHA256Digest();
    final out = digest.process(Uint8List.fromList(bytes));
    final buf = StringBuffer();
    for (final b in out) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
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

  // ── Internals ───────────────────────────────────────────────────

  static SshKeysCompanion _toCompanion(SshKeyEntry e) =>
      SshKeysCompanion.insert(
        id: e.id,
        label: e.label,
        privateKey: e.privateKey,
        publicKey: e.publicKey,
        keyType: e.keyType,
        createdAt: e.createdAt,
      );

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
