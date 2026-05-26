import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/security/ssh_key.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/db.dart' as rust_db;
import '../utils/logger.dart';

/// Stream of the latest SSH-key listing. Yields:
///   1. An initial credential-stripped list pulled via FRB on first
///      watch.
///   2. A fresh list on every `BusEvent::KeysChanged` tick the Rust
///      side publishes after every `ssh_keys` /
///      `ssh_key_certificates` write.
///
/// The Rust side is the single source of truth: every mutation goes
/// through FRB (`db_ssh_keys_*` / `db_ssh_key_certificate_*` and the
/// per-backend `*_ssh_generate` / `*_ssh_delete` shims), Rust
/// publishes `KeysChanged`, this stream re-fetches. No Dart-cached
/// state.
///
/// Cold-start: the first `_loadKeys` call runs lazily on first
/// watch. Pre-FRB-init contexts catch the `StateError` and yield an
/// empty list so the key manager / session-edit picker paint
/// without crashing.
final sshKeysStreamProvider = StreamProvider<List<SshKeyEntry>>((ref) async* {
  yield await _loadKeys();
  await for (final event in AppBus.instance.subscribe(rust_bus.BusTopic.keys)) {
    if (event is rust_bus.BusEvent_KeysChanged) {
      yield await _loadKeys();
    }
  }
});

/// Synchronous view of the latest SSH-key listing. Yields an empty
/// list while the first stream emission is in flight or the stream
/// is in an error state — consumers that need the loading / error
/// discriminant watch [sshKeysStreamProvider] directly.
///
/// Back-compat alias: every existing `ref.watch(sshKeysProvider)`
/// keeps working while the data flow itself goes Rust → stream →
/// derived Provider. Same shape, zero Dart-cached state.
final sshKeysProvider = Provider<List<SshKeyEntry>>((ref) {
  final async = ref.watch(sshKeysStreamProvider);
  return async.hasValue
      ? async.value as List<SshKeyEntry>
      : const <SshKeyEntry>[];
});

/// Pure-FRB mutator surface for SSH keys. No Dart-cached state —
/// every method is a thin pass-through to the FRB write paths.
/// After each successful FRB write, Rust publishes
/// `BusEvent::KeysChanged` on the global bus;
/// [sshKeysStreamProvider] re-fetches the listing, the derived
/// [sshKeysProvider] re-emits, every widget consumer rebuilds.
///
/// The metadata-listing reader ([loadAllMetadata]) lives here too
/// so consumers that need per-backend discriminator columns (the
/// session-edit key picker badge) reach for one mutator handle
/// rather than wiring a second provider.
class SshKeysMutator {
  const SshKeysMutator();

  /// List every stored key without pulling its PEM bytes. Returns
  /// metadata only — id, label, public half, key type, timestamps,
  /// `isGenerated` flag, plus SHA-256 fingerprints of the private
  /// and public material computed inside Rust.
  ///
  /// Call this from any path that needs *which keys exist* but not
  /// *what's in them* (key manager listing, import dedup,
  /// existing-id checks). Paths that genuinely need PEM bytes call
  /// `dbSshKeysListAll` directly via FRB — the bytes never get
  /// pinned on a Dart-side cache so a stale copy can't drift from
  /// the canonical Rust DB row.
  Future<Map<String, SshKeyMetadata>> loadAllMetadata() async {
    try {
      final rows = await rust_db.dbSshKeysListMetadata();
      // Cert blobs live in a separate join table — one FRB call to
      // pull every attached cert lets the merge stay O(N) without
      // an N-FRB-hop fan-out per row.
      Map<String, rust_db.DbSshKeyCertificate> certs = const {};
      try {
        final certRows = await rust_db.dbSshKeyCertificatesListAll();
        certs = {for (final c in certRows) c.keyId: c};
      } catch (e) {
        AppLogger.instance.log(
          'Failed to load certificate join rows',
          name: 'SshKeysMutator',
          error: e,
        );
      }
      return {
        for (final r in rows) r.id: _mergeCertOntoMetadata(r, certs[r.id]),
      };
    } catch (e) {
      // Cold-start race: the load fires before the unlock handshake
      // opens the DB. Returning an empty map is the expected
      // pre-open shape — the stream re-fetches once the
      // post-unlock cascade publishes `KeysChanged`.
      if (e.toString().contains('db not initialized')) {
        return const {};
      }
      AppLogger.instance.log(
        'Failed to load key metadata',
        name: 'SshKeysMutator',
        error: e,
      );
      throw KeyStoreException('Failed to load key metadata.', cause: e);
    }
  }

