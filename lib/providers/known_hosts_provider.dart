import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/db.dart' as rust_db;
import '../src/rust/api/ssh.dart' as rust_ssh;
import '../utils/logger.dart';

/// Stream of the latest known-hosts listing keyed by `host:port` →
/// `keytype base64key`. Yields:
///   1. An initial snapshot pulled via FRB on first watch.
///   2. A fresh snapshot on every `BusEvent::KnownHostsChanged` tick
///      the Rust side publishes after every `known_hosts` write.
///
/// The Rust side is the single source of truth: every mutation goes
/// through FRB (`db_known_hosts_upsert_by_host_port` /
/// `db_known_hosts_delete_by_host_port` / `db_known_hosts_clear_all`
/// / `db_known_hosts_import_from_string` /
/// `db_known_hosts_import_from_path`), Rust publishes
/// `KnownHostsChanged`, this stream re-fetches. No Dart-cached
/// state.
///
/// Cold-start: the first `_loadEntries` call runs lazily on first
/// watch and may race `db_init` (provider mounts between FRB init
/// and `securityController.bootstrap`). The `"db not initialized"`
/// branch yields an empty map silently; the post-unlock cascade's
/// `KnownHostsChanged` publish drives the first real load.
/// Pre-FRB-init contexts (flutter_test without the native lib)
/// catch the `StateError` through the same branch.
final knownHostsStreamProvider = StreamProvider<Map<String, String>>((
  ref,
) async* {
  yield await _loadEntries();
  await for (final event in AppBus.instance.subscribe(
    rust_bus.BusTopic.knownHosts,
  )) {
    if (event is rust_bus.BusEvent_KnownHostsChanged) {
      yield await _loadEntries();
    }
  }
});

/// Synchronous view of the latest known-hosts map. Yields an empty
/// map while the first stream emission is in flight or the stream
/// is in an error state — consumers that need the loading / error
/// discriminant watch [knownHostsStreamProvider] directly.
///
/// Back-compat alias: every existing `ref.watch(knownHostsProvider)`
/// keeps working while the data flow itself goes Rust → stream →
/// derived Provider. Same shape, zero Dart-cached state.
final knownHostsProvider = Provider<Map<String, String>>((ref) {
  final async = ref.watch(knownHostsStreamProvider);
  return async.hasValue
      ? async.value as Map<String, String>
      : const <String, String>{};
});

/// Pure-FRB mutator surface for known hosts. No Dart-cached state —
/// every method is a thin pass-through to the FRB write paths.
/// After each successful FRB write, Rust publishes
/// `BusEvent::KnownHostsChanged` on the global bus;
/// [knownHostsStreamProvider] re-fetches the listing, the derived
/// [knownHostsProvider] re-emits, every widget consumer rebuilds.
class KnownHostsMutator {
  const KnownHostsMutator();

