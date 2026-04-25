import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';

/// TOFU (Trust On First Use) host key verification backed by
/// `lfs_core.db`. Engine behind the DAO is Rust + rusqlite; the
/// on-disk row layout matches the `KnownHosts` schema drift used
/// to own.
///
/// In-memory cache + serialisation invariants are preserved verbatim
/// from the drift era. Pre-unlock and inside the unit-test runner
/// the FRB calls raise synchronously; every entry point catches and
/// degrades to "no DB attached" semantics so a race between unlock
/// and the first verify cannot crash the connect path.
class KnownHostsManager {
  final Map<String, String> _hosts = {};

  /// Drop the in-memory cache so the next [load] re-reads. Called
  /// from the unlock handshake — replaces the drift-era
  /// `setDatabase` injection now that the FRB DAO resolves the live
  /// connection off `AppState`.
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

  /// Serialises mutating database operations so that two concurrent
  /// `clearAll` / `importFromString` / `removeMultiple` callers cannot
  /// interleave and leave the in-memory cache and the database in
  /// inconsistent states (e.g. one clear running while another is mid-flight).
  Future<void> _writeLock = Future.value();

  Future<T> _serializeWrite<T>(Future<T> Function() body) {
    final pending = _writeLock.then((_) => body());
    _writeLock = pending.then((_) {}, onError: (_) {});
    return pending;
  }

  /// True once [_doLoad] has completed successfully at least once. Used to
  /// distinguish "load already done" from "load attempted but failed and
  /// should be retried on the next call".
  bool _loaded = false;

  /// Callback invoked when an unknown host is encountered.
  /// Return true to accept the key, false to reject.
  /// If null, unknown hosts are auto-accepted (TOFU).
  Future<bool> Function(
    String host,
    int port,
    String keyType,
    String fingerprint,
  )?
  onUnknownHost;

  /// Callback invoked when a known host's key has changed (potential MITM).
  /// Return true to accept the new key, false to reject.
  /// If null, changed keys are always rejected.
  Future<bool> Function(
    String host,
    int port,
    String keyType,
    String fingerprint,
  )?
  onHostKeyChanged;

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

  /// Verify host key. Returns true if accepted.
  ///
  /// Serialised against every other mutator via `_serializeWrite` so a
  /// user-initiated `clearAll` / `removeMultiple` / `importFromString`
  /// cannot interleave between the cache read and the follow-on
  /// `_addHost` / `_updateHost`. Prior shape: reader path could call
  /// `onUnknownHost` (long-running user prompt), user taps Accept, the
  /// pending `clearAll` — which was queued while the prompt was open
  /// — wiped `_hosts` and the DB, then `_addHost` re-wrote the row
  /// the user had just told us to forget.
  ///
  /// Verifies are rare and short; full serialisation does not hurt
  /// throughput and keeps the invariant trivial.
  Future<bool> verify(
    String host,
    int port,
    String keyType,
    List<int> keyBytes,
  ) => _serializeWrite(() => _verifyInner(host, port, keyType, keyBytes));

  Future<bool> _verifyInner(
    String host,
    int port,
    String keyType,
    List<int> keyBytes,
  ) async {
    await load();
    final hostPort = '$host:$port';
    final keyData = base64Encode(keyBytes);
    final keyString = '$keyType $keyData';
    final existing = _hosts[hostPort];

    if (existing != null) {
      if (existing == keyString) {
        AppLogger.instance.log(
          'Host key verified: $hostPort',
          name: 'KnownHosts',
        );
        return true;
      }
      AppLogger.instance.log(
        'Host key CHANGED for $hostPort ($keyType) — potential MITM',
        name: 'KnownHosts',
      );
      if (onHostKeyChanged != null) {
        final fp = _fingerprint(keyBytes);
        final accepted = await onHostKeyChanged!(host, port, keyType, fp);
        if (accepted) {
          AppLogger.instance.log(
            'Changed host key accepted: $hostPort',
            name: 'KnownHosts',
          );
          await _updateHost(host, port, keyType, keyData);
          return true;
        }
      }
      AppLogger.instance.log(
        'Changed host key rejected: $hostPort',
        name: 'KnownHosts',
      );
      return false;
    }

    // Unknown host
    AppLogger.instance.log(
      'Unknown host: $hostPort ($keyType)',
      name: 'KnownHosts',
    );
    if (onUnknownHost != null) {
      final fp = _fingerprint(keyBytes);
      final accepted = await onUnknownHost!(host, port, keyType, fp);
      if (accepted) {
        AppLogger.instance.log(
          'Unknown host accepted (TOFU): $hostPort',
          name: 'KnownHosts',
        );
        await _addHost(host, port, keyType, keyData);
        return true;
      }
      AppLogger.instance.log(
        'Unknown host rejected: $hostPort',
        name: 'KnownHosts',
      );
      return false;
    }

    AppLogger.instance.log(
      'Unknown host rejected (no callback): $hostPort',
      name: 'KnownHosts',
    );
    return false;
  }

