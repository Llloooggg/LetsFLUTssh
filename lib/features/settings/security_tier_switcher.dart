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
///
/// SecretRef shape: the DB key is staged in the Rust-side
/// `SecretStore` upstream (typically `cryptoAesGcmRandomKeyToSecret`)
/// and the caller hands the id in. The bytes never land on the Dart
/// heap; `dbRekeyFromSecret` uses `secrets_get` so the SecretStore
/// entry survives the rekey for downstream consumers (the wrapper /
/// persistConfig callbacks receive the same id and run their own
/// SecretRef-aware writes — `keychain_write_from_secret` /
/// `hardware_tier_vault_store_from_secret` / `setFromSecret`).
/// Caller drops the entry once every consumer has had its turn
/// (typical shape: `_injectDatabase(secretId: ...)` →
/// `dbInitFromSecret` → `secrets_take`).
class SecurityTierSwitcher {
  final Future<void> Function(String secretId) _rekeyFromSecret;

  SecurityTierSwitcher({
    Future<void> Function(String secretId)? rekeyFromSecret,
  }) : _rekeyFromSecret = rekeyFromSecret ?? _defaultRekeyFromSecret;

  /// Default rekey hook — re-encrypts `letsflutssh.db` under the
  /// SecretStore-staged DB key via the FRB `db_rekey_from_secret`
  /// adapter. Constructor-injectable so unit tests can drive the
  /// orchestration shape without booting the FRB native bridge.
  static Future<void> _defaultRekeyFromSecret(String secretId) =>
      rust_app.dbRekeyFromSecret(secretId: secretId);

  /// Return the pending-marker payload if the last startup left one
  /// behind, else null. Caller consults this before inferring the
  /// unlock tier — a pending marker means the DB is probably
  /// encrypted under the target config's key, not the source's.
  Future<String?> readPendingMarker() async {
    try {
      return rust_ttm.tierTransitionMarkerRead();
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
      rust_ttm.tierTransitionMarkerClear();
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
  ///   1. Caller stages a fresh DB key into the Rust SecretStore
  ///      (typically `cryptoAesGcmRandomKeyToSecret`) and hands the
  ///      `secretId` in.
  ///   2. Write the pending-transition marker with
  ///      [targetMarkerPayload].
  ///   3. Rekey the DB via the SecretRef (atomic PRAGMA rekey).
  ///   4. [applyWrapperFromSecret] — target tier stores the key in
  ///      its vault / derives `credentials.kdf` / whatever.
  ///   5. [persistConfigFromSecret] — writes `security_tier` to
  ///      config.json and updates the security provider.
  ///   6. [clearPrevious] — target deletes the *old* tier's state
  ///      (previous keychain entry, previous credentials.kdf, etc.).
  ///   7. Delete the marker.
  ///
  /// If any step before 7 throws, the marker stays on disk. The next
  /// startup can either complete or roll back the pending transition.
  Future<void> switchTierFromSecret({
    required String secretId,
    required String targetMarkerPayload,
    required Future<void> Function(String secretId) applyWrapperFromSecret,
    required Future<void> Function(String secretId) persistConfigFromSecret,
    required Future<void> Function() clearPrevious,
  }) async {
    // 1 + 2. Write marker.
    rust_ttm.tierTransitionMarkerWrite(payload: targetMarkerPayload);

    // 3. Atomic rekey via SecretRef. SecretStore entry survives —
    //    `db_rekey_from_secret` uses `secrets_get`, not `take`.
    try {
      await _rekeyFromSecret(secretId);
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
