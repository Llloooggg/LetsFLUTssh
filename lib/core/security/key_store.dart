import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/db.dart' as rust_db;
import '../../src/rust/api/keys.dart' as rust_keys;
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

/// SSH key store backed by `lfs_core.db`. Row reads / writes route
/// through the FRB DAO; the in-memory cache shape is unchanged.
///
/// The unit-test runner does not load the FRB native lib — every
/// FRB call site catches its synchronous `RustLib.instance` throw
/// and degrades to the same empty-cache / no-op surface drift's
/// `_db == null` branch used to expose. Live coverage moves to
/// integration_test.
class KeyStore {
  Map<String, SshKeyEntry>? _cache;

  /// Drop the in-memory cache. Called from the unlock handshake so
  /// the next read pulls fresh rows after the DB switches behind us.
  /// (Replaces the old `setDatabase` injection.)
  void invalidateCache() {
    _cache = null;
  }

  static SshKeyEntry _fromRow(rust_db.DbSshKey r) => SshKeyEntry(
    id: r.id,
    label: r.label,
    privateKey: r.privateKey,
    publicKey: r.publicKey,
    keyType: r.keyType,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
    isGenerated: r.isGenerated,
  );

  static rust_db.DbSshKey _toRow(SshKeyEntry e) => rust_db.DbSshKey(
    id: e.id,
    label: e.label,
    privateKey: e.privateKey,
    publicKey: e.publicKey,
    keyType: e.keyType,
    isGenerated: e.isGenerated,
    createdAtMs: e.createdAt.millisecondsSinceEpoch,
  );

  /// Load all stored keys.
  Future<Map<String, SshKeyEntry>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);
    try {
      final rows = await rust_db.dbSshKeysListAll();
      final result = {for (final r in rows) r.id: _fromRow(r)};
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
    try {
      final existing = await rust_db.dbSshKeysListAll();
      for (final r in existing) {
        await rust_db.dbSshKeysDelete(id: r.id);
      }
      for (final entry in keys.values) {
        await rust_db.dbSshKeysUpsert(row: _toRow(entry));
      }
      _cache = Map.of(keys);
    } catch (e) {
      AppLogger.instance.log(
        'KeyStore.saveAll failed: $e',
        name: 'KeyStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Get a single key entry.
  Future<SshKeyEntry?> get(String id) async {
    final all = await loadAll();
    return all[id];
  }

  /// Add or update a key entry.
  Future<void> save(SshKeyEntry entry) async {
    try {
      await rust_db.dbSshKeysUpsert(row: _toRow(entry));
      _cache?[entry.id] = entry;
    } catch (e) {
      AppLogger.instance.log(
        'KeyStore.save failed: $e',
        name: 'KeyStore',
        level: LogLevel.warn,
      );
    }
  }

  /// Delete a key entry.
  Future<void> delete(String id) async {
    try {
      await rust_db.dbSshKeysDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'KeyStore.delete failed: $e',
        name: 'KeyStore',
        level: LogLevel.warn,
      );
    }
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
    return sha256.convert(bytes).toString();
  }

  /// Import an OpenSSH PEM-armored private key. Returns the created
  /// entry. Async — the underlying parse runs on the Rust core's
  /// blocking pool through the FRB boundary.
  Future<SshKeyEntry> importKey(String pem, String label) async {
    final rust_keys.KeyMaterial km;
    try {
      km = await rust_keys.keysImportOpenssh(
        pem: pem,
        passphrase: null,
        comment: label,
      );
    } catch (e) {
      throw KeyStoreException('No valid key found in PEM data', cause: e);
    }
    return SshKeyEntry(
      id: const Uuid().v4(),
      label: label,
      privateKey: km.privatePem,
      publicKey: km.publicOpenssh,
      keyType: km.keyType,
      createdAt: DateTime.now(),
    );
  }

  /// Generate a new SSH key pair. Async — keygen runs on the Rust
  /// core's blocking pool. Ed25519 returns near-instant; RSA can take
  /// several seconds at 4096 bits.
  static Future<SshKeyEntry> generateKeyPair(
    SshKeyType type,
    String label,
  ) async {
    final rust_keys.KeyMaterial km;
    switch (type) {
      case SshKeyType.ed25519:
        km = await rust_keys.keysGenerateEd25519(comment: label);
      case SshKeyType.rsa2048:
        km = await rust_keys.keysGenerateRsa(bits: 2048, comment: label);
      case SshKeyType.rsa4096:
        km = await rust_keys.keysGenerateRsa(bits: 4096, comment: label);
    }

    return SshKeyEntry(
      id: const Uuid().v4(),
      label: label,
      privateKey: km.privatePem,
      publicKey: km.publicOpenssh,
      keyType: km.keyType,
      createdAt: DateTime.now(),
      isGenerated: true,
    );
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
