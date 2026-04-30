import 'package:uuid/uuid.dart';

import '../../src/rust/api/keys.dart' as rust_keys;

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

/// Listing-only view of an SSH key — carries the metadata needed
/// by the key manager / import-dedup / export-selection UIs but
/// **not** the private PEM bytes. Fingerprints are computed inside
/// Rust (see `db_ssh_keys_list_metadata`) so dedup paths can
/// compare against scanned key material without ever pulling the
/// PEM through the FRB boundary.
class SshKeyMetadata {
  final String id;
  final String label;
  final String publicKey;
  final String keyType;
  final DateTime createdAt;
  final bool isGenerated;
  final String privateFingerprint;
  final String publicFingerprint;

  const SshKeyMetadata({
    required this.id,
    required this.label,
    required this.publicKey,
    required this.keyType,
    required this.createdAt,
    required this.isGenerated,
    required this.privateFingerprint,
    required this.publicFingerprint,
  });
}

/// Thrown when key store operations fail.
class KeyStoreException implements Exception {
  final String message;
  final Object? cause;

  const KeyStoreException(this.message, {this.cause});

  @override
  String toString() => 'KeyStoreException: $message';
}

/// SHA-256 hex of a normalized public key (OpenSSH single-line form)
/// via `lfs_core::keys::normalized_text_fingerprint`. Used as a
/// content-addressable id for deduplicating imported manager keys
/// without running the hash over private material. Normalization
/// (trim, collapse CRLF) happens Rust-side.
String publicKeyFingerprint(String publicKey) =>
    rust_keys.keysNormalizedTextFingerprint(text: publicKey);

/// SHA-256 hex of a normalized private key PEM via
/// `lfs_core::keys::normalized_text_fingerprint`. Retained only as a
/// fallback for entries that lack an extracted public half. Prefer
/// [publicKeyFingerprint] everywhere else.
String privateKeyFingerprint(String privateKey) =>
    rust_keys.keysNormalizedTextFingerprint(text: privateKey);

/// Generate a new SSH key pair. Async — keygen runs on the Rust
/// core's blocking pool. Ed25519 returns near-instant; RSA can take
/// several seconds at 4096 bits.
Future<SshKeyEntry> generateSshKeyPair(SshKeyType type, String label) async {
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

/// Stateless PEM→SshKeyEntry parser signature, matching
/// [importSshKey]. Used by config importers that want to override
/// the parser in tests without owning a Riverpod ref.
typedef SshKeyImporter = Future<SshKeyEntry> Function(String pem, String label);

/// Parse an OpenSSH PEM-armored private key into an [SshKeyEntry].
/// Returns the entry; the caller decides whether to persist it via
/// `SshKeysNotifier.save` / `importForMerge`. Async — the underlying
/// parse runs on the Rust core's blocking pool through the FRB
/// boundary.
///
/// Throws [KeyStoreException] when the PEM does not parse.
Future<SshKeyEntry> importSshKey(String pem, String label) async {
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
