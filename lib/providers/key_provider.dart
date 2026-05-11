import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/ssh_key.dart';
import '../src/rust/api/db.dart' as rust_db;
import '../utils/logger.dart';

/// All stored SSH keys, sorted by createdAt descending. Loaded from
/// `letsflutssh.db` on first access; mutations route through the
/// [SshKeysNotifier] CRUD methods which invalidate state and refresh.
///
/// Replaces the prior two-tier `Provider<KeyStore>` +
/// `FutureProvider<List<SshKeyEntry>>` split. The AsyncNotifier
/// owns the FRB read/write pipeline directly.
final sshKeysProvider =
    AsyncNotifierProvider<SshKeysNotifier, List<SshKeyEntry>>(
      SshKeysNotifier.new,
    );

class SshKeysNotifier extends AsyncNotifier<List<SshKeyEntry>> {
  @override
  Future<List<SshKeyEntry>> build() async {
    // Metadata-only view: every Riverpod watcher of
    // [sshKeysProvider] gets a credential-stripped list — no PEM
    // private bytes pulled into the Dart heap on a list refresh.
    // The UI consumers (key picker, key manager list, settings
    // export tile) only need label / type / fingerprints / dates;
    // the rare archive-export staging path stays Rust-side.
    // The `try / on KeyStoreException` below collapses an FRB
    // failure to an empty map so the UI list never throws on a
    // transient backend miss.
    Map<String, SshKeyMetadata> map;
    try {
      map = await loadAllMetadata();
    } on KeyStoreException catch (e) {
      AppLogger.instance.log(
        'sshKeysProvider build: returning empty list — $e',
        name: 'SshKeysNotifier',
      );
      map = const {};
    }
    return map.values.map(_metadataToStrippedEntry).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Project a [SshKeyMetadata] row into a [SshKeyEntry] with the
  /// `privateKey` cleared. UI watchers see the same shape as before;
  /// the Dart heap never holds the PEM bytes for keys nobody is
  /// actively using.
  static SshKeyEntry _metadataToStrippedEntry(SshKeyMetadata m) => SshKeyEntry(
    id: m.id,
    label: m.label,
    privateKey: '',
    publicKey: m.publicKey,
    keyType: m.keyType,
    createdAt: m.createdAt,
    isGenerated: m.isGenerated,
  );

  /// Drop the in-memory state and re-run `build()`. Called from
  /// the unlock handshake so the next read pulls fresh rows after
  /// the DB switches behind us — the rebuild fires unconditionally
  /// to defend the prior "Failed to load key metadata: db not
  /// initialized" cold-start race where a stale cache survived the
  /// post-DB-open invalidate.
  void invalidateCache() {
    ref.invalidateSelf();
  }

  /// List every stored key without pulling its PEM bytes. Returns
  /// metadata only — id, label, public half, key type, timestamps,
  /// `isGenerated` flag, plus SHA-256 fingerprints of the private
  /// and public material computed inside Rust.
  ///
  /// Call this from any path that needs *which keys exist* but not
  /// *what's in them* (key manager listing, import dedup,
  /// existing-id checks). Paths that genuinely need PEM bytes call
  /// `dbSshKeysListAll` directly via FRB — the bytes never get
  /// pinned on a Dart-side cache so a stale Notifier copy can't
  /// drift from the canonical Rust DB row.
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
          name: 'SshKeysNotifier',
          error: e,
        );
      }
      return {
        for (final r in rows) r.id: _mergeCertOntoMetadata(r, certs[r.id]),
      };
    } catch (e) {
      // Cold-start race: the provider's `build()` fires before the
      // unlock handshake opens the DB. Returning an empty map is
      // the expected pre-open shape — `ref.invalidateSelf()` runs
      // post-unlock and pulls a fresh load. No log, no throw, this
      // is normal lifecycle, not an error.
      if (e.toString().contains('db not initialized')) {
        return const {};
      }
      AppLogger.instance.log(
        'Failed to load key metadata',
        name: 'SshKeysNotifier',
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
        'SshKeysNotifier.saveAll failed: $e',
        name: 'SshKeysNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
  }

  /// Add or update a key entry.
  Future<void> save(SshKeyEntry entry) async {
    try {
      await rust_db.dbSshKeysUpsert(row: _toRow(entry));
    } catch (e) {
      AppLogger.instance.log(
        'SshKeysNotifier.save failed: $e',
        name: 'SshKeysNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
  }

  /// Delete a key entry.
  Future<void> delete(String id) async {
    try {
      await rust_db.dbSshKeysDelete(id: id);
    } catch (e) {
      AppLogger.instance.log(
        'SshKeysNotifier.delete failed: $e',
        name: 'SshKeysNotifier',
        level: LogLevel.warn,
      );
    }
    ref.invalidateSelf();
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

  static rust_db.DbSshKey _toRow(SshKeyEntry e) => rust_db.DbSshKey(
    id: e.id,
    label: e.label,
    privateKey: e.privateKey,
    publicKey: e.publicKey,
    keyType: e.keyType,
    isGenerated: e.isGenerated,
    createdAtMs: e.createdAt.millisecondsSinceEpoch,
  );

  /// Project the `ssh_keys` row + optional `ssh_key_certificates`
  /// row into a single [SshKeyMetadata]. The cert blob itself is
  /// dropped here — the listing view only needs the typed summary
  /// (principals / validity / fingerprint). The bytes are fetched
  /// on demand by the connect path's SecretStore staging.
  ///
  /// `principals` / `criticalOptions` arrive as serialized JSON in
  /// the DAO row (one TEXT column each); a malformed JSON value is
  /// logged-and-skipped so a tampered DB row never sinks the whole
  /// listing.
  static SshKeyMetadata _mergeCertOntoMetadata(
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
      principals = _decodeJsonStringList(cert.principals);
      critical = _decodeJsonStringMap(cert.criticalOptions);
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
    );
  }

  static List<String> _decodeJsonStringList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList(growable: false);
      }
    } catch (e) {
      AppLogger.instance.log(
        'Failed to decode cert principals JSON',
        name: 'SshKeysNotifier',
        error: e,
        level: LogLevel.warn,
      );
    }
    return const [];
  }

  static Map<String, String> _decodeJsonStringMap(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (e) {
      AppLogger.instance.log(
        'Failed to decode cert critical_options JSON',
        name: 'SshKeysNotifier',
        error: e,
        level: LogLevel.warn,
      );
    }
    return const {};
  }
}