  /// Save all keys (replaces entire store). Routes through the
  /// `db_ssh_keys_replace_all` FRB endpoint so the operation
  /// lands as a single FRB hop + one rusqlite transaction.
  /// **Don't fan out to N delete + N upsert calls** — that pays
  /// 2N round-trips for the same outcome and opens a
  /// half-cleared-table race on a transient FRB failure mid-loop.
  Future<void> saveAll(Map<String, SshKeyEntry> keys) async {
    try {
      final rows = keys.values.map(_toRow).toList(growable: false);
      await rust_db.dbSshKeysReplaceAll(rows: rows);
    } catch (e) {
      AppLogger.instance.log(
        'SshKeysMutator.saveAll failed: $e',
        name: 'SshKeysMutator',
        level: LogLevel.warn,
      );
    }
  }

  /// Add or update a key entry.
  Future<void> save(SshKeyEntry entry) async {
    try {
      await rust_db.dbSshKeysUpsert(row: _toRow(entry));
    } catch (e) {
      AppLogger.instance.log(
        'SshKeysMutator.save failed: $e',
        name: 'SshKeysMutator',
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
        'SshKeysMutator.delete failed: $e',
        name: 'SshKeysMutator',
        level: LogLevel.warn,
      );
    }
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
  ///
  /// Routes through `lfs_core::db::ssh_keys::import_key_for_merge`
  /// (FRB async) so the dedup-by-fingerprint + label-uniqueness +
  /// insert sequence runs as one sqlite transaction.
  Future<String> importForMerge(SshKeyEntry entry) =>
      rust_db.dbSshKeysImportForMerge(proposed: _toRow(entry));

  /// Import an OpenSSH PEM-armored private key. Returns the created
  /// entry — the caller decides whether to persist via [save] /
  /// [importForMerge]. Thin delegation to the top-level
  /// [importSshKey] in `ssh_key.dart` so callers without a Riverpod
  /// ref (config importer, ssh-dir wizard) can hit the same parser.
  Future<SshKeyEntry> importKey(String pem, String label) =>
      importSshKey(pem, label);
}

/// Process-singleton mutator handle. Stateless — every method
/// pass-throughs to FRB. Tests override the provider directly with
/// a fake mutator subclass when they need to assert call counts or
/// seed responses.
final sshKeysMutatorProvider = Provider<SshKeysMutator>(
  (ref) => const SshKeysMutator(),
);

/// Fetch the current credential-stripped listing from the Rust DB.
/// All failure modes degrade to an empty list — the key manager /
/// picker stays usable on pre-FRB / DB-missing / locked-tier reads.
Future<List<SshKeyEntry>> _loadKeys() async {
  Map<String, SshKeyMetadata> map;
  try {
    map = await const SshKeysMutator().loadAllMetadata();
  } on KeyStoreException catch (e) {
    AppLogger.instance.log(
      'sshKeysStreamProvider: empty list — $e',
      name: 'SshKeysStream',
    );
    map = const {};
  }
  AppLogger.instance.log(
    'Loaded ${map.length} ssh keys',
    name: 'SshKeysStream',
  );
  return map.values.map(_metadataToStrippedEntry).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// Project a [SshKeyMetadata] row into a [SshKeyEntry] with the
/// `privateKey` cleared. UI watchers see the same shape as before;
/// the Dart heap never holds the PEM bytes for keys nobody is
/// actively using.
SshKeyEntry _metadataToStrippedEntry(SshKeyMetadata m) => SshKeyEntry(
  id: m.id,
  label: m.label,
  privateKey: '',
  publicKey: m.publicKey,
  keyType: m.keyType,
  createdAt: m.createdAt,
  isGenerated: m.isGenerated,
);

rust_db.DbSshKey _toRow(SshKeyEntry e) => rust_db.DbSshKey(
  id: e.id,
  label: e.label,
  privateKey: e.privateKey,
  publicKey: e.publicKey,
  keyType: e.keyType,
  isGenerated: e.isGenerated,
  createdAtMs: e.createdAt.millisecondsSinceEpoch,
  credentialId: e.credentialId,
  applicationString: e.applicationString,
  hasUserVerification: e.hasUserVerification,
  agentPolicy: e.agentPolicy,
  // Backend + PKCS#11 columns ride through unchanged when the
  // `SshKeyEntry` carries them; software keys leave them at the
  // default `'software'` + null. The full PKCS#11 / Enclave /
  // Hello / TPM import flows bypass this row builder entirely
  // (Rust composes the row server-side); this path is the legacy
  // `SshKeyEntry` round-trip for software / FIDO2 rows that the
  // existing key-manager state machine already produces, so the
  // TPM-only columns stay at their schema defaults (NULL / 0).
  backend: 'software',
  tpmPinRequired: false,
  keystoreStrongbox: false,
  keystoreUserAuthRequired: false,
  // `SshKeyEntry` carries the live local row; `imported_as_stub`
  // is per-import metadata that never lives on the typed entry.
  // A row built from this helper is always a software / FIDO2
  // row the user actively edits.
  importedAsStub: false,
);

/// Project the `ssh_keys` row + optional `ssh_key_certificates`
/// row into a single [SshKeyMetadata]. The cert blob itself is
/// dropped here — the listing view only needs the typed summary
/// (principals / validity / fingerprint). The bytes are fetched
/// on demand by the connect path's SecretStore staging.
///
/// `principals` / `criticalOptions` arrive already typed as
/// `Vec<String>` / `HashMap<String, String>` from the FRB-mirrored
/// DAO row — the JSON encode / decode lives Rust-side at the SQL
/// boundary, so a malformed stored value collapses to the empty
/// list / map inside Rust before crossing the boundary and never
/// surfaces here.
SshKeyMetadata _mergeCertOntoMetadata(
  rust_db.DbSshKeyMetadata r,
  rust_db.DbSshKeyCertificate? cert,
) {
  CertValidity? validity;
  List<String> principals = const [];
  Map<String, String> critical = const {};
  String certFp = '';
  if (cert != null) {
    validity = CertValidity(
      from: DateTime.fromMillisecondsSinceEpoch(
        cert.validAfter * 1000,
        isUtc: true,
      ),
      to: DateTime.fromMillisecondsSinceEpoch(
        cert.validBefore * 1000,
        isUtc: true,
      ),
    );
    principals = cert.principals;
    critical = cert.criticalOptions;
    certFp = cert.fingerprint;
  }
  return SshKeyMetadata(
    id: r.id,
    label: r.label,
    publicKey: r.publicKey,
    keyType: r.keyType,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
    isGenerated: r.isGenerated,
    privateFingerprint: r.privateFingerprint,
    publicFingerprint: r.publicFingerprint,
    validity: validity,
    principals: principals,
    criticalOptions: critical,
    certFingerprint: certFp,
    backend: r.backend,
    pkcs11ModulePath: r.pkcs11ModulePath,
    pkcs11TokenSerial: r.pkcs11TokenSerial,
    pkcs11ObjectLabel: r.pkcs11ObjectLabel,
    helloCredentialName: r.helloCredentialName,
    tpmHandle: r.tpmHandle,
    tpmProvider: r.tpmProvider,
    tpmPinRequired: r.tpmPinRequired,
    cngKeyName: r.cngKeyName,
    keystoreAlias: r.keystoreAlias,
    keystoreStrongBox: r.keystoreStrongbox,
    keystoreUserAuthRequired: r.keystoreUserAuthRequired,
    keystorePlatform: r.keystorePlatform,
    importedAsStub: r.importedAsStub,
  );
}
