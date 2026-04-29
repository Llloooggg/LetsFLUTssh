import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/wipe.dart' as rust_wipe;
import '../../src/rust/api/wipe_keychain.dart' as rust_wipe_kc;
import '../../utils/logger.dart';

/// Report returned by [WipeAllService.wipeAll]. Callers log it and
/// surface failures via the UI; partial failure is tolerated — the
/// service keeps going through the rest of the artefacts so one stuck
/// file never blocks the wipe.
class WipeReport {
  final List<String> deletedFiles;
  final List<String> failedFiles;
  final bool keychainPurged;
  final bool nativeVaultCleared;
  final bool biometricOverlayCleared;

  const WipeReport({
    this.deletedFiles = const [],
    this.failedFiles = const [],
    this.keychainPurged = false,
    this.nativeVaultCleared = false,
    this.biometricOverlayCleared = false,
  });

  bool get hasFailures => failedFiles.isNotEmpty;
}

/// Single orchestrator for "wipe every piece of app state this install
/// holds, across every tier, so the next launch starts from a clean
/// slate".
///
/// Three consumers share this service:
///
/// * Settings → Reset all data (user-initiated; double-confirmed).
/// * DbCorruptDialog (automatic on failed cipher-under-tier probe).
/// * TierResetDialog (automatic when the resolved tier no longer
///   matches the on-disk artefact shape).
///
/// **File-half lives Rust-side** in `lfs_core::security::wipe`: the
/// canonical [`MANAGED_FILES`] / [`ORPHAN_PROBE_FILES`] catalogue,
/// the `.wipe-pending` crash-marker write/clear cycle, the per-file
/// best-effort delete, and the `logs/` sweep. Crash safety: the Rust
/// sweep writes the marker before any delete and clears it only
/// after every step finishes. The next launch reads
/// [hasPendingWipe] and re-runs the sweep idempotently.
///
/// Dart side keeps the platform-bound concerns: the keychain
/// (`flutter_secure_storage`) purge, the
/// `com.letsflutssh/hardware_vault` `MethodChannel` invocations, and
/// the optional per-session credential cache evict.
///
/// Intentionally *not* tied to the migration framework's `Artefact`
/// interface: wipe is a cross-cutting concern that touches files even
/// the migration framework does not track (logs, markers, keychain
/// aliases), so a stand-alone list keeps the cleanup total.
class WipeAllService {
  WipeAllService({
    Future<Directory> Function()? supportDirFactory,
    FlutterSecureStorage? keychain,
    MethodChannel? hardwareVaultChannel,
    bool purgeKeychain = true,
    Future<void> Function()? credentialCacheEvict,
  }) : _supportDir = supportDirFactory ?? getApplicationSupportDirectory,
       _keychain = keychain ?? const FlutterSecureStorage(),
       _hwChannel =
           hardwareVaultChannel ??
           const MethodChannel(_hardwareVaultChannelName),
       _purgeKeychain = purgeKeychain,
       _credentialCacheEvict = credentialCacheEvict;

  static const _hardwareVaultChannelName = 'com.letsflutssh/hardware_vault';

  final Future<Directory> Function() _supportDir;
  final FlutterSecureStorage _keychain;
  final MethodChannel _hwChannel;
  final bool _purgeKeychain;

  /// Optional hook that drops every cached per-session credential
  /// before the file sweep runs. The cache holds page-locked copies
  /// of per-session passwords / key bytes; a wipe that deletes the
  /// Sessions table on disk must also drop these, or a later
  /// `reconnect` against a now-gone session would still find
  /// credentials in memory. Nullable because tests and the
  /// startup-pending-wipe resumption path have no cache to flush.
  final Future<void> Function()? _credentialCacheEvict;