  /// Insert or update a single host entry. Routes through the FRB
  /// upsert; the resulting `KnownHostsChanged` bus event refreshes
  /// the stream.
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
        'KnownHostsMutator.upsert failed: $e',
        name: 'KnownHostsMutator',
        level: LogLevel.warn,
      );
    }
  }

  /// Remove a single known host entry. `hostPort` is the canonical
  /// `host:port` key the stream emits; the helper splits it back
  /// into the FRB DAO's `(host, port)` shape.
  Future<void> removeHost(String hostPort) async {
    if (hostPort.isEmpty) return;
    final (host, port) = splitKnownHostKey(hostPort);
    try {
      await rust_db.dbKnownHostsDeleteByHostPort(host: host, port: port);
    } catch (e) {
      AppLogger.instance.log(
        'KnownHostsMutator.removeHost failed: $e',
        name: 'KnownHostsMutator',
        level: LogLevel.warn,
      );
    }
  }

  /// Remove multiple known host entries. Rust publishes one
  /// `KnownHostsChanged` per row but the Dart stream coalesces
  /// re-fetches inside one microtask so the workspace re-renders
  /// once per burst, not per delete.
  Future<void> removeMultiple(Set<String> hostPorts) async {
    for (final hp in hostPorts) {
      await removeHost(hp);
    }
  }

  /// Remove all known host entries.
  Future<void> clearAll() async {
    try {
      await rust_db.dbKnownHostsClearAll();
    } catch (e) {
      AppLogger.instance.log(
        'KnownHostsMutator.clearAll failed: $e',
        name: 'KnownHostsMutator',
        level: LogLevel.warn,
      );
    }
  }

  /// Import entries from a known_hosts file at `path`. The Rust I/O
  /// keeps the raw bytes out of the Dart heap on the way to the
  /// parser, so a curl-piped `~/.ssh/known_hosts` import never
  /// materialises in the FRB layer twice.
  ///
  /// Returns the number of new entries added (existing hosts are
  /// skipped).
  Future<int> importFromFile(String path) async {
    try {
      final summary = await rust_db.dbKnownHostsImportFromPath(
        path: path,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (summary.added > 0) {
        AppLogger.instance.log(
          'Imported ${summary.added} known hosts',
          name: 'KnownHostsMutator',
        );
      }
      if (summary.skippedHashed > 0) {
        AppLogger.instance.log(
          'Skipped ${summary.skippedHashed} hashed known_hosts entries',
          name: 'KnownHostsMutator',
          level: LogLevel.warn,
        );
      }
      return summary.added;
    } catch (e) {
      AppLogger.instance.log(
        'KnownHostsMutator.importFromFile failed: $e',
        name: 'KnownHostsMutator',
        level: LogLevel.warn,
      );
      return 0;
    }
  }

  /// Import entries from a multi-line known_hosts blob. Routes
  /// through the Rust importer
  /// (`lfs_core::known_hosts::import_from_string`) so the parser
  /// walk + per-line dedup + DB upserts run inside one task.
  /// Skipped hashed-hostname rows are surfaced via the warning log
  /// so the user knows their `HashKnownHosts yes` lines were not
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
          name: 'KnownHostsMutator',
        );
      }
      if (summary.skippedHashed > 0) {
        AppLogger.instance.log(
          'Skipped ${summary.skippedHashed} hashed known-hosts entries '
          '(HashKnownHosts) — we cannot reverse the HMAC-SHA1 hash back '
          'to a hostname for storage',
          name: 'KnownHostsMutator',
          level: LogLevel.warn,
        );
      }
      return summary.added.toInt();
    } catch (e) {
      AppLogger.instance.log(
        'KnownHostsMutator.importFromString failed: $e',
        name: 'KnownHostsMutator',
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
        'KnownHostsMutator.exportToString failed: $e',
        name: 'KnownHostsMutator',
        level: LogLevel.warn,
      );
      return '';
    }
  }
}

/// Process-singleton mutator handle. Stateless — every method
/// pass-throughs to FRB. Tests override the provider directly with
/// a fake mutator subclass when they need to assert call counts or
/// seed responses.
/// Split a `host:port` stream key back into its `(host, port)` parts,
/// the inverse of the `'${e.host}:${e.port}'` key the known-hosts
/// stream builds. Splits on the LAST colon so an IPv6 host — whose
/// address itself embeds colons (`::1` → key `::1:2222`) — keeps its
/// address intact instead of collapsing to an empty host (the bug
/// that made IPv6 known-host rows un-deletable). A key whose trailing
/// segment isn't a number (no port appended) is treated as a bare
/// host on the default port 22.
(String host, int port) splitKnownHostKey(String hostPort) {
  final lastColon = hostPort.lastIndexOf(':');
  if (lastColon <= 0) return (hostPort, 22);
  final port = int.tryParse(hostPort.substring(lastColon + 1));
  if (port == null) return (hostPort, 22);
  return (hostPort.substring(0, lastColon), port);
}

final knownHostsMutatorProvider = Provider<KnownHostsMutator>(
  (ref) => const KnownHostsMutator(),
);

/// Fetch the current known-hosts listing from the Rust DB. All
/// failure modes degrade to an empty map — the known-hosts manager
/// stays usable on pre-FRB / DB-missing / locked-tier reads.
Future<Map<String, String>> _loadEntries() async {
  try {
    final entries = await rust_db.dbKnownHostsListAll();
    final next = <String, String>{};
    for (final e in entries) {
      next['${e.host}:${e.port}'] = '${e.keyType} ${e.keyBase64}';
    }
    AppLogger.instance.log(
      'Loaded ${next.length} known hosts',
      name: 'KnownHostsStream',
    );
    return next;
  } catch (e) {
    // Cold-start race: see `_loadSnapshot` in session_provider.dart.
    // The post-unlock cascade republishes `KnownHostsChanged` once
    // `db_init` lands, which re-enters this function with the DB
    // ready — degrade to empty without surfacing it as an error.
    if (e.toString().contains('db not initialized')) {
      return const <String, String>{};
    }
    AppLogger.instance.log(
      'Failed to load known hosts',
      name: 'KnownHostsStream',
      error: e,
      level: LogLevel.warn,
    );
    return const <String, String>{};
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
