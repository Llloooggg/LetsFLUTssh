import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/recovery.dart' as rust_recovery;
import '../../src/rust/api/wipe.dart' as rust_wipe;
import '../../utils/logger.dart';
import 'terminal_scrubber.dart';

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
/// Dart side keeps two concerns: the optional per-session
/// credential cache evict (process-RAM only, must run before the
/// file sweep) and the terminal-scrollback scrub (Flutter-side
/// widget state). Everything else — db_close, file sweep,
/// keychain alias purge, per-platform hardware-vault primary +
/// biometric overlay clear — lives Rust-side inside the
/// `recovery::run_destructive_reset` orchestrator.
///
/// Intentionally *not* tied to the migration framework's `Artefact`
/// interface: wipe is a cross-cutting concern that touches files even
/// the migration framework does not track (logs, markers, keychain
/// aliases), so a stand-alone list keeps the cleanup total.
class WipeAllService {
  WipeAllService({
    Future<Directory> Function()? supportDirFactory,
    bool purgeKeychain = true,
    Future<void> Function()? credentialCacheEvict,
  }) : _supportDir = supportDirFactory ?? getApplicationSupportDirectory,
       _purgeKeychain = purgeKeychain,
       _credentialCacheEvict = credentialCacheEvict;

  final Future<Directory> Function() _supportDir;
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
    final sw = Stopwatch()..start();
    void mark(String phase) {
      AppLogger.instance.log(
        'wipe phase=$phase elapsed=${sw.elapsedMilliseconds}ms',
        name: 'WipeAllService',
      );
    }

    final dir = await _supportDir();
    mark('support_dir');

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
    mark('credential_evict');

    // 0.5. Scrub every active xterm scrollback. A reset that wipes
    //      the on-disk session record while leaving the user's
    //      recently-typed commands visible in an open terminal
    //      defeats the point — the buffer outlives the deletion
    //      until the tab itself is closed (which the wipe path
    //      does not force). AutoLockDetector already calls
    //      TerminalScrubber.scrubAll on lock; the wipe path was the
    //      missing peer.
    try {
      TerminalScrubber.instance.scrubAll();
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: terminal scrub threw: $e',
        name: 'WipeAllService',
      );
    }

    // 1. Composite destructive cascade through the Rust
    //    `recovery::run_destructive_reset` orchestrator. Bundles
    //    db_close + managed-file sweep + keychain alias purge +
    //    per-platform hardware-vault primary clear + biometric
    //    overlay clear into one transaction so the Dart side
    //    awaits a single FRB call.
    //
    //    Falls back to the per-call FRB shape on the keychain-only
    //    branch (`_purgeKeychain == false` — Settings "wipe but
    //    keep keychain entries" toggle) so the caller's opt-out is
    //    still honoured. In that path the keychain alias purge is
    //    skipped together with the hw-vault clear (the wrapped-key
    //    envelope file still gets removed by `wipeSweepFiles`; the
    //    persistent hardware key — Apple SE / AndroidKeyStore /
    //    Windows CNG — stays, matching the opt-out's "leave
    //    OS-bound secret material in place" intent).
    final List<String> deleted;
    final List<String> failed;
    final bool purged;
    final bool nativeCleared;
    final bool overlayCleared;
    if (_purgeKeychain) {
      final report = await rust_recovery.recoveryRunDestructiveReset(
        supportDir: dir.path,
      );
      deleted = List<String>.from(report.deletedFiles);
      failed = List<String>.from(report.failedFiles);
      purged = report.keychainPurgeSucceeded;
      nativeCleared = report.hwVaultCleared;
      overlayCleared = report.hwVaultBiometricCleared;
      mark('recovery_reset');
    } else {
      // Settings opt-out: caller wants the on-disk wipe without
      // touching OS-keychain aliases or hardware-bound persistent
      // keys. The file sweep still removes the wrapped-key
      // envelope; the persistent hardware key stays.
      final fileReport = await rust_wipe.wipeSweepFiles(supportDir: dir.path);
      deleted = List<String>.from(fileReport.deletedFiles);
      failed = List<String>.from(fileReport.failedFiles);
      purged = false;
      nativeCleared = false;
      overlayCleared = false;
      mark('sweep_files');
    }
    for (final name in failed) {
      AppLogger.instance.log(
        'WipeAllService: failed to delete $name',
        name: 'WipeAllService',
      );
    }
    AppLogger.instance.log(
      'WipeAllService: cascade outcome '
      'keychain_purged=$purged '
      'hw_vault_cleared=$nativeCleared '
      'hw_vault_biometric_cleared=$overlayCleared',
      name: 'WipeAllService',
    );

    return WipeReport(
      deletedFiles: deleted,
      failedFiles: failed,
      keychainPurged: purged,
      nativeVaultCleared: nativeCleared,
      biometricOverlayCleared: overlayCleared,
    );
  }
}
