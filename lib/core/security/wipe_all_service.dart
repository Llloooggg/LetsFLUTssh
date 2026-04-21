import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
/// Single source of truth for every file + keychain alias + native
/// hw-vault entry the app ever writes. Three consumers share this
/// service:
///
/// * Settings → Reset all data (user-initiated; double-confirmed).
/// * DbCorruptDialog (automatic on failed cipher-under-tier probe).
/// * TierResetDialog (automatic when a v1-era tier is detected on
///   first launch under the v2 build).
///
/// Crash safety: before any delete runs, the service writes a
/// `.wipe-pending` marker to app-support. The next launch treats a
/// leftover marker as "resume wipe" and re-runs the full sweep
/// idempotently before hitting `_initSecurity`. The marker is cleared
/// only after every best-effort step finishes.
///
/// Intentionally *not* tied to the migration framework's `Artefact`
/// interface: wipe is a cross-cutting concern that touches files even
/// the migration framework does not track (logs, legacy markers,
/// keychain aliases), so a stand-alone list keeps the cleanup total.
class WipeAllService {
  WipeAllService({
    Future<Directory> Function()? supportDirFactory,
    FlutterSecureStorage? keychain,
    MethodChannel? hardwareVaultChannel,
    bool purgeKeychain = true,
  }) : _supportDir = supportDirFactory ?? getApplicationSupportDirectory,
       _keychain = keychain ?? const FlutterSecureStorage(),
       _hwChannel =
           hardwareVaultChannel ??
           const MethodChannel(_hardwareVaultChannelName),
       _purgeKeychain = purgeKeychain;

  static const _hardwareVaultChannelName = 'com.letsflutssh/hardware_vault';
  static const _wipePendingMarker = '.wipe-pending';

  /// Every file the app writes under the app-support directory. New
  /// artefacts MUST be added here so the wipe stays total. Ordered
  /// from "safest to delete first" (markers, overlays) → "most
  /// destructive last" (the DB itself) so a mid-wipe crash leaves the
  /// user with at least a detectable "wipe was in progress" state.
  static const _managedFiles = <String>[
    // Markers / transient state
    '.tier-transition-pending',
    'keychain_enabled',
    'rate_limit_state.bin',

    // Biometric / hw overlay blobs (password released from biometric-gated slot)
    'hardware_vault_password_overlay_android.bin',
    'hardware_vault_password_overlay_apple.bin',
    'hardware_vault_password_overlay_windows.bin',

    // Password gate (L2-era + current bank-style password layer)
    'security_pass_hash.bin',

    // Hardware vault primary blobs — one per platform
    'hardware_vault.bin',
    'hardware_vault_android.bin',
    'hardware_vault_apple.bin',
    'hardware_vault_ios.bin',
    'hardware_vault_macos.bin',
    'hardware_vault_windows.bin',
    'hardware_vault_linux.bin',
    'hardware_vault_salt.bin',

    // Legacy biometric-vault + TPM blobs predating the tier model
    'biometric_vault.tpm',

    // KDF descriptors (Paranoid / Argon2id params)
    'credentials.kdf',
    'credentials.salt',
    'credentials.verify',
    'credentials.key',

    // Config (contains the active tier, modifiers, user prefs)
    'config.json',

    // Migration framework state — regenerates on next launch
    'migration_history.json',

    // Drift DB + SQLite sidecars. Last because losing these zaps the
    // session list. Ordering intentional: if the wipe crashes before
    // we get here, the user still sees a tier-less install that the
    // wizard can handle, rather than a DB under an unknown cipher.
    'letsflutssh.db',
    'letsflutssh.db-wal',
    'letsflutssh.db-shm',
    'letsflutssh.db-journal',
  ];

  final Future<Directory> Function() _supportDir;
  final FlutterSecureStorage _keychain;
  final MethodChannel _hwChannel;
  final bool _purgeKeychain;

  /// True if a `.wipe-pending` marker is on disk — the previous run
  /// started a wipe that did not finish. Call sites check this on
  /// startup and re-run the service before `_initSecurity`.
  Future<bool> hasPendingWipe() async {
    try {
      final dir = await _supportDir();
      return File(p.join(dir.path, _wipePendingMarker)).exists();
    } catch (_) {
      return false;
    }
  }

