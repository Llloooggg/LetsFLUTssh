import '../db/database.dart';
import '../../utils/logger.dart';

/// Persistence shim for the auto-lock idle timeout.
///
/// The setting lives in the encrypted DB instead of `config.json` because it
/// is a security control — an attacker with disk access could otherwise
/// disable auto-lock by editing a plaintext file. The store is unusable
/// before the DB is unlocked; until then, callers should treat the value
/// as `0` (auto-lock disabled).
class AutoLockStore {
  AppDatabase? _db;

  void setDatabase(AppDatabase db) {
    _db = db;
  }

  /// Returns the persisted timeout in minutes, or `0` when the DB isn't
  /// available yet (locked) or no value has been written.
  Future<int> load() async {
    final db = _db;
    if (db == null) return 0;
    return db.configDao.getAutoLockMinutes();
  }

  /// Persist [minutes] (`0` disables auto-lock). No-op when the DB isn't
  /// available — matches the read contract.
  Future<void> save(int minutes) async {
    final db = _db;
    if (db == null) {
      AppLogger.instance.log(
        'Skipped autoLockMinutes save — DB not unlocked',
        name: 'AutoLockStore',
      );
      return;
    }
    await db.configDao.setAutoLockMinutes(minutes);
  }
}
