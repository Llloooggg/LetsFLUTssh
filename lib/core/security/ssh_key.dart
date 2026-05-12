import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/keys.dart' as rust_keys;

/// Supported SSH key types for generation and import.
///
/// The `sk*` variants are FIDO2 hardware-bound keys —
/// `sk-ssh-ed25519@openssh.com` and
/// `sk-ecdsa-sha2-nistp256@openssh.com`. These keys cannot be
/// generated inside the app (the device firmware mints them via
/// `ssh-keygen -t ed25519-sk` / `-t ecdsa-sk`); they're imported by
/// pasting the matching `*.pub` file. Persisted alongside the rest
/// of the key manager rows so the connect path can resolve them
/// transparently.
enum SshKeyType {
  ed25519('Ed25519'),
  rsa2048('RSA 2048'),
  rsa4096('RSA 4096'),
  skEd25519('FIDO2 Ed25519'),
  skEcdsaP256('FIDO2 ECDSA P-256');

  const SshKeyType(this.label);
  final String label;

  /// True for hardware-bound (`sk-*`) variants — used by the connect
  /// dispatch and the key-manager row badge.
  bool get isHardwareBound =>
      this == SshKeyType.skEd25519 || this == SshKeyType.skEcdsaP256;
}

/// Validity window of a paired OpenSSH certificate. `from` / `to`
/// match the cert's wire-format `valid_after` / `valid_before` —
/// unix seconds projected to `DateTime`. A row whose cert is
/// expired renders the red "Expired" badge in the key manager.
class CertValidity {
  final DateTime from;
  final DateTime to;
  const CertValidity({required this.from, required this.to});

  bool get isExpired => to.isBefore(DateTime.now());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CertValidity && from == other.from && to == other.to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// An SSH key entry stored in the key manager.
///
/// `certificate` carries the optional OpenSSH cert blob paired to
/// this key — `null` for keys without a cert attached, which is the
/// common case. `validity`, `principals`, and `criticalOptions`
/// summarise the cert's wire-format fields and are kept on the
/// entry so the key manager row can render without an extra FRB
/// hop per row.
class SshKeyEntry {
  final String id;
  final String label;
  final String privateKey;
  final String publicKey;
  final String keyType;
  final DateTime createdAt;
  final bool isGenerated;
  final Uint8List? certificate;
  final CertValidity? validity;
  final List<String> principals;
  final Map<String, String> criticalOptions;

  /// FIDO2 credential id for hardware-bound `sk-*` keys. `null` for
  /// software keys; the opaque CTAP2 blob the device matches against
  /// on every assertion for hardware-bound keys. Persists alongside
  /// the `*.pub` body so the connect path can resolve it without an
  /// extra FRB hop.
  final Uint8List? credentialId;

  /// FIDO2 `application` field — the SSH RP-id (typically `ssh:`).
  /// `null` for software keys.
  final String? applicationString;

  /// User-verification bit captured at import. Drives the PIN prompt
  /// in [HardwareKeyPromptDialog] on connect.
  final bool hasUserVerification;

  /// Per-key dispatch policy for the in-process ssh-agent endpoint.
  /// One of `'always'` (sign silently), `'ask'` (default; route
  /// every SIGN_REQUEST through a Flutter confirmation dialog),
  /// `'deny'` (always refuse). Mirrored verbatim from
  /// `ssh_keys.agent_policy` on the Rust side; the Settings UI
  /// rebinds this via [updateAgentPolicy] on KeyStore.
  final String agentPolicy;

  const SshKeyEntry({
    required this.id,
    required this.label,
    required this.privateKey,
    required this.publicKey,
    required this.keyType,
    required this.createdAt,
    this.isGenerated = false,
    this.certificate,
    this.validity,
    this.principals = const [],
    this.criticalOptions = const {},
    this.credentialId,
    this.applicationString,
    this.hasUserVerification = false,
    this.agentPolicy = 'ask',
  });

  /// True when the row is a hardware-bound `sk-*` key. Drives the
  /// "Hardware-bound (FIDO2)" badge in the key manager + the connect
  /// path's dispatch into [ssh_connect_pubkey_sk].
  bool get isHardwareBound => credentialId != null;

  SshKeyEntry copyWith({
    String? label,
    Uint8List? certificate,
    CertValidity? validity,
    List<String>? principals,
    Map<String, String>? criticalOptions,
    Uint8List? credentialId,
    String? applicationString,
    bool? hasUserVerification,
    String? agentPolicy,
  }) => SshKeyEntry(
    id: id,
    label: label ?? this.label,
    privateKey: privateKey,
    publicKey: publicKey,
    keyType: keyType,
    createdAt: createdAt,
    isGenerated: isGenerated,
    certificate: certificate ?? this.certificate,
    validity: validity ?? this.validity,
    principals: principals ?? this.principals,
    criticalOptions: criticalOptions ?? this.criticalOptions,
    credentialId: credentialId ?? this.credentialId,
    applicationString: applicationString ?? this.applicationString,
    hasUserVerification: hasUserVerification ?? this.hasUserVerification,
    agentPolicy: agentPolicy ?? this.agentPolicy,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'private_key': privateKey,
    'public_key': publicKey,
    'key_type': keyType,
    'created_at': createdAt.toIso8601String(),
    'is_generated': isGenerated,
    if (certificate != null) 'certificate': certificate!.toList(),
    if (validity != null) ...{
      'valid_from': validity!.from.toIso8601String(),
      'valid_to': validity!.to.toIso8601String(),
    },
    if (principals.isNotEmpty) 'principals': principals,
    if (criticalOptions.isNotEmpty) 'critical_options': criticalOptions,
    if (credentialId != null) 'credential_id': credentialId!.toList(),
    if (applicationString != null) 'application_string': applicationString,
    if (hasUserVerification) 'has_user_verification': true,
    if (agentPolicy != 'ask') 'agent_policy': agentPolicy,
  };

