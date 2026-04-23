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
}
