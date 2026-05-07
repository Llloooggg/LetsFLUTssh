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
  Map<String, SshKeyEntry>? _cache;

  @override
  Future<List<SshKeyEntry>> build() async {
    // Metadata-only view: every Riverpod watcher of
    // [sshKeysProvider] gets a credential-stripped list (no PEM
    // private bytes pulled into the Dart heap on every list
    // refresh, no stale GC-roots once the cache is invalidated).
    // The UI consumers (key picker, key manager list, settings
    // export tile) only need label / type / fingerprints / dates;
    // the rare paths that genuinely need the PEM bytes (e.g.
    // archive export staging) call [loadAll] explicitly. The
    // `try / on KeyStoreException` below collapses an FRB failure
    // to an empty map so the UI list never throws on a transient
    // backend miss.
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

  /// Drop the in-memory cache. Called from the unlock handshake so
  /// the next read pulls fresh rows after the DB switches behind us.
  ///
  /// `ref.invalidateSelf()` is unconditional — the previous
  /// `_attached` guard skipped the rebuild whenever the provider
  /// had only ever served the metadata path (`build()` calls
  /// `loadAllMetadata`, which never sets `_attached`). The skip
  /// was the symptom behind "Failed to load key metadata: db not
  /// initialized" surviving the post-DB-open invalidate: the
  /// rebuild that would have re-loaded against the now-open DB
  /// never fired.
  void invalidateCache() {
    _cache = null;
    ref.invalidateSelf();
  }

  /// Load all stored keys with PEM bytes attached. Throws on FRB
  /// failure. Reserved for the export-tile path that genuinely needs
  /// the private material (size estimator + the actual archive /
  /// QR encoder). Every other consumer must go through
  /// [loadAllMetadata] so the Dart heap doesn't pin PEM bytes for
  /// keys nobody is actively using.
  Future<Map<String, SshKeyEntry>> loadAll() async {
    if (_cache != null) return Map.of(_cache!);
    try {
      final rows = await rust_db.dbSshKeysListAll();
      final result = {for (final r in rows) r.id: _fromRow(r)};
      _cache = result;
      return Map.of(result);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load keys',
        name: 'SshKeysNotifier',
        error: e,
      );
      throw KeyStoreException('Failed to load keys.', cause: e);
    }
  }

  /// List every stored key without pulling its PEM bytes. Returns
  /// metadata only — id, label, public half, key type, timestamps,
  /// `isGenerated` flag, plus SHA-256 fingerprints of the private
  /// and public material computed inside Rust.
  ///
  /// Call this from any path that needs *which keys exist* but not
  /// *what's in them* (key manager listing, import dedup,
  /// existing-id checks). The PEM-bearing [loadAll] stays in place
  /// for the rare paths that genuinely need the bytes (e.g. `.lfs`
  /// archive export, before the export orchestrator moves Rust-
  /// side).
  Future<Map<String, SshKeyMetadata>> loadAllMetadata() async {
    try {
      final rows = await rust_db.dbSshKeysListMetadata();
      return {
        for (final r in rows)
          r.id: SshKeyMetadata(
            id: r.id,
            label: r.label,
            publicKey: r.publicKey,
            keyType: r.keyType,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
            isGenerated: r.isGenerated,
            privateFingerprint: r.privateFingerprint,
            publicFingerprint: r.publicFingerprint,
          ),
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
      _cache?[entry.id] = entry;
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
    _cache?.remove(id);
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
}