  /// True if a `.wipe-pending` marker is on disk — the previous run
  /// started a wipe that did not finish. Call sites check this on
  /// startup and re-run the service before `_initSecurity`.
  Future<bool> hasPendingWipe() async {
    try {
      final dir = await _supportDir();
      return rust_wipe.wipeHasPending(supportDir: dir.path);
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService.hasPendingWipe probe failed (assuming no marker): $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }

  /// True when **any security-bearing** managed artefact lives in the
  /// app-support dir. Used on startup to detect "install has prior
  /// state" when the current build also finds `config.security == null`.
  ///
  /// `config.json` and `migration_history.json` are excluded from the
  /// orphan probe — both are recreated as soon as the app initialises
  /// its provider graph, so counting them as state would trap the
  /// user in a reset-dialog loop. The probe list lives in
  /// `lfs_core::security::wipe::ORPHAN_PROBE_FILES`.
  Future<bool> hasAnyState() async {
    try {
      final dir = await _supportDir();
      return rust_wipe.wipeHasAnyState(supportDir: dir.path);
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService.hasAnyState probe failed: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }

  /// Walk every managed file + purge keychain + ask the hw-vault
  /// plugin to drop its secondary keys. Returns a [WipeReport] so
  /// callers can surface partial failures.
  Future<WipeReport> wipeAll() async {
    final dir = await _supportDir();

    // 0. Flush the per-session credential cache BEFORE any file
    //    deletion. The cache is process-RAM-only, so there is no
    //    crash-safety concern — if the wipe aborts after this step
    //    the user simply has to re-enter passwords on reconnect,
    //    same as a cold app start. Doing it first keeps the
    //    invariant "no cached credentials exist for sessions whose
    //    on-disk record is about to be deleted".
    try {
      final evict = _credentialCacheEvict;
      if (evict != null) {
        await evict();
      }
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: credential-cache evict threw: $e',
        name: 'WipeAllService',
      );
    }

    // 1. Files (Rust-side: marker write → managed-file delete →
    //    logs sweep → marker clear, all under one FRB hop). The
    //    Rust sweep also handles the `.wipe-pending` crash marker.
    final fileReport = await rust_wipe.wipeSweepFiles(supportDir: dir.path);
    final deleted = List<String>.from(fileReport.deletedFiles);
    final failed = List<String>.from(fileReport.failedFiles);
    for (final name in failed) {
      AppLogger.instance.log(
        'WipeAllService: failed to delete $name',
        name: 'WipeAllService',
      );
    }

    // 2. Native hw-vault: primary + biometric overlay. Swallow errors;
    //    a missing channel (desktop Linux, missing plugin) is a no-op.
    final nativeCleared = await _invokeNative('clear');
    final overlayCleared = await _invokeNative('clearBiometricPassword');

    // 3. OS secure storage (keychain / Credential Manager / keyring /
    //    EncryptedSharedPrefs depending on platform).
    final purged = _purgeKeychain ? await _purgeKeychainStore() : false;

    return WipeReport(
      deletedFiles: deleted,
      failedFiles: failed,
      keychainPurged: purged,
      nativeVaultCleared: nativeCleared,
      biometricOverlayCleared: overlayCleared,
    );
  }

  Future<bool> _invokeNative(String method) async {
    try {
      await _hwChannel.invokeMethod<bool>(method);
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: native $method skipped: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }

  /// Walk the canonical key list (versioned in Rust as
  /// `lfs_core::security::wipe_keychain::MANAGED_KEYS`) and ask
  /// the keychain plugin to drop each. Routes through the Rust
  /// actor by default — owns the audited key catalogue + a
  /// per-key outcome report; falls back to the inline
  /// `_keychain.deleteAll()` shape for flutter_test contexts
  /// that don't load the FRB native lib.
  ///
  /// Per-key outcomes are logged so a partial failure (e.g. one
  /// stuck Linux libsecret slot) is visible in a support trace
  /// without having to re-run the wipe.
  Future<bool> _purgeKeychainStore() async {
    try {
      final report = await rust_wipe_kc.wipeKeychainRun();
      for (final entry in report.entries) {
        if (entry.status != 'deleted') {
          AppLogger.instance.log(
            'WipeAllService: keychain key "${entry.key}" '
            '${entry.status}',
            name: 'WipeAllService',
          );
        }
      }
      return report.allSucceeded;
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService.keychainPurge FRB unreachable, '
        'falling back to deleteAll: $e',
        name: 'WipeAllService',
      );
    }
    try {
      await _keychain.deleteAll();
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: keychain purge skipped: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }
}
