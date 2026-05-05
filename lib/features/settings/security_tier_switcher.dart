import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/tier_transition_marker.dart' as rust_ttm;
import '../../utils/logger.dart';

/// Atomic tier-switch helper.
///
/// Enforces the always-rekey invariant — every tier transition, even
/// a modifier-only change, generates a fresh random 32-byte DB key
/// and runs the rekey through `lfs_core`'s `PRAGMA rekey`. A
/// previously-leaked wrapper key cannot re-decrypt pages after the
/// switch.
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
/// File-format ownership for the marker lives Rust-side in
/// `lfs_core::security::tier_transition_marker`. This Dart class
/// keeps the orchestration order + the per-tier callbacks + the DB
/// rekey hook; the marker I/O delegates straight to the
/// `tier_transition_marker_*` FRB shims.
class SecurityTierSwitcher {
  final Future<String> Function() _supportDir;
  final Uint8List Function() _keyFactory;
  final Future<void> Function(Uint8List) _rekey;

  SecurityTierSwitcher({
    Future<String> Function()? supportDirFactory,
    Uint8List Function()? keyFactory,
    Future<void> Function(Uint8List)? rekey,
  }) : _supportDir = supportDirFactory ?? _defaultSupportDir,
       _keyFactory = keyFactory ?? _defaultRandomKey,
       _rekey = rekey ?? _defaultRekey;

  /// Default rekey hook — re-encrypts `letsflutssh.db` under `newKey`
  /// via the FRB `db_rekey` adapter.
  static Future<void> _defaultRekey(Uint8List newKey) =>
      rust_app.dbRekey(newKey: List<int>.from(newKey));

  static Future<String> _defaultSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
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
      final dir = await _supportDir();
      return rust_ttm.tierTransitionMarkerRead(supportDir: dir);
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
      final dir = await _supportDir();
      rust_ttm.tierTransitionMarkerClear(supportDir: dir);
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
    required String targetMarkerPayload,
    required Future<void> Function(Uint8List newKey) applyWrapper,
    required Future<void> Function(Uint8List newKey) persistConfig,
    required Future<void> Function() clearPrevious,
  }) async {
    final newKey = _keyFactory();

    // 1 + 2. Write marker.
    final dir = await _supportDir();
    rust_ttm.tierTransitionMarkerWrite(
      supportDir: dir,
      payload: targetMarkerPayload,
    );

    // 3. Atomic rekey. On failure the DB is still under the old key
    //    and the marker points at the unfinished target — startup
    //    will notice and roll back.
    try {
      await _rekey(newKey);
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch rekey failed: $e',
        name: 'SecurityTierSwitcher',
      );
      rethrow;
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

  /// SecretRef variant of [switchTier]. Identical orchestration but
  /// the new DB key is provided indirectly through a SecretStore id:
  /// the new bytes never land on the Dart heap. Caller stages the
  /// secret upstream (typically `cryptoAesGcmRandomKeyToSecret`),
  /// hands the id here, the switcher routes it through
  /// `dbRekeyFromSecret` for the SQLCipher rekey, and the wrapper /
  /// persistConfig callbacks receive the same id so they can run
  /// their own SecretRef-aware writes (`keychain_write_from_secret`
  /// / `hardware_tier_vault_store_from_secret` / `setFromSecret`).
  ///
  /// SecretStore entry survives the rekey + wrappers — `db_rekey_from_secret`
  /// uses `secrets_get`, not `take`. Caller is responsible for
  /// dropping the entry once every downstream consumer has had its
  /// turn (typical shape: `_injectDatabase(secretId: ...)` →
  /// `dbInitFromSecret` → `secrets_take`).
  Future<void> switchTierFromSecret({
    required String secretId,
    required String targetMarkerPayload,
    required Future<void> Function(String secretId) applyWrapperFromSecret,
    required Future<void> Function(String secretId) persistConfigFromSecret,
    required Future<void> Function() clearPrevious,
  }) async {
    // 1 + 2. Write marker.
    final dir = await _supportDir();
    rust_ttm.tierTransitionMarkerWrite(
      supportDir: dir,
      payload: targetMarkerPayload,
    );

    // 3. Atomic rekey via SecretRef. SecretStore entry survives —
    //    `db_rekey_from_secret` uses `secrets_get`, not `take`.
    try {
      await rust_app.dbRekeyFromSecret(secretId: secretId);
    } catch (e) {
      AppLogger.instance.log(
        'Tier switch rekey (SecretRef) failed: $e',
        name: 'SecurityTierSwitcher',
      );
      rethrow;
    }

    // 4. Wrap the new key in the target tier's vault.
    await applyWrapperFromSecret(secretId);

    // 5. Persist the new config.
    await persistConfigFromSecret(secretId);

    // 6. Drop the old tier's state.
    await clearPrevious();

    // 7. Marker cleared last — its absence is the "all good"
    //    signal the next startup relies on.
    await clearMarker();
  }
}

/// Mint a unique SecretStore id for tier-switch DB-key staging.
String mintTierSwitchSecretId() => 'tier-switch.dbkey.${const Uuid().v4()}';
