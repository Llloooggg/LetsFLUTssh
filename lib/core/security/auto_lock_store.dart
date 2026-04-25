import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';

/// Persistence shim for the auto-lock idle timeout.
///
/// Reads/writes through `lfs_core.db` (the Rust-owned sqlite handle).
/// The setting lives in the encrypted DB instead of `config.json`
/// because it is a security control — an attacker with disk access
/// could otherwise disable auto-lock by editing a plaintext file.
///
/// The store is unusable before the Rust DB is unlocked
/// (`ensureRustDbOpen` runs inside `SecurityInitController`); until
/// then, FRB raises "db not initialized" and we surface that as 0
/// (auto-lock disabled) so the first frame after unlock does not
/// auto-lock the user out of their own session.
class AutoLockStore {
  /// Returns the persisted timeout in minutes, or `0` when the DB
  /// isn't available yet (locked) or no value has been written.
  Future<int> load() async {
    try {
      final row = await rust_db.dbAppConfigsGet();
      return row?.autoLockMinutes ?? 0;
    } catch (e) {
      AppLogger.instance.log(
        'autoLockMinutes load failed (DB not unlocked?): $e',
        name: 'AutoLockStore',
        level: LogLevel.warn,
      );
      return 0;
    }
  }

  /// Persist [minutes] (`0` disables auto-lock). Reads the row first
  /// so we never clobber the JSON `data` blob that ConfigStore-style
  /// future writes might park here. Writes are silently dropped if
  /// the DB is locked — same contract as [load].
  Future<void> save(int minutes) async {
    try {
      final existing = await rust_db.dbAppConfigsGet();
      await rust_db.dbAppConfigsUpsert(
        row: rust_db.DbAppConfig(
          data: existing?.data ?? '{}',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          autoLockMinutes: minutes,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'autoLockMinutes save failed (DB not unlocked?): $e',
        name: 'AutoLockStore',
        level: LogLevel.warn,
      );
    }
  }
}
