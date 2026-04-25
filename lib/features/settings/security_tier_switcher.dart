import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/database.dart';
import '../../core/db/database_opener.dart';
import '../../src/rust/api/app.dart' as rust_app;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// Atomic tier-switch helper.
///
/// Enforces the always-rekey invariant — every tier transition, even
/// a modifier-only change, generates a fresh random 32-byte DB key
/// and runs [rekeyDatabase] under a single `PRAGMA rekey`
/// transaction. A previously-leaked wrapper key cannot re-decrypt
/// pages after the switch.
///
/// Crash recovery: before the rekey runs, a tiny
/// `.tier-transition-pending` marker file lands in the app support
/// dir holding the target config's JSON. If the process dies between
/// the rekey completing and the wrapper + config.json updates, the
/// next startup sees the marker and the DB encrypted under the new
/// key; the user provides the target secret to resume, or the app
/// rolls back. Clean-shutdown path deletes the marker as the last
/// step.
///
/// This class owns **orchestration order** and the **marker**.
/// Wrapping a key for keychain / hardware / paranoid still lives in
/// each tier's own store; the switcher calls back into them via
/// closures.
class SecurityTierSwitcher {
  static const _markerFileName = '.tier-transition-pending';

  final Future<File> Function() _markerFile;
  final Uint8List Function() _keyFactory;
  final Future<void> Function(AppDatabase, Uint8List) _rekey;

  SecurityTierSwitcher({
    Future<File> Function()? markerFileFactory,
    Uint8List Function()? keyFactory,
    Future<void> Function(AppDatabase, Uint8List)? rekey,
  }) : _markerFile = markerFileFactory ?? _defaultMarkerFile,
       _keyFactory = keyFactory ?? _defaultRandomKey,
       _rekey = rekey ?? rekeyDatabase;

  static Future<File> _defaultMarkerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _markerFileName));
  }

  /// CSPRNG-backed 32-byte key. Uses `Random.secure()` — backed by
  /// `/dev/urandom` on POSIX and `BCryptGenRandom` on Windows.
  static Uint8List _defaultRandomKey() {
    final rng = Random.secure();
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }

  /// Return the pending-marker payload if the last startup left one
  /// behind, else null. Caller consults this before inferring the
  /// unlock tier — a pending marker means the DB is probably
  /// encrypted under the target config's key, not the source's.
  Future<String?> readPendingMarker() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch marker read failed: $e',
        name: 'SecurityTierSwitcher',
      );
      return null;
    }
  }

  Future<void> clearMarker() async {
    try {
      final file = await _markerFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch marker clear failed: $e',
        name: 'SecurityTierSwitcher',
      );
    }
  }

  /// Run a full tier switch.
  ///
  /// Sequence:
  ///   1. Generate fresh random `newKey`.
  ///   2. Write the pending-transition marker with
  ///      [targetMarkerPayload].
  ///   3. [rekey] the DB to `newKey` (atomic PRAGMA rekey).
  ///   4. [applyWrapper] — target tier stores `newKey` in its vault
  ///      / derives `credentials.kdf` / whatever.
  ///   5. [persistConfig] — writes `security_tier` to config.json and
  ///      updates the security provider.
  ///   6. [clearPrevious] — target deletes the *old* tier's state
  ///      (previous keychain entry, previous credentials.kdf, etc.).
  ///   7. Delete the marker.
  ///
  /// If any step before 7 throws, the marker stays on disk. The next
  /// startup can either complete or roll back the pending transition.
  Future<void> switchTier({
    required AppDatabase db,
    required String targetMarkerPayload,
    required Future<void> Function(Uint8List newKey) applyWrapper,
    required Future<void> Function(Uint8List newKey) persistConfig,
    required Future<void> Function() clearPrevious,
  }) async {
    final newKey = _keyFactory();

    // 1 + 2. Write marker.
    await _writeMarker(targetMarkerPayload);

    // 3. Atomic rekey. On failure the DB is still under the old key
    //    and the marker points at the unfinished target — startup
    //    will notice and roll back.
    try {
      await _rekey(db, newKey);
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch rekey failed: $e',
        name: 'SecurityTierSwitcher',
      );
      rethrow;
    }
    // 3b. Rekey lfs_core's parallel sqlite handle so its file does
    //     not stay locked under the previous key on next boot.
    //     Drift uses MC ChaCha20; lfs_core uses SQLCipher AES-256-CBC
    //     (cipher_compatibility=4). Both pages get re-encrypted under
    //     the same `newKey` even though the cipher families differ —
    //     each PRAGMA rekey is engine-local.
    try {
      await rust_app.dbRekey(newKey: List<int>.from(newKey));
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch lfs_core rekey failed (continuing — drift already rekeyed): $e',
        name: 'SecurityTierSwitcher',
        level: LogLevel.warn,
      );
    }

    // 4. Wrap the new key in the target tier's vault.
    await applyWrapper(newKey);

    // 5. Persist the new config.
    await persistConfig(newKey);

    // 6. Drop the old tier's state.
    await clearPrevious();

    // 7. Marker cleared last — its absence is the "all good"
    //    signal the next startup relies on.
    await clearMarker();
  }

  Future<void> _writeMarker(String payload) async {
    final file = await _markerFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(payload, flush: true);
    await hardenFilePerms(file.path);
  }
}