  factory SshKeyEntry.fromJson(Map<String, dynamic> json) {
    final certList = json['certificate'];
    final Uint8List? cert = certList is List
        ? Uint8List.fromList(certList.cast<int>())
        : null;
    final from = DateTime.tryParse(json['valid_from'] as String? ?? '');
    final to = DateTime.tryParse(json['valid_to'] as String? ?? '');
    final CertValidity? validity = (from != null && to != null)
        ? CertValidity(from: from, to: to)
        : null;
    final principalsRaw = json['principals'];
    final List<String> principals = principalsRaw is List
        ? principalsRaw.cast<String>()
        : const [];
    final critRaw = json['critical_options'];
    final Map<String, String> critical = critRaw is Map
        ? critRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : const {};
    final credIdList = json['credential_id'];
    final Uint8List? credentialId = credIdList is List
        ? Uint8List.fromList(credIdList.cast<int>())
        : null;
    return SshKeyEntry(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      privateKey: json['private_key'] as String? ?? '',
      publicKey: json['public_key'] as String? ?? '',
      keyType: json['key_type'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isGenerated: json['is_generated'] as bool? ?? false,
      certificate: cert,
      validity: validity,
      principals: principals,
      criticalOptions: critical,
      credentialId: credentialId,
      applicationString: json['application_string'] as String?,
      hasUserVerification: json['has_user_verification'] as bool? ?? false,
      agentPolicy: json['agent_policy'] as String? ?? 'ask',
    );
  }

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
///
/// `validity` / `principals` / `criticalOptions` / `certFingerprint`
/// are non-null when a certificate is paired to this key. The key-
/// manager UI joins them onto the row via a separate
/// `db_ssh_key_certificate_get` call rather than redesigning the
/// metadata listing — most keys have no cert and the cert lookup
/// is keyed by `id` so the merge is O(1) per row.
class SshKeyMetadata {
  final String id;
  final String label;
  final String publicKey;
  final String keyType;
  final DateTime createdAt;
  final bool isGenerated;
  final String privateFingerprint;
  final String publicFingerprint;
  final CertValidity? validity;
  final List<String> principals;
  final Map<String, String> criticalOptions;
  final String certFingerprint;

  /// Backend discriminator mirrored from `ssh_keys.backend`. One of
  /// `software` / `fido2` / `pkcs11` / `tpm` / `enclave` / `hello` /
  /// `keystore`. Drives the badge picker in the key manager — software
  /// rows render no badge, FIDO2 the "Hardware-bound (FIDO2)" pill,
  /// PKCS#11 the "Smart card / token" pill (with an info popover
  /// showing module + token serial + object label).
  final String backend;

  /// PKCS#11 module path captured at import. `null` for non-PKCS#11
  /// rows.
  final String? pkcs11ModulePath;

  /// PKCS#11 token serial captured at import.
  final String? pkcs11TokenSerial;

  /// PKCS#11 object label (`CKA_LABEL`) — the on-token name of the
  /// key object. Distinct from the row's user-typed [label].
  final String? pkcs11ObjectLabel;

  const SshKeyMetadata({
    required this.id,
    required this.label,
    required this.publicKey,
    required this.keyType,
    required this.createdAt,
    required this.isGenerated,
    required this.privateFingerprint,
    required this.publicFingerprint,
    this.validity,
    this.principals = const [],
    this.criticalOptions = const {},
    this.certFingerprint = '',
    this.backend = 'software',
    this.pkcs11ModulePath,
    this.pkcs11TokenSerial,
    this.pkcs11ObjectLabel,
  });

  bool get hasCertificate => certFingerprint.isNotEmpty;

  /// True when the row's `backend` discriminator names a PKCS#11
  /// smart-card / token. Drives the key-manager badge + info popover.
  bool get isPkcs11 => backend == 'pkcs11';

  /// True when the row's `backend` discriminator names a FIDO2 sk-*
  /// hardware key. Mirrors the existing `sk-*` keyType heuristic so
  /// rows imported before schema v9 (which the migration arm relabels
  /// to `fido2`) still pick the FIDO2 badge.
  bool get isFido2 => backend == 'fido2';

  /// True when the row's `backend` discriminator names an Apple
  /// Secure Enclave key. Drives the key-manager badge + info popover
  /// + the "device-bound" warning the key cannot leave this Mac /
  /// iPhone.
  bool get isEnclave => backend == 'enclave';
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
    case SshKeyType.skEd25519:
    case SshKeyType.skEcdsaP256:
      // Hardware-bound keys are minted on the device by `ssh-keygen
      // -t ed25519-sk` / `-t ecdsa-sk`; the app imports the matching
      // public-key file rather than generating one in-process. The
      // key manager dialog gates the generate flow before reaching
      // here — surface a typed error if the dispatch leaks through.
      throw const KeyStoreException(
        'Hardware-bound (sk-*) keys are generated on the device, '
        'not by the app — import the matching *.pub file instead.',
      );
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
