import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/db.dart' as rust_db;
import '../src/rust/api/ssh.dart' as rust_ssh;
import '../utils/logger.dart';

/// TOFU (Trust On First Use) host key state — keys are `host:port`,
/// values are `keytype base64key`. Mirrors the FRB-side
/// `lfs_core::known_hosts` registry; mutations route through the
/// Rust DAO and the resulting `KnownHostsChanged` bus event refreshes
/// the local cache.
///
/// Replaces the prior two-tier `Provider<KnownHostsManager>` shape
/// with a single `NotifierProvider<KnownHostsNotifier, Map<String,
/// String>>`. The notifier owns the bus subscription, the FRB
/// pipeline, and the in-memory snapshot directly.
final knownHostsProvider =
    NotifierProvider<KnownHostsNotifier, Map<String, String>>(
      KnownHostsNotifier.new,
    );

class KnownHostsNotifier extends Notifier<Map<String, String>> {
  StreamSubscription<rust_bus.BusEvent>? _busSub;
  Future<void>? _loadFuture;
  bool _loaded = false;

  @override
  Map<String, String> build() {
    // Subscribe to the global KnownHosts topic so any mutation
    // (including the FRB layer's bulk-import path) refreshes the
    // cache. The subscribe call hits the FRB native lib at
    // construction time; flutter_test contexts that don't load the
    // lib raise synchronously. Catch + log so the notifier stays
    // usable in tests with mocked FRB DAOs.
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
        'KnownHostsNotifier bus subscribe failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
    ref.onDispose(() {
      unawaited(_busSub?.cancel());
      _busSub = null;
    });
    return const {};
  }

  /// Read-only view of all known host entries.
  Map<String, String> get entries => Map.unmodifiable(state);

  /// Number of known hosts.
  int get count => state.length;

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake.
  void invalidateCache() {
    state = const {};
    _loaded = false;
    _loadFuture = null;
  }

  /// Initialize and load known hosts from database.
  ///
  /// Safe to call concurrently — the first call does the actual I/O,
  /// subsequent calls await the same future. If the underlying I/O
  /// fails the failure is logged (not rethrown) and the cached future
  /// is cleared, so the next call retries instead of returning
  /// instantly with a stale empty cache.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _runLoad();
  }

  /// Force a re-fetch from the database, discarding the cached state.
  /// Use after operations that mutate the underlying table outside of
  /// this notifier (e.g. import, settings reset).
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
      final next = <String, String>{};
      for (final e in entries) {
        next['${e.host}:${e.port}'] = '${e.keyType} ${e.keyBase64}';
      }
      state = next;
      _loaded = true;
      AppLogger.instance.log(
        'Loaded ${next.length} known hosts',
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
  /// Returns the number of new entries added (existing hosts are
  /// skipped). The file read happens Rust-side so the raw bytes
  /// never cross the FRB boundary into the Dart heap.
  Future<int> importFromFile(String path) async {
    try {
      final summary = await rust_db.dbKnownHostsImportFromPath(
        path: path,
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
          'Skipped ${summary.skippedHashed} hashed known_hosts entries',
          name: 'KnownHosts',
          level: LogLevel.warn,
        );
      }
      return summary.added;
    } catch (e) {
      AppLogger.instance.log(
        'importFromFile failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
      return 0;
    }
  }

  /// Import entries from a multi-line known_hosts blob. Routes
  /// through the Rust importer (`lfs_core::known_hosts::
  /// import_from_string`) so the parser walk + per-line dedup + DB
  /// upserts run inside one task. Skipped hashed-hostname rows are
  /// surfaced via the warning log so the user knows their
  /// `HashKnownHosts yes` lines were not silently swallowed.
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
}

/// Compute SHA256 fingerprint of host key bytes —
/// `SHA256:<base64-no-pad>`, the OpenSSH `ssh-keygen -lf` shape —
/// via `lfs_core::ssh::format_fingerprint`. Same helper backs
/// KnownHostsRow.host_key_fingerprint Rust-side.
String knownHostFingerprint(List<int> keyBytes) =>
    rust_ssh.sshFormatHostKeyFingerprint(
      keyBytes: keyBytes is Uint8List ? keyBytes : Uint8List.fromList(keyBytes),
    );
