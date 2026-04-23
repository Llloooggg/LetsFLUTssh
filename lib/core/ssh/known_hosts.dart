import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../utils/logger.dart';
import '../db/database.dart';

/// TOFU (Trust On First Use) host key verification backed by drift database.
///
/// Keeps the same public API as the old file-based manager. Call [setDatabase]
/// before [load] — without a database, all reads return empty data and writes
/// are no-ops.
class KnownHostsManager {
  AppDatabase? _db;

  final Map<String, String> _hosts = {};

  /// Read-only view of all known host entries.
  ///
  /// Keys are `host:port`, values are `keytype base64key`.
  Map<String, String> get entries => Map.unmodifiable(_hosts);

  /// Number of known hosts.
  int get count => _hosts.length;

  /// Inject the opened database. Replaces the old `setEncryptionKey()`.
  void setDatabase(AppDatabase db) {
    _db = db;
  }

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
    final db = _db;
    if (db == null) return;

    try {
      final entries = await db.knownHostDao.getAll();
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
    final db = _db;
    if (db != null) {
      await db.knownHostDao.insert(
        KnownHostsCompanion.insert(
          host: host,
          port: Value(port),
          keyType: keyType,
          keyBase64: keyBase64,
          addedAt: DateTime.now(),
        ),
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
    final db = _db;
    if (db != null) {
      await db.knownHostDao.deleteByHostPort(host, port);
      await db.knownHostDao.insert(
        KnownHostsCompanion.insert(
          host: host,
          port: Value(port),
          keyType: keyType,
          keyBase64: keyBase64,
          addedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Remove a single known host entry.
  Future<void> removeHost(String hostPort) => _serializeWrite(() async {
    await load();
    if (_hosts.remove(hostPort) != null) {
      final db = _db;
      if (db != null) {
        final parts = hostPort.split(':');
        final host = parts[0];
        final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;
        await db.knownHostDao.deleteByHostPort(host, port);
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
        final db = _db;
        if (db != null) {
          for (final hp in hostPorts) {
            final parts = hp.split(':');
            final host = parts[0];
            final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;
            await db.knownHostDao.deleteByHostPort(host, port);
          }
        }
      });

  /// Remove all known host entries.
  Future<void> clearAll() => _serializeWrite(() async {
    await load();
    if (_hosts.isEmpty) return;
    _hosts.clear();
    await _db?.knownHostDao.clearAll();
    AppLogger.instance.log('Cleared all known hosts', name: 'KnownHosts');
  });

  /// Import entries from an OpenSSH-format known_hosts file.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    final content = await file.readAsString();
    return importFromString(content);
  }

  /// Import entries from an OpenSSH-format known_hosts string.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromString(String content) => _serializeWrite(() async {
    await load();
    final db = _db;
    var added = 0;
    for (final line in content.split('\n')) {
      final entry = _parseLine(line);
      if (entry == null || _hosts.containsKey(entry.hostPort)) continue;

      _hosts[entry.hostPort] = entry.keyString;
      if (db != null) await _persistEntry(db, entry);
      added++;
    }
    if (added > 0) {
      AppLogger.instance.log(
        'Imported $added known hosts from string',
        name: 'KnownHosts',
      );
    }
    return added;
  });

  Future<void> _persistEntry(AppDatabase db, _ParsedHostEntry entry) async {
    final hpParts = entry.hostPort.split(':');
    final host = hpParts[0];
    final port = hpParts.length > 1 ? int.tryParse(hpParts[1]) ?? 22 : 22;
    await db.knownHostDao.insert(
      KnownHostsCompanion.insert(
        host: host,
        port: Value(port),
        keyType: entry.keyType,
        keyBase64: entry.keyBase64,
        addedAt: DateTime.now(),
      ),
    );
  }

  /// Export all entries to OpenSSH known_hosts format.
  /// Export all known hosts to OpenSSH format.
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
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(keyBytes));
    return 'SHA256:${base64Encode(hash)}';
  }

  String _fingerprint(List<int> keyBytes) => fingerprint(keyBytes);

  static _ParsedHostEntry? _parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = trimmed.split(' ');
    if (parts.length < 3) return null;
    return _ParsedHostEntry(
      hostPort: parts[0],
      keyType: parts[1],
      keyBase64: parts[2],
      keyString: '${parts[1]} ${parts[2]}',
    );
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