  /// True when **any security-bearing** managed artefact lives in the
  /// app-support dir. Used on startup to detect "install has prior
  /// state" when the current build also finds `config.security == null`
  /// — together those predicates mean the on-disk state predates the
  /// current schema and should be wiped via the user-confirmed reset
  /// dialog.
  ///
  /// *`config.json` and `migration_history.json` are excluded from
  /// this probe* because both are recreated as soon as the app
  /// initialises its provider graph — a freshly-reset install writes
  /// `config.json` back with `security: null` seconds after the wipe
  /// finishes, so counting it as "state" trapped the user in a
  /// reset-dialog loop: reset → wipe → provider rewrites config →
  /// next launch sees "orphan state" → offers reset again. Neither
  /// file carries credential material; they are settings. The real
  /// "orphan install" signal is a KDF descriptor, a hw-vault blob,
  /// a DB file, or a legacy credentials artefact — all of which stay
  /// in the scan list below.
  static const _orphanProbeFiles = <String>[
    '.tier-transition-pending',
    'keychain_enabled',
    'rate_limit_state.bin',
    'hardware_vault_password_overlay_android.bin',
    'hardware_vault_password_overlay_apple.bin',
    'hardware_vault_password_overlay_windows.bin',
    'security_pass_hash.bin',
    'hardware_vault.bin',
    'hardware_vault_android.bin',
    'hardware_vault_apple.bin',
    'hardware_vault_ios.bin',
    'hardware_vault_macos.bin',
    'hardware_vault_windows.bin',
    'hardware_vault_linux.bin',
    'hardware_vault_salt.bin',
    'biometric_vault.tpm',
    'credentials.kdf',
    'credentials.salt',
    'credentials.verify',
    'credentials.key',
    'letsflutssh.db',
    'letsflutssh.db-wal',
    'letsflutssh.db-shm',
    'letsflutssh.db-journal',
  ];

  Future<bool> hasAnyState() async {
    try {
      final dir = await _supportDir();
      for (final name in _orphanProbeFiles) {
        if (await File(p.join(dir.path, name)).exists()) return true;
      }
      return false;
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
    final deleted = <String>[];
    final failed = <String>[];
    final dir = await _supportDir();

    // 1. Drop the marker first so a crash mid-wipe leaves a trace the
    //    next launch can detect.
    await _writePendingMarker(dir);

    // 2. Files. Best-effort per-file; one stuck entry does not abort
    //    the sweep.
    for (final name in _managedFiles) {
      final file = File(p.join(dir.path, name));
      try {
        if (await file.exists()) {
          await file.delete();
          deleted.add(name);
        }
      } catch (e) {
        failed.add(name);
        AppLogger.instance.log(
          'WipeAllService: failed to delete $name: $e',
          name: 'WipeAllService',
        );
      }
    }

    // 3. Native hw-vault: primary + biometric overlay. Swallow errors;
    //    a missing channel (desktop Linux, missing plugin) is a no-op.
    final nativeCleared = await _invokeNative('clear');
    final overlayCleared = await _invokeNative('clearBiometricPassword');

    // 4. OS secure storage (keychain / Credential Manager / keyring /
    //    EncryptedSharedPrefs depending on platform).
    final purged = _purgeKeychain ? await _purgeKeychainStore() : false;

    // 5. Logs directory — a "reset all" that leaves behind a log of
    //    every session name defeats the point. Best-effort; a busy
    //    FS handle on Windows (logger not closed) is not fatal.
    await _wipeLogsDir(dir);

    // 6. All done — drop the marker.
    await _clearPendingMarker(dir);

    return WipeReport(
      deletedFiles: deleted,
      failedFiles: failed,
      keychainPurged: purged,
      nativeVaultCleared: nativeCleared,
      biometricOverlayCleared: overlayCleared,
    );
  }

  Future<void> _writePendingMarker(Directory dir) async {
    try {
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, _wipePendingMarker),
      ).writeAsString('${DateTime.now().toUtc().toIso8601String()}\n');
    } catch (e) {
      AppLogger.instance.log(
        'WipeAllService: failed to write marker: $e',
        name: 'WipeAllService',
      );
    }
  }

  Future<void> _clearPendingMarker(Directory dir) async {
    try {
      final f = File(p.join(dir.path, _wipePendingMarker));
      if (await f.exists()) await f.delete();
    } catch (_) {}
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

  Future<bool> _purgeKeychainStore() async {
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

  Future<void> _wipeLogsDir(Directory supportDir) async {
    try {
      final logs = Directory(p.join(supportDir.path, 'logs'));
      if (await logs.exists()) {
        await for (final entity in logs.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
