import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/hardware_tier_vault.dart' as rust_hwvault;
import '../../src/rust/api/wipe.dart' as rust_wipe;
import '../../src/rust/api/wipe_keychain.dart' as rust_wipe_kc;
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
/// Dart side keeps the platform-bound concerns: the keychain
/// purge (`lfs_os_security::secure_key_storage::delete` over the
/// canonical alias list — see `wipe_keychain.dart`), the
/// per-platform hw-vault clear via FRB into `lfs_os_security`,
/// and the optional per-session credential cache evict.
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
    mark('sweep_files');

    // 2. Native hw-vault: primary + biometric overlay via Rust
    //    (`lfs_os_security::hardware_tier_vault::*`). Swallow errors;
    //    on Linux without a TPM the dispatch returns Unavailable and
    //    the call is a no-op. Apple SE / Android Keystore / Windows
    //    CNG / Linux TPM2 all share the same FRB entry now, so wipe
    //    semantics are uniform across platforms.
    final nativeCleared = await _clearNativePrimary();
    final overlayCleared = await _clearNativeBiometricOverlay();
    mark('native_vault_clear');

    // 3. OS secure storage (keychain / Credential Manager / keyring /
    //    EncryptedSharedPrefs depending on platform).
    final purged = _purgeKeychain ? await _purgeKeychainStore() : false;
    mark('keychain_purge');

    return WipeReport(
      deletedFiles: deleted,
      failedFiles: failed,
      keychainPurged: purged,
      nativeVaultCleared: nativeCleared,
      biometricOverlayCleared: overlayCleared,
    );
  }

  /// Drop the primary hw-vault. Routes through the unified Rust
  /// dispatch in `lfs_os_security::hardware_tier_vault::clear`:
  /// SE primary key + envelope on Apple, AndroidKeyStore wrap key
  /// + bin file on Android, NCrypt persisted key + bin file on
  /// Windows, TPM2 envelope on Linux.
  Future<bool> _clearNativePrimary() async {
    if (!Platform.isMacOS &&
        !Platform.isIOS &&
        !Platform.isAndroid &&
        !Platform.isWindows &&
        !Platform.isLinux) {
      return false;
    }
    try {
      final dir = await _supportDir();
      await rust_hwvault.hardwareTierVaultClear(supportDir: dir.path);
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: Rust hw-vault clear failed: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }

  /// Drop the biometric overlay (key + file) via the unified Rust
  /// dispatch — Apple SE / Android Keystore / Windows CNG / Linux
  /// TPM2-sealed-under-fprintd-hash. Linux's overlay file is
  /// `hardware_vault_password_overlay_linux.bin`; the orchestrator
  /// lives one crate up in `lfs_core` because it depends on the
  /// in-crate fprintd D-Bus walk.
  Future<bool> _clearNativeBiometricOverlay() async {
    if (!Platform.isMacOS &&
        !Platform.isIOS &&
        !Platform.isAndroid &&
        !Platform.isWindows &&
        !Platform.isLinux) {
      return false;
    }
    try {
      final dir = await _supportDir();
      await rust_hwvault.hardwareTierVaultClearBiometricPassword(
        supportDir: dir.path,
      );
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: Rust hw-vault clearBiometric failed: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }

  /// Walk the canonical key list (versioned in Rust as
  /// `lfs_core::security::wipe_keychain::MANAGED_KEYS`) and ask
  /// the keychain plugin to drop each via the Rust actor. The
  /// audited key catalogue + the per-key outcome report live in
  /// Rust; per-key failures (e.g. one stuck Linux libsecret slot)
  /// are logged so partial wipe is visible in a support trace
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
        'WipeAllService: keychain purge skipped: $e',
        name: 'WipeAllService',
      );
      return false;
    }
  }
}
