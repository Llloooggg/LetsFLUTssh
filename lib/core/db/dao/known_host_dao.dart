import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [KnownHosts] table.
class KnownHostDao {
  final AppDatabase _db;

  KnownHostDao(this._db);

  Future<List<DbKnownHost>> getAll() => _db.select(_db.knownHosts).get();

  Future<DbKnownHost?> lookup(String host, int port) => (_db.select(
    _db.knownHosts,
  )..where((t) => t.host.equals(host) & t.port.equals(port))).getSingleOrNull();

  Future<void> insert(KnownHostsCompanion entry) async {
    await _db.into(_db.knownHosts).insert(entry);
    AppLogger.instance.log(
      'Added known host ${entry.host.value}:${entry.port.value}',
      name: 'KnownHostDao',
    );
  }

  Future<int> deleteById(int id) async {
    final count = await (_db.delete(
      _db.knownHosts,
    )..where((t) => t.id.equals(id))).go();
    return count;
  }

  Future<int> deleteByHostPort(String host, int port) async {
    final count = await (_db.delete(
      _db.knownHosts,
    )..where((t) => t.host.equals(host) & t.port.equals(port))).go();
    AppLogger.instance.log(
      'Removed known host $host:$port (rows: $count)',
      name: 'KnownHostDao',
    );
    return count;
  }

  Future<int> deleteMultiple(Set<int> ids) async {
    final count = await (_db.delete(
      _db.knownHosts,
    )..where((t) => t.id.isIn(ids))).go();
    AppLogger.instance.log(
      'Removed ${ids.length} known hosts (rows: $count)',
      name: 'KnownHostDao',
    );
    return count;
  }

  Future<int> clearAll() async {
    final count = await _db.delete(_db.knownHosts).go();
    AppLogger.instance.log(
      'Cleared all known hosts (rows: $count)',
      name: 'KnownHostDao',
    );
    return count;
  }

  /// Export all entries to OpenSSH known_hosts format.
  ///
  /// Format: `host:port keytype base64key` (one per line).
  Future<String> exportToString() async {
    final entries = await getAll();
    final buf = StringBuffer();
    for (final e in entries) {
      buf.writeln('${e.host}:${e.port} ${e.keyType} ${e.keyBase64}');
    }
    return buf.toString();
  }

  /// Import entries from OpenSSH known_hosts format string.
  ///
  /// Skips blank lines and entries that already exist.
  /// Returns the number of new entries added.
  Future<int> importFromString(String content) async {
    var added = 0;
    for (final line in LineSplitter.split(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(' ');
      if (parts.length < 3) continue;

      final hostPort = parts[0].split(':');
      final host = hostPort[0];
      final port = hostPort.length > 1 ? int.tryParse(hostPort[1]) ?? 22 : 22;
      final keyType = parts[1];
      final keyBase64 = parts[2];

      final existing = await lookup(host, port);
      if (existing != null) continue;

      await _db
          .into(_db.knownHosts)
          .insert(
            KnownHostsCompanion.insert(
              host: host,
              port: Value(port),
              keyType: keyType,
              keyBase64: keyBase64,
              addedAt: DateTime.now(),
            ),
          );
      added++;
    }
    AppLogger.instance.log('Imported $added known hosts', name: 'KnownHostDao');
    return added;
  }
}
