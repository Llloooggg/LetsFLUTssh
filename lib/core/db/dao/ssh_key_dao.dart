import '../../../utils/logger.dart';
import '../database.dart';

/// Data access for [SshKeys] table.
class SshKeyDao {
  final AppDatabase _db;

  SshKeyDao(this._db);

  Future<List<DbSshKey>> getAll() => _db.select(_db.sshKeys).get();

  Future<DbSshKey?> getById(String id) => (_db.select(
    _db.sshKeys,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(SshKeysCompanion key) async {
    await _db.into(_db.sshKeys).insert(key);
    AppLogger.instance.log(
      'Inserted SSH key ${key.id.value}',
      name: 'SshKeyDao',
    );
  }

  Future<bool> update(SshKeysCompanion key) async {
    final count = await (_db.update(
      _db.sshKeys,
    )..where((t) => t.id.equals(key.id.value))).write(key);
    return count > 0;
  }

  Future<int> deleteById(String id) async {
    final count = await (_db.delete(
      _db.sshKeys,
    )..where((t) => t.id.equals(id))).go();
    AppLogger.instance.log(
      'Deleted SSH key $id (rows: $count)',
      name: 'SshKeyDao',
    );
    return count;
  }
}