  Future<void> _addHost(
    String host,
    int port,
    String keyType,
    String keyBase64,
  ) async {
    _hosts['$host:$port'] = '$keyType $keyBase64';
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
        '_addHost FRB write failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> _updateHost(
    String host,
    int port,
    String keyType,
    String keyBase64,
  ) async {
    _hosts['$host:$port'] = '$keyType $keyBase64';
    try {
      // Rust's upsert handles ON CONFLICT(host, port) — no separate
      // delete-then-insert dance needed.
      await rust_db.dbKnownHostsUpsertByHostPort(
        host: host,
        port: port,
        keyType: keyType,
        keyBase64: keyBase64,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.instance.log(
        '_updateHost FRB write failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  /// Remove a single known host entry.
  Future<void> removeHost(String hostPort) => _serializeWrite(() async {
    await load();
    if (_hosts.remove(hostPort) != null) {
      final parts = hostPort.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;
      try {
        await rust_db.dbKnownHostsDeleteByHostPort(host: host, port: port);
      } catch (e) {
        AppLogger.instance.log(
          'removeHost FRB delete failed: $e',
          name: 'KnownHosts',
          level: LogLevel.warn,
        );
      }
      AppLogger.instance.log(
        'Removed known host: $hostPort',
        name: 'KnownHosts',
      );
    }
  });

  /// Remove multiple known host entries.
  Future<void> removeMultiple(Set<String> hostPorts) =>
      _serializeWrite(() async {
        await load();
        for (final hp in hostPorts) {
          _hosts.remove(hp);
        }
        for (final hp in hostPorts) {
          final parts = hp.split(':');
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
      });

  /// Remove all known host entries.
  Future<void> clearAll() => _serializeWrite(() async {
    await load();
    if (_hosts.isEmpty) return;
    _hosts.clear();
    try {
      await rust_db.dbKnownHostsClearAll();
    } catch (e) {
      AppLogger.instance.log(
        'clearAll FRB write failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
    AppLogger.instance.log('Cleared all known hosts', name: 'KnownHosts');
  });

  /// Import entries from a LetsFLUTssh-format known_hosts file.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    return importFromString(content);
  }

  /// Import entries from a LetsFLUTssh-format known_hosts string.
  ///
  /// Format is space-separated `host:port keytype base64key`, one entry
  /// per line. Blank lines and `#`-prefixed comments are skipped. This
  /// is NOT the OpenSSH `~/.ssh/known_hosts` wire format — real
  /// OpenSSH uses `host` (port 22) or `[host]:port` for non-default
  /// ports, supports hashed hostnames, comma-separated host aliases,
  /// and `@cert-authority` / `@revoked` markers, none of which this
  /// parser understands. The format exists purely for round-tripping
  /// through our own `.lfs` archive export; paired with
  /// [exportToString] below.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromString(String content) => _serializeWrite(() async {
    await load();
    var added = 0;
    var skippedHashed = 0;
    for (final line in content.split('\n')) {
      final entries = _parseLine(line);
      if (entries.isEmpty) {
        if (_isHashedHostsLine(line)) skippedHashed++;
        continue;
      }
      for (final entry in entries) {
        if (_hosts.containsKey(entry.hostPort)) continue;
        _hosts[entry.hostPort] = entry.keyString;
        await _persistEntry(entry);
        added++;
      }
    }
    if (added > 0) {
      AppLogger.instance.log(
        'Imported $added known hosts from string',
        name: 'KnownHosts',
      );
    }
    if (skippedHashed > 0) {
      AppLogger.instance.log(
        'Skipped $skippedHashed hashed known-hosts entries (HashKnownHosts) — '
        'we cannot reverse the HMAC-SHA1 hash back to a hostname for storage',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
    return added;
  });

  static bool _isHashedHostsLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return false;
    final firstSpace = trimmed.indexOf(RegExp(r'\s'));
    if (firstSpace < 0) return false;
    return trimmed.substring(0, firstSpace).startsWith('|1|');
  }

  Future<void> _persistEntry(_ParsedHostEntry entry) async {
    final hpParts = entry.hostPort.split(':');
    final host = hpParts[0];
    final port = hpParts.length > 1 ? int.tryParse(hpParts[1]) ?? 22 : 22;
    try {
      await rust_db.dbKnownHostsUpsertByHostPort(
        host: host,
        port: port,
        keyType: entry.keyType,
        keyBase64: entry.keyBase64,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.instance.log(
        '_persistEntry FRB write failed for ${entry.hostPort}: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  /// Export all entries to the LetsFLUTssh known_hosts wire format.
  ///
  /// Emits `host:port keytype base64key`, one entry per line —
  /// symmetric with [importFromString] above. This is NOT real
  /// OpenSSH format (that would be `host` / `[host]:port` with
  /// brackets for non-default ports); the format is private to the
  /// `.lfs` archive round-trip so the exporter stays a single
  /// trivial line.
  ///
  /// Ensures the in-memory cache is hydrated first: callers that export
  /// before any `verify()` / known-hosts-UI interaction in this session
  /// would otherwise see an empty string even though the encrypted DB
  /// has entries (the lazy `load()` only fires on first access). Missing
  /// this call was the visible bug — archives shipped without the user's
  /// TOFU history even though the checkbox was on.
  Future<String> exportToString() async {
    await load();
    final sb = StringBuffer();
    for (final entry in _hosts.entries) {
      sb.writeln('${entry.key} ${entry.value}');
    }
    return sb.toString();
  }

  /// Compute SHA256 fingerprint of host key bytes.
  static String fingerprint(List<int> keyBytes) {
    final hash = sha256.convert(keyBytes).bytes;
    return 'SHA256:${base64Encode(hash)}';
  }

  String _fingerprint(List<int> keyBytes) => fingerprint(keyBytes);

  /// Parse a single line into zero or more host entries.
  ///
  /// Accepts both formats:
  ///
  /// - **LetsFLUTssh internal** (`host:port keytype base64key`) —
  ///   what `exportToString` emits for `.lfs` archive round-trips.
  /// - **OpenSSH `~/.ssh/known_hosts`** — the file the user has
  ///   built up over years of `ssh` use. Supports:
  ///   - bare hostname (`example.com keytype base64`) → port 22
  ///   - bracketed `[host]:port` for non-default ports
  ///   - comma-separated multi-host (`example.com,1.2.3.4,...`)
  ///   - bracketed IPv6 (`[::1]:22`, `[::1]`)
  ///   - leading `@cert-authority` / `@revoked` markers — skipped
  ///     (we don't ship a cert-authority chain today)
  ///   - hashed hostnames (`|1|salt|hash`) — skipped, the HMAC-SHA1
  ///     hash can't be reversed back to a real hostname so we have
  ///     nothing to match against on subsequent connects. Counted
  ///     and surfaced via the importer's "skipped N hashed entries"
  ///     warning so the user knows their `HashKnownHosts yes` rows
  ///     were not silently swallowed.
  ///
  /// Returns one entry per resolved host:port pair. A single
  /// OpenSSH multi-host line can yield several entries.
  static List<_ParsedHostEntry> _parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return const [];
    // OpenSSH @-markers (cert-authority, revoked) — drop the marker
    // and re-parse the rest. We don't currently honour
    // cert-authority semantics (no cert chain on connect) so the
    // safest read is "treat it like a normal entry"; @revoked
    // entries are still imported because the user clearly wanted
    // them on the file but won't have any effect on TOFU here.
    final parts = trimmed.split(RegExp(r'\s+'));
    var idx = 0;
    while (idx < parts.length && parts[idx].startsWith('@')) {
      idx++;
    }
    if (parts.length - idx < 3) return const [];
    final hostSpec = parts[idx];
    final keyType = parts[idx + 1];
    final keyBase64 = parts[idx + 2];

    if (hostSpec.startsWith('|1|')) {
      // Hashed entry — caller's _isHashedHostsLine surfaces a
      // separate "skipped N hashed entries" warning. Returning an
      // empty list here means the import loop counts it as skipped.
      return const [];
    }
    final keyString = '$keyType $keyBase64';
    final out = <_ParsedHostEntry>[];
    for (final spec in hostSpec.split(',')) {
      final hostPort = _normaliseHostSpec(spec);
      if (hostPort == null) continue;
      out.add(
        _ParsedHostEntry(
          hostPort: hostPort,
          keyType: keyType,
          keyBase64: keyBase64,
          keyString: keyString,
        ),
      );
    }
    return out;
  }

  /// Convert a single OpenSSH host-spec or LetsFLUTssh internal
  /// `host:port` into the canonical `host:port` shape the rest of
  /// the manager keys on. Returns null on malformed input.
  static String? _normaliseHostSpec(String spec) {
    final s = spec.trim();
    if (s.isEmpty) return null;
    // OpenSSH bracketed form: `[host]:port` or `[ipv6]` (no port)
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      if (close < 0) return null;
      final host = s.substring(1, close);
      if (host.isEmpty) return null;
      // Tail after `]` is either empty (port 22) or `:port`.
      final tail = s.substring(close + 1);
      if (tail.isEmpty) return '$host:22';
      if (!tail.startsWith(':')) return null;
      final port = int.tryParse(tail.substring(1));
      if (port == null || port < 1 || port > 65535) return null;
      return '$host:$port';
    }
    // Bare IPv6 without brackets is illegal in OpenSSH — assume
    // anything with multiple `:` is unbracketed IPv6 and drop it.
    final colonCount = s.split(':').length - 1;
    if (colonCount > 1) return null;
    if (colonCount == 1) {
      // `host:port` — internal format (or OpenSSH IPv4-with-explicit
      // port which OpenSSH itself does not emit but we accept).
      final parts = s.split(':');
      final host = parts[0];
      final port = int.tryParse(parts[1]);
      if (host.isEmpty || port == null || port < 1 || port > 65535) {
        return null;
      }
      return '$host:$port';
    }
    // Bare hostname — OpenSSH default port 22.
    return '$s:22';
  }
}

class _ParsedHostEntry {
  final String hostPort;
  final String keyType;
  final String keyBase64;
  final String keyString;

  const _ParsedHostEntry({
    required this.hostPort,
    required this.keyType,
    required this.keyBase64,
    required this.keyString,
  });
}
