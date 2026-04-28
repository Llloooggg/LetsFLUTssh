import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import '../security/_crypto_compat.dart';

/// TOFU (Trust On First Use) host key verification backed by
/// `lfs_core.db`. Engine behind the DAO is Rust + rusqlite.
///
/// The Dart side is a thin snapshot mirror: `entries` / `count`
/// expose the in-memory cache populated by [load]; mutating calls
/// (upsert / remove / clear / import) route through FRB and the
/// cache refreshes on the matching `KnownHostsChanged` bus event.
/// Failures from FRB calls (DB locked / native lib missing in
/// unit tests) are caught at every entry point and degrade to
/// "no DB attached" semantics so a race between unlock and the
/// first read cannot crash the connect path.
class KnownHostsManager {
  KnownHostsManager() {
    // Subscribe to the global KnownHosts topic so any mutation
    // (including from the FRB layer's bulk-import path) refreshes
    // the cache. The subscription survives `invalidateCache`
    // because the manager itself outlives the unlock cycle.
    //
    // The subscribe call hits the FRB native lib at construction
    // time; flutter_test contexts that don't load the lib raise
    // synchronously. Catch + log so the manager stays usable in
    // tests with mocked FRB DAOs.
    try {
      _busSub = AppBus.instance.subscribe(rust_bus.BusTopic.knownHosts).listen((
        event,
      ) {
        if (event is rust_bus.BusEvent_KnownHostsChanged) {
          unawaited(reload());
        }
      });
    } catch (e) {
      AppLogger.instance.log(
        'KnownHostsManager bus subscribe failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  final Map<String, String> _hosts = {};
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake.
  void invalidateCache() {
    _hosts.clear();
    _loaded = false;
    _loadFuture = null;
  }

  /// Read-only view of all known host entries.
  ///
  /// Keys are `host:port`, values are `keytype base64key`.
  Map<String, String> get entries => Map.unmodifiable(_hosts);

  /// Number of known hosts.
  int get count => _hosts.length;

  /// Cached load future — ensures concurrent calls to [load] don't race.
  Future<void>? _loadFuture;

  /// True once [_doLoad] has completed successfully at least once. Used to
  /// distinguish "load already done" from "load attempted but failed and
  /// should be retried on the next call".
  bool _loaded = false;

  /// Initialize and load known hosts from database.
  ///
  /// Safe to call concurrently — the first call does the actual I/O,
  /// subsequent calls await the same future. If the underlying I/O fails
  /// the failure is logged (not rethrown) and the cached future is
  /// cleared, so the next call retries instead of returning instantly with
  /// a stale empty cache.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _runLoad();
  }

  /// Force a re-fetch from the database, discarding the cached state.
  /// Use after operations that mutate the underlying table outside of this
  /// manager (e.g. import, settings reset).
  Future<void> reload() {
    _loaded = false;
    _loadFuture = null;
    return load();
  }

  Future<void> _runLoad() async {
    try {
      await _doLoad();
    } finally {
      if (!_loaded) _loadFuture = null;
    }
  }

  Future<void> _doLoad() async {
    try {
      final entries = await rust_db.dbKnownHostsListAll();
      _hosts.clear();
      for (final e in entries) {
        _hosts['${e.host}:${e.port}'] = '${e.keyType} ${e.keyBase64}';
      }
      _loaded = true;
      AppLogger.instance.log(
        'Loaded ${_hosts.length} known hosts',
        name: 'KnownHosts',
      );
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load known hosts',
        name: 'KnownHosts',
        error: e,
      );
    }
  }

  /// Insert or update a single host entry. Routes through the FRB
  /// upsert; the resulting `KnownHostsChanged` bus event refreshes
  /// the cache.
  Future<void> upsert(
    String host,
    int port,
    String keyType,
    String keyBase64,
  ) async {
    try {
      await rust_db.dbKnownHostsUpsertByHostPort(
        host: host,
        port: port,
        keyType: keyType,
        keyBase64: keyBase64,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.instance.log(
        'upsert FRB write failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  /// Remove a single known host entry.
  Future<void> removeHost(String hostPort) async {
    final parts = hostPort.split(':');
    if (parts.isEmpty) return;
    final host = parts[0];
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;
    try {
      await rust_db.dbKnownHostsDeleteByHostPort(host: host, port: port);
      AppLogger.instance.log(
        'Removed known host: $hostPort',
        name: 'KnownHosts',
      );
    } catch (e) {
      AppLogger.instance.log(
        'removeHost FRB delete failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  /// Remove multiple known host entries. The cache refresh fires
  /// once per row's bus event, but the listeners (settings UI) only
  /// re-render once per microtask so the cost is bounded.
  Future<void> removeMultiple(Set<String> hostPorts) async {
    for (final hp in hostPorts) {
      final parts = hp.split(':');
      if (parts.isEmpty) continue;
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;
      try {
        await rust_db.dbKnownHostsDeleteByHostPort(host: host, port: port);
      } catch (e) {
        AppLogger.instance.log(
          'removeMultiple FRB delete failed for $hp: $e',
          name: 'KnownHosts',
          level: LogLevel.warn,
        );
      }
    }
  }

  /// Remove all known host entries.
  Future<void> clearAll() async {
    try {
      await rust_db.dbKnownHostsClearAll();
      AppLogger.instance.log('Cleared all known hosts', name: 'KnownHosts');
    } catch (e) {
      AppLogger.instance.log(
        'clearAll FRB write failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  /// Import entries from a LetsFLUTssh-format known_hosts file.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    return importFromString(content);
  }

  /// Import entries from a multi-line known_hosts blob. Routes
  /// through the Rust importer (`lfs_core::known_hosts::import_from_string`)
  /// so the parser walk + per-line dedup + DB upserts run inside one
  /// task. Skipped hashed-hostname rows are surfaced via the warning
  /// log so the user knows their `HashKnownHosts yes` lines were not
  /// silently swallowed.
  ///
  /// Returns the number of new entries added.
  Future<int> importFromString(String content) async {
    try {
      final summary = await rust_db.dbKnownHostsImportFromString(
        content: content,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (summary.added > 0) {
        AppLogger.instance.log(
          'Imported ${summary.added} known hosts',
          name: 'KnownHosts',
        );
      }
      if (summary.skippedHashed > 0) {
        AppLogger.instance.log(
          'Skipped ${summary.skippedHashed} hashed known-hosts entries '
          '(HashKnownHosts) — we cannot reverse the HMAC-SHA1 hash back '
          'to a hostname for storage',
          name: 'KnownHosts',
          level: LogLevel.warn,
        );
      }
      return summary.added.toInt();
    } catch (e) {
      AppLogger.instance.log(
        'importFromString FRB call failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
      return 0;
    }
  }

  /// Export all entries to the LetsFLUTssh known_hosts wire format.
  ///
  /// Routes through the Rust exporter so the row order stays
  /// deterministic across exports of the same DB. Used by the
  /// `.lfs` archive composer to round-trip the user's TOFU history.
  Future<String> exportToString() async {
    try {
      return await rust_db.dbKnownHostsExportToString();
    } catch (e) {
      AppLogger.instance.log(
        'exportToString FRB call failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
      return '';
    }
  }

  /// Compute SHA256 fingerprint of host key bytes — `SHA256:<base64>`,
  /// the OpenSSH `ssh-keygen -lf` shape.
  static String fingerprint(List<int> keyBytes) {
    final hash = sha256Compat(keyBytes);
    return 'SHA256:${base64Encode(hash)}';
  }

  /// Cancel the bus subscription. Idempotent — safe to call
  /// multiple times.
  void dispose() {
    unawaited(_busSub?.cancel());
    _busSub = null;
  }
}
