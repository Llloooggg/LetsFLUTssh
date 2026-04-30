import 'dart:async' show unawaited;
import 'dart:io' show Directory, Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/rust_db_init.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/crypto.dart' as rust_crypto;
import '../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../core/migration/migration_runner.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/master_password.dart';
import '../core/security/password_rate_limiter.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
import '../core/security/tier_unlock_attempt.dart';
import '../core/security/wipe_all_service.dart';
import '../features/settings/security_tier_switcher.dart';
import '../l10n/app_localizations.dart';
import '../providers/auto_lock_provider.dart';
import '../providers/config_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/first_launch_banner_provider.dart';
import '../providers/key_provider.dart';
import '../providers/master_password_provider.dart';
import '../providers/security_provider.dart';
import '../providers/security_reinit_provider.dart';
import '../providers/session_credential_cache_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/platform.dart' as plat;
import '../widgets/app_dialog.dart';
import '../widgets/db_corrupt_dialog.dart';
import '../widgets/security_setup_dialog.dart';
import '../widgets/tier_reset_dialog.dart';
import '../widgets/tier_secret_unlock_dialog.dart';
import '../widgets/toast.dart';
import 'navigator_key.dart';
import 'security_dialog_prompter.dart';
import 'tier_unlocked_listener.dart';

/// Owns the startup / security / tier / DB lifecycle that
/// `_LetsFLUTsshAppState` used to carry inline.
///
/// Three mutable fields (`_securityReady`, `_corruptionRetries`,
/// `_credentialsWereReset`) are touched by ~30 methods spanning
/// migration, first-launch wizard, per-tier unlock, DB-corruption
/// recovery, reset, and reinit. Pulling them out of the state class
/// keeps main.dart's widget-level code focused on the UI shell
/// while giving this flow a single place to reason about its
/// invariants.
///
/// Lifecycle contract:
///   1. Constructed in `_LetsFLUTsshAppState.initState` with the
///      ConsumerState's `ref` + a `bool Function() isMounted`
///      closure so the "post-dispose bail" checks that used to read
///      `State.mounted` still short-circuit correctly.
///   2. `bootstrap()` runs migrations → security init → corruption
///      probe → session load. Called once from the first-frame
///      post-frame callback.
///   3. `reopenAfterUnlock()` fires from the lockState listener —
///      the auto-lock path closed the DB, the lock screen released
///      a fresh key, re-attach every store.
///   4. `reinitFromReset()` fires from the `securityReinitProvider`
///      listener — Settings → Reset All Data wiped everything, run
///      the first-launch wizard again.
///   5. `dispose()` called from the state's `dispose()` so any
///      in-flight async completes into a disposed flag instead of
///      touching the DB.
/// Signature of the `lfs_core.db` existence probe. Lets tests flip
/// "first launch vs existing install" without touching the
/// filesystem.
typedef DbFileExistsProbe = Future<bool> Function();

/// Signature of `verifyRustDbReadable` — trivial `SELECT count(*)
/// FROM sqlite_master` probe against the running Rust handle.
/// Injectable so tests can simulate a corrupt database without
/// synthesising a SQLCipher cipher mismatch on disk.
typedef DbReadableProbe = Future<bool> Function();

/// Signature of [runStartupMigrations]. Injectable so tests can drive
/// the error / recovery paths without having to synthesize a failing
/// artefact on disk.
typedef MigrationRunnerFn = Future<DbMigrationReport> Function();

class SecurityInitController {
  final WidgetRef ref;
  final bool Function() isMounted;

  /// Test seams — production leaves every field at the default so
  /// the unlock path stays identical. The hooks let tests swap in a
  /// canned "file exists" flag, a deterministic readability probe,
  /// a scripted dialog prompter, and a stubbed migration runner.
  final DbFileExistsProbe _dbFileExists;
  final DbReadableProbe _verifyReadable;
  final SecurityDialogPrompter _dialogs;
  final MigrationRunnerFn _migrationRunner;

  SecurityInitController({
    required this.ref,
    required this.isMounted,
    DbFileExistsProbe? dbFileExists,
    DbReadableProbe? verifyReadable,
    SecurityDialogPrompter? dialogPrompter,
    MigrationRunnerFn? migrationRunner,
  }) : _dbFileExists = dbFileExists ?? lfsCoreDbExists,
       _verifyReadable = verifyReadable ?? verifyRustDbReadable,
       _dialogs = dialogPrompter ?? const ProductionSecurityDialogPrompter(),
       _migrationRunner = migrationRunner ?? runStartupMigrations;

  // ── State fields ────────────────────────────────────────────

  /// True once the integrity probe has observed a successful read
  /// against the live `lfs_core.db`. Gates every follow-on query path —
  /// session reloads, auto-lock load — so nothing hits the DB
  /// before the cipher is validated.
  bool _securityReady = false;

  /// Counts how many times the corruption dialog has fired with the
  /// "try other credentials" option. Limits the recursion so a
  /// genuinely broken file cannot loop forever.
  int _corruptionRetries = 0;
  static const int _maxCorruptionRetries = 2;

  /// True when the user chose "forgot password" — read once by the
  /// state class via [takeAndClearCredentialsResetFlag] to surface
  /// a one-shot toast after sessions load.
  bool _credentialsWereReset = false;

  /// Set to true on [dispose]. Every `!isMounted()` check used to
  /// rely on [State.mounted]; after the move the same short-circuit
  /// still works — `isMounted` is a closure over the state's mount
  /// flag — but the controller also guards its own post-dispose
  /// reads with this field so a trailing async that resolves after
  /// [dispose] never walks into a disposed provider.
  bool _disposed = false;

  // ── Public API ─────────────────────────────────────────────

  /// Whether the post-unlock integrity probe has completed. Callers
  /// (session-reload lifecycle callback) short-circuit when this is
  /// false so nothing touches the DB before the cipher is validated.
  bool get isReady => _securityReady;

  /// Read-once flag: returns the previous value, clears it. The
  /// state class uses this from its post-session-load toast
  /// callback so the credentials-reset notification fires exactly
  /// once per reset.
  bool takeAndClearCredentialsResetFlag() {
    final v = _credentialsWereReset;
    _credentialsWereReset = false;
    return v;
  }

  /// Clean up. Called from `_LetsFLUTsshAppState.dispose()`.
  void dispose() {
    _disposed = true;
  }

  /// Full cold-start sequence: migrations → security init →
  /// corruption probe → session load. Called from the first-frame
  /// post-frame callback in `_LetsFLUTsshAppState.initState`.
  ///
  /// Returns nothing — all outcomes (success, migration failure,
  /// legacy-state wipe, first-launch wizard) are handled internally.
  Future<void> bootstrap() async {
    // Migration runner gates everything else — a failed or mismatched
    // artefact would make both the unlock flow and the corrupt-DB
    // probe read stale state. When it surfaces a reset, the migration
    // handler runs the full wipe + wizard on its own, so skip the
    // follow-up _initSecurity / corruption probe.
    final migrationOk = await _runMigrations();
    if (!migrationOk) return;
    await _initSecurity();
    // Integrity probe + first session load both read the unlocked DB,
    // so fire them in parallel — the corruption probe runs its own
    // SELECT and errors out before the session query would see stale
    // data. Previously sequential `_handleDatabaseCorruption` → `load`
    // added ~200 ms to cold start on every run (both hit drift's
    // first-query warm-up cost once each). Kicking them off together
    // overlaps that warm-up and saves roughly that window on plaintext
    // tiers where DB unlock itself is trivial. If corruption fires,
    // the reset dialog takes over regardless of load outcome.
    final corruptFuture = handleCorruption();
    // `sessionsLoadingProvider` defaults to `true` so the sidebar
    // already shows the blank placeholder; `load()` flips it back to
    // idle in its `finally` block.
    final loadFuture = ref.read(sessionProvider.notifier).load();
    await Future.wait([corruptFuture, loadFuture]);
  }

  /// Re-open the drift / MC handle after a lock → unlock transition.
  /// The auto-lock path unconditionally closes the DB handle so MC's
  /// C-layer page-cipher cache (ChaCha20-Poly1305 state) is zeroed
  /// alongside the Dart-side [SecretBuffer]. On unlock the lock
  /// screen re-derives the DB key, pushes it back into
  /// [securityStateProvider], and flips [lockStateProvider] off —
  /// this callback then walks the usual injection path so every
  /// store gets a fresh DB reference.
  Future<void> reopenAfterUnlock() async {
    if (!isMounted()) return;
    final security = ref.read(securityStateProvider);
    final key = security.encryptionKey;
    if (key == null) {
      AppLogger.instance.log(
        'Unlock re-open: securityStateProvider has no key — skipping',
        name: 'App',
      );
      return;
    }
    final modifiers = ref.read(configProvider).security?.modifiers;
    // `_injectDatabase` calls `securityStateProvider.set(level, key)`
    // internally, which copies the bytes into a fresh SecretBuffer
    // and disposes the old one. Reading the alias here and passing
    // it through is fine because the copy happens before the dispose
    // inside the notifier — same contract `_releaseLock` relies on.
    await _injectDatabase(
      key: key,
      level: security.level,
      modifiers: modifiers,
    );
    if (!isMounted()) return;
    await ref.read(sessionProvider.notifier).load();
  }

  /// Re-enter the first-launch provisioning path after a user-driven
  /// wipe completed elsewhere (Settings → Reset All Data).
  Future<void> reinitFromReset() async {
    if (!isMounted()) return;
    _safeRustDbClose();
    _corruptionRetries = 0;
    _securityReady = false;
    // Drop the cached `FutureProvider` snapshots so Settings UI
    // reads fresh probe results after the reset.
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    if (!isMounted()) return;
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    await _firstLaunchSetup(manager, keyStorage);
    if (!isMounted()) return;
    await handleCorruption();
    if (!isMounted()) return;
    await ref.read(sessionProvider.notifier).load();
  }

  /// Post-[bootstrap] integrity probe. Runs one trivial SELECT
  /// against the DB we just attached; on failure asks the user
  /// whether to try a different unlock path, wipe and start fresh,
  /// or quit. Public because [reinitFromReset] re-runs it after the
  /// wizard and because tests drive it directly.
  Future<void> handleCorruption() async {
    if (await _verifyReadable()) {
      _markSecurityReady();
      return;
    }

    // Probe failure is a crash-class event — the user is about to
    // see `DbCorruptDialog` and might pick "Reset" or "Quit"; either
    // way the breadcrumb must survive the routine-log toggle so we
    // can reason about the failure post-mortem.
    await AppLogger.instance.logCritical(
      'Database readability probe failed — offering reset dialog',
      name: 'App',
    );
    final choice = await _dialogs.showDbCorrupt();
    switch (choice) {
      case DbCorruptChoice.exitApp:
        AppLogger.instance.log(
          'DB corruption detected — user chose to exit',
          name: 'App',
        );
        await SystemNavigator.pop();
        exit(0);
      case DbCorruptChoice.tryOtherTier:
        await _retryUnlockUnderDifferentTier();
      case DbCorruptChoice.resetAndSetupFresh:
        await _wipeAndRestartFromScratch();
    }
  }

  // ── Migrations ─────────────────────────────────────────────

  /// Walk every framework-registered artefact and bring its on-disk
  /// state up to the current build's `lfs_core::migration::SchemaVersions`.
  /// Runs BEFORE `_initSecurity` so the unlock path always reads the
  /// post-migration shape.
  Future<bool> _runMigrations() async {
    final DbMigrationReport report;
    try {
      report = await _migrationRunner();
    } catch (e, st) {
      await AppLogger.instance.logCritical(
        'MigrationRunner threw uncaught: $e',
        name: 'App',
        error: e,
        stackTrace: st,
      );
      await _handleMigrationFailure();
      return false;
    }
    if (report.noOp) return true;
    if (report.hasFailures) {
      await AppLogger.instance.logCritical(
        'MigrationRunner reported failures '
        '(steps=${report.steps.length}, '
        'futureVersions=${report.futureVersions.length}, '
        'fatal=${report.fatalError}) — routing through corrupt dialog',
        name: 'App',
      );
      await _handleMigrationFailure();
      return false;
    }
    AppLogger.instance.log(
      'MigrationRunner: ${report.migratedCount} artefact(s) migrated',
      name: 'App',
    );
    if (report.migratedCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Toast.show(
            ctx,
            message: S.of(ctx).migrationToast,
            level: ToastLevel.info,
          );
        }
      });
    }
    return true;
  }

  Future<void> _handleMigrationFailure() async {
    final choice = await _dialogs.showDbCorrupt();
    switch (choice) {
      case DbCorruptChoice.exitApp:
      case DbCorruptChoice.tryOtherTier:
        AppLogger.instance.log(
          'Migration failure — user chose to exit',
          name: 'App',
        );
        await SystemNavigator.pop();
        exit(0);
      case DbCorruptChoice.resetAndSetupFresh:
        await _wipeAndRestartFromScratch();
    }
  }

  // ── Security init ──────────────────────────────────────────

  Future<void> _initSecurity() async {
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);

    await _clearPendingTierTransition();

    final wiper = WipeAllService();
    if (await wiper.hasPendingWipe()) {
      AppLogger.instance.log(
        'Resuming unfinished wipe from previous launch',
        name: 'App',
      );
      await wiper.wipeAll();
      _credentialsWereReset = true;
    }

    if (await _handleLegacyStateIfPresent(manager, keyStorage, wiper)) {
      return;
    }

    final dbExists = await _dbFileExists();
    if (dbExists) {
      await _unlockExistingDatabase(manager, keyStorage);
      return;
    }

    // No DB file — first launch. Show security setup wizard.
    await _firstLaunchSetup(manager, keyStorage);
  }

  Future<void> _clearPendingTierTransition() async {
    final pendingTransition = await SecurityTierSwitcher().readPendingMarker();
    if (pendingTransition == null) return;
    AppLogger.instance.log(
      'Pending tier-transition marker from previous session '
      '(payload=$pendingTransition) — clearing and falling back to '
      'standard unlock path',
      name: 'App',
    );
    await SecurityTierSwitcher().clearMarker();
  }

  Future<bool> _handleLegacyStateIfPresent(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
    WipeAllService wiper,
  ) async {
    final currentSecurity = ref.read(configProvider).security;
    final configVersion = await readConfigSchemaVersion();
    final legacyConfig =
        configVersion >= 0 && configVersion < kCurrentConfigSchemaVersion;
    final orphanArtefacts =
        currentSecurity == null && await wiper.hasAnyState();
    if (!legacyConfig && !orphanArtefacts) return false;
    if (!isMounted()) return true;
    final choice = await _dialogs.showTierReset();
    if (choice == TierResetChoice.exitApp) {
      AppLogger.instance.log(
        'Legacy state detected (configVersion=$configVersion, '
        'orphan=$orphanArtefacts) — user chose to exit',
        name: 'App',
      );
      await SystemNavigator.pop();
      exit(0);
    }
    await wiper.wipeAll();
    AppLogger.instance.log(
      'Legacy state detected (configVersion=$configVersion, '
      'orphan=$orphanArtefacts) — wiped, running fresh wizard',
      name: 'App',
    );
    _credentialsWereReset = true;
    await _firstLaunchSetup(manager, keyStorage);
    return true;
  }

  // ── Existing-install unlock ────────────────────────────────

  Future<void> _unlockExistingDatabase(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    final currentSecurity = ref.read(configProvider).security;
    if (currentSecurity != null) {
      await _unlockByTier(currentSecurity.tier, manager, keyStorage);
      return;
    }

    // Legacy-inference path — no explicit tier field yet.
    if (await manager.isEnabled()) {
      await _unlockParanoid(manager);
      return;
    }
    final keychainKey = await keyStorage.readKey();
    if (keychainKey != null) {
      await _injectDatabase(key: keychainKey, level: SecurityTier.keychain);
      AppLogger.instance.log('Keychain key loaded', name: 'App');
      return;
    }
    // DB exists but no encryption credentials — plaintext mode.
    await _injectDatabase();
    AppLogger.instance.log('Plaintext mode (existing DB)', name: 'App');
  }

  Future<void> _unlockByTier(
    SecurityTier tier,
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    switch (tier) {
      case SecurityTier.hardware:
        await _unlockHardware();
      case SecurityTier.keychainWithPassword:
        await _unlockKeychainWithPassword();
      case SecurityTier.keychain:
        await _unlockKeychain();
      case SecurityTier.paranoid:
        await _unlockParanoid(manager);
      case SecurityTier.plaintext:
        // Plaintext routes the cascade end-to-end through Rust:
        // `tier_unlock_plaintext` orchestrator dispatches
        // `UnlockRequested` + `UnlockSucceeded` and stages the
        // (empty) key under `tier.unlock.key`. The
        // `TierUnlockedListener` provider takes the staged key,
        // invalidates Dart-side caches, opens the Rust DB,
        // publishes `securityStateProvider`, persists the tier
        // into config — everything `_injectDatabase` used to do
        // here. Falls back to the inline `_injectDatabase` call
        // when the orchestrator is unreachable (flutter_test
        // contexts that don't load the FRB native lib — listener
        // never fires + the test harness drives drift open via
        // the manual call below).
        await _runPlaintextUnlockCascade();
        AppLogger.instance.log('Plaintext mode (tier=L0)', name: 'App');
    }
  }

  /// Drive the Plaintext unlock cascade through the
  /// orchestrator + listener pair; fall back to the inline
  /// `_injectDatabase` when the FRB native lib is unreachable
  /// (flutter_test contexts).
  Future<void> _runPlaintextUnlockCascade() async {
    try {
      final listener = ref.read(tierUnlockedListenerProvider)..start();
      // Arm BEFORE dispatch — the orchestrator's UnlockSucceeded
      // event delivery is async (FRB stream → Dart microtask)
      // but Dart can't process it before this call returns
      // control to the event loop, so the arm always lands
      // before the listener handler runs.
      final unlockDone = listener.awaitNextUnlock();
      rust_orch.tierUnlockPlaintext();
      final outcome = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (outcome == TierUnlockOutcome.unlocked) return;
      AppLogger.instance.log(
        'Plaintext unlock listener returned $outcome — falling '
        'back to inline _injectDatabase',
        name: 'App',
        level: LogLevel.warn,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Plaintext orchestrator path failed, falling back to '
        'inline _injectDatabase: $e',
        name: 'App',
        level: LogLevel.warn,
      );
    }
    await _injectDatabase();
  }

  Future<void> _unlockParanoid(MasterPasswordManager manager) async {
    if (!isMounted()) return;
    // Multi-attempt dialog: every submit fires a paired
    // `UnlockRequested` / `UnlockSucceeded`-or-`UnlockFailed`
    // through the `tier_unlock_paranoid` orchestrator (driven from
    // `manager.unlockAttempt`). Listener arms with `onlyUnlocked:
    // true` so per-attempt `Locked` events from wrong-password
    // retries don't resolve the wait; the dismiss-without-submit
    // branch resolves it via `cancelPending`.
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    final dialogResult = await _dialogs.showMasterPasswordUnlock(manager);
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('Master password unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'Paranoid dialog returned success but listener resolved $result',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      try {
        rust_orch.tierUnlockParanoidCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_paranoid_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    _credentialsWereReset = true;
    await _injectDatabase();
    AppLogger.instance.log(
      'Master password reset — credentials cleared',
      name: 'App',
    );
  }

  Future<void> _unlockKeychain() async {
    // Production routes through `tier_unlock_orchestrator::unlock_keychain`
    // + `TierUnlockedListener`: orchestrator stages the keychain
    // key under `tier.unlock.key`, listener takes it + runs the
    // post-unlock cascade (caches, securityStateProvider, Rust DB,
    // tier persist). Plaintext fallback covers both the orchestrator-
    // returned PluginError (keychain entry missing) and the FRB-
    // unreachable case (flutter_test).
    try {
      final listener = ref.read(tierUnlockedListenerProvider)..start();
      final unlockDone = listener.awaitNextUnlock();
      final outcome = await rust_orch.tierUnlockKeychain();
      if (outcome is rust_orch.DbUnlockOutcome_Staged) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log('Keychain key loaded (tier=L1)', name: 'App');
          return;
        }
        AppLogger.instance.log(
          'Keychain listener returned $result after Staged — '
          'falling through to plaintext fallback',
          name: 'App',
          level: LogLevel.warn,
        );
      }
      listener.cancelPending();
    } catch (e) {
      AppLogger.instance.log(
        'tier_unlock_keychain FRB unreachable: $e',
        name: 'App',
        level: LogLevel.warn,
      );
    }
    _credentialsWereReset = true;
    await _injectDatabase();
    AppLogger.instance.log(
      'L1 configured but keychain entry missing — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<void> _unlockKeychainWithPassword() async {
    final gate = ref.read(keychainPasswordGateProvider);
    if (!await gate.isConfigured()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L2 configured but gate state missing — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    // Multi-attempt dialog routes through the orchestrator + listener
    // pair. Listener arms with `onlyUnlocked: true` so per-attempt
    // `UnlockFailed` → `Locked` events from the wrong-password retry
    // loop don't resolve the wait — the dialog handles the retry UI
    // and the dismiss/reset path resolves explicitly via
    // `cancelPending`.
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    var biometricAttempted = false;
    final vault = ref.read(biometricKeyVaultProvider);
    final bio = ref.read(biometricAuthProvider);
    if (await vault.isStored() && await bio.isAvailable()) {
      biometricAttempted = true;
      final ok = await _tryBiometricCommit(SecurityTier.keychainWithPassword);
      if (ok) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log(
            'L2 keychain+password unlocked via biometrics',
            name: 'App',
          );
          return;
        }
        AppLogger.instance.log(
          'L2 biometric staged but listener returned $result — '
          'falling through to dialog',
          name: 'App',
          level: LogLevel.warn,
        );
      }
    }
    final dialogResult = await _showL2UnlockDialog(
      gate,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('L2 keychain+password unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'L2 dialog returned success but listener resolved $result — '
        'falling back to plaintext',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      // Dialog dismissed / reset / unrecoverable error. Fire the
      // cancel cascade so any half-state Unlocking transition
      // unwinds; idempotent on an already-Locked machine.
      try {
        rust_orch.tierUnlockKeychainWithPasswordCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_keychain_with_password_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L2 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<bool?> _showL2UnlockDialog(
    KeychainPasswordGate gate, {
    bool autoTriggerBiometric = true,
  }) async {
    final limiter = await gate.rateLimiter();
    if (!isMounted()) return null;
    return _showL2DialogSync(
      limiter,
      autoTriggerBiometric: autoTriggerBiometric,
    );
  }

  Future<bool?> _showL2DialogSync(
    PasswordRateLimiter? limiter, {
    bool autoTriggerBiometric = true,
  }) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    final l10n = S.of(ctx);
    return _dialogs.showTierSecretUnlock(
      ctx: ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l2UnlockTitle,
        hint: l10n.l2UnlockHint,
        inputLabel: l10n.password,
        wrongSecretLabel: l10n.l2WrongPassword,
      ),
      rateLimiter: limiter,
      verify: (password) async {
        // Routes through the `tier_unlock_keychain_with_password`
        // orchestrator: gate verify + keychain key read in one FRB
        // hop, bytes staged in the SecretStore, cascade emitted.
        // FRB-unreachable contexts (flutter_test) surface as
        // `TierUnlockAttempt.error` so the dialog closes + the
        // caller routes through the plaintext fallback in
        // `_unlockKeychainWithPassword`.
        try {
          final outcome = await rust_orch.tierUnlockKeychainWithPassword(
            password: password,
          );
          return mapUnlockOutcome(outcome);
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_keychain_with_password FRB unreachable: $e',
            name: 'App',
            level: LogLevel.warn,
          );
          return TierUnlockAttempt.error;
        }
      },
      biometricUnlock: () =>
          _tryBiometricCommit(SecurityTier.keychainWithPassword),
      autoTriggerBiometric: autoTriggerBiometric,
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        requestSecurityReinit(ref);
      },
    );
  }

  /// Read the biometric-vault DB key + commit it through the
  /// `tier_unlock_biometric_commit` shim so the cascade fires +
  /// the `TierUnlockedListener` runs the post-unlock cascade.
  /// Returns true on success, false on plugin-unavailable / wrong-
  /// auth / vault-empty.
  Future<bool> _tryBiometricCommit(SecurityTier tier) async {
    final ctx = navigatorKey.currentContext;
    final reason = ctx != null
        ? S.of(ctx).biometricUnlockPrompt
        : 'Biometric unlock';
    try {
      final vault = ref.read(biometricKeyVaultProvider);
      if (!await vault.isStored()) return false;
      final bio = ref.read(biometricAuthProvider);
      if (!await bio.isAvailable()) return false;
      if (!await bio.authenticate(reason)) return false;
      final key = await vault.read();
      if (key == null) return false;
      try {
        return rust_orch.tierUnlockBiometricCommit(
          tierWireName: tier.wireName,
          bytes: key,
        );
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_biometric_commit FRB unreachable: $e',
          name: 'App',
          level: LogLevel.warn,
        );
        return false;
      }
    } catch (e) {
      AppLogger.instance.log(
        'Tier-secret dialog biometric unlock failed: $e',
        name: 'App',
        error: e,
      );
      return false;
    }
  }

  Future<void> _unlockHardware() async {
    final vault = ref.read(hardwareTierVaultProvider);
    if (!await vault.isStored()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 configured but vault state missing — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    final mods = ref.read(configProvider).security?.modifiers;
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    if (mods != null && !mods.password) {
      // Passwordless variant — vault was sealed without a user
      // secret. Routes through `tier_unlock_hardware(null)` which
      // fans out to the platform vault via the prompt registry +
      // stages bytes in the SecretStore. FRB-unreachable contexts
      // (flutter_test) skip straight to the plaintext fallback.
      try {
        final outcome = await rust_orch.tierUnlockHardware();
        if (outcome is rust_orch.DbUnlockOutcome_Staged) {
          final result = await unlockDone.timeout(
            const Duration(seconds: 5),
            onTimeout: () => TierUnlockOutcome.failed,
          );
          if (result == TierUnlockOutcome.unlocked) {
            AppLogger.instance.log(
              'L3 hardware-vault unlocked (passwordless)',
              name: 'App',
            );
            return;
          }
          AppLogger.instance.log(
            'L3 passwordless listener returned $result after Staged',
            name: 'App',
            level: LogLevel.warn,
          );
        }
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_hardware (passwordless) FRB unreachable: $e',
          name: 'App',
          level: LogLevel.warn,
        );
      }
      listener.cancelPending();
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 passwordless unseal failed — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    var biometricAttempted = false;
    final vault2 = ref.read(biometricKeyVaultProvider);
    final bio = ref.read(biometricAuthProvider);
    if (await vault2.isStored() && await bio.isAvailable()) {
      biometricAttempted = true;
      final ok = await _tryBiometricCommit(SecurityTier.hardware);
      if (ok) {
        final result = await unlockDone.timeout(
          const Duration(seconds: 5),
          onTimeout: () => TierUnlockOutcome.failed,
        );
        if (result == TierUnlockOutcome.unlocked) {
          AppLogger.instance.log(
            'L3 hardware-vault unlocked via biometrics',
            name: 'App',
          );
          return;
        }
        AppLogger.instance.log(
          'L3 biometric staged but listener returned $result',
          name: 'App',
          level: LogLevel.warn,
        );
      }
    }
    final dialogResult = await _showL3UnlockDialog(
      mods,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (dialogResult == true) {
      final result = await unlockDone.timeout(
        const Duration(seconds: 5),
        onTimeout: () => TierUnlockOutcome.failed,
      );
      if (result == TierUnlockOutcome.unlocked) {
        AppLogger.instance.log('L3 hardware-vault unlocked', name: 'App');
        return;
      }
      AppLogger.instance.log(
        'L3 dialog returned success but listener resolved $result',
        name: 'App',
        level: LogLevel.warn,
      );
    } else {
      listener.cancelPending();
      // Dialog dismissed / reset / unrecoverable error. Fire the
      // cancel cascade so any half-state Unlocking unwinds.
      try {
        rust_orch.tierUnlockHardwareCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_hardware_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L3 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<bool?> _showL3UnlockDialog(
    SecurityTierModifiers? mods, {
    bool autoTriggerBiometric = true,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final l10n = S.of(ctx);
    final limiter = HardwareRateLimiter();
    return _dialogs.showTierSecretUnlock(
      ctx: ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l3UnlockTitle,
        hint: l10n.l3UnlockHint,
        inputLabel: l10n.pinLabel,
        wrongSecretLabel: l10n.l3WrongPin,
      ),
      rateLimiter: limiter,
      verify: (pin) async {
        // Routes through `tier_unlock_hardware(pin)` which fans
        // out to the platform vault via the prompt registry,
        // stages bytes in the SecretStore, emits the cascade.
        // FRB-unreachable contexts (flutter_test) surface as
        // `TierUnlockAttempt.error` so the dialog closes + the
        // caller routes through the plaintext fallback in
        // `_unlockHardware`.
        try {
          final outcome = await rust_orch.tierUnlockHardware(pin: pin);
          return mapUnlockOutcome(outcome);
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_hardware FRB unreachable: $e',
            name: 'App',
            level: LogLevel.warn,
          );
          return TierUnlockAttempt.error;
        }
      },
      biometricUnlock: () => _tryBiometricCommit(SecurityTier.hardware),
      autoTriggerBiometric: autoTriggerBiometric,
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        requestSecurityReinit(ref);
      },
    );
  }

  // ── First-launch wizard ────────────────────────────────────

  Future<void> _firstLaunchSetup(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    if (!isMounted()) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    var caps = await ref.read(securityCapabilitiesProvider.future);
    if (!isMounted()) return;

    if (plat.isMacosPlatform &&
        !caps.keychainAvailable &&
        caps.hardwareProbeCode == 'macosSigningIdentityMissing') {
      final updatedCaps = await _offerMacosSelfSign(caps);
      if (!isMounted()) return;
      caps = updatedCaps;
    }

    if (caps.keychainAvailable) {
      final ok = await _autoSetupKeychain(keyStorage);
      if (ok) {
        _queueFirstLaunchBanner(caps);
        return;
      }
      AppLogger.instance.log(
        'First launch: keychain probe said available but write failed — '
        'retrying through the manual wizard with T1 greyed out',
        name: 'App',
        level: LogLevel.warn,
      );
      caps = caps.copyWith(keychainAvailable: false);
    }

    final fallbackCtx = navigatorKey.currentContext;
    if (fallbackCtx == null || !fallbackCtx.mounted) return;
    final result = await _dialogs.showFirstLaunchWizard(fallbackCtx);
    if (!isMounted()) return;
    await _applyFirstLaunchWizardResult(
      result: result,
      manager: manager,
      keyStorage: keyStorage,
    );
  }

  Future<SecurityCapabilities> _offerMacosSelfSign(
    SecurityCapabilities caps,
  ) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return caps;
    final l10n = S.of(ctx);
    final accepted = await AppDialog.show<bool>(
      ctx,
      barrierDismissible: false,
      builder: (d) => AppDialog(
        title: l10n.securityMacosOfferTitle,
        dismissible: false,
        content: Text(
          l10n.securityMacosOfferBody,
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
        ),
        actions: [
          AppButton.secondary(
            label: l10n.securityMacosOfferDecline,
            onTap: () => Navigator.pop(d, false),
          ),
          AppButton.primary(
            label: l10n.securityMacosOfferAccept,
            icon: Icons.vpn_key,
            onTap: () => Navigator.pop(d, true),
          ),
        ],
      ),
    );
    if (accepted != true) {
      return caps.copyWith(
        keychainAvailable: false,
        hardwareVaultAvailable: false,
      );
    }
    try {
      final svc = ref.read(resignServiceProvider);
      await svc.ensureIdentity();
      final bundle = Directory(
        Platform.resolvedExecutable,
      ).parent.parent.parent;
      await svc.resignBundle(appBundle: bundle);
      await ref
          .read(configProvider.notifier)
          .update((c) => c.copyWithSecurity(securityProbeCache: null));
      ref.invalidate(securityCapabilitiesProvider);
      return await ref.read(securityCapabilitiesProvider.future);
    } catch (e) {
      AppLogger.instance.log(
        'macOS self-sign offer: failed to re-sign — falling back to reduced wizard',
        name: 'App',
        error: e,
      );
      return caps.copyWith(
        keychainAvailable: false,
        hardwareVaultAvailable: false,
      );
    }
  }

  Future<void> _applyFirstLaunchWizardResult({
    required SecuritySetupResult result,
    required MasterPasswordManager manager,
    required SecureKeyStorage keyStorage,
  }) async {
    switch (result.tier) {
      case SecurityTier.paranoid:
        await _firstLaunchParanoid(result, manager);
      case SecurityTier.hardware:
        await _firstLaunchHardware(result.pin, result.modifiers);
      case SecurityTier.keychainWithPassword:
        await _firstLaunchKeychainWithPassword(
          keyStorage: keyStorage,
          shortPassword: result.shortPassword,
          modifiers: result.modifiers,
        );
      case SecurityTier.keychain:
        await _firstLaunchKeychain(result, keyStorage);
      case SecurityTier.plaintext:
        final ok = await _runFirstLaunchOrchestrator(
          tier: SecurityTier.plaintext,
          dispatch: () async {
            rust_orch.tierFirstLaunchPlaintext();
            return true;
          },
        );
        if (!ok) {
          // Orchestrator unreachable — fall back to direct inject.
          await _injectDatabase();
        }
        AppLogger.instance.log(
          'First launch: plaintext mode (L0)',
          name: 'App',
        );
    }
  }

  Future<void> _firstLaunchParanoid(
    SecuritySetupResult result,
    MasterPasswordManager manager,
  ) async {
    final password = result.masterPassword;
    if (password == null) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.paranoid,
      modifiers: result.modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchParanoid(
          password: password,
        );
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: master password (Paranoid) enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart manager.enable path so flutter_test contexts (no FRB
    // native lib) still resolve.
    final key = await manager.enable(password);
    await _injectDatabase(
      key: key,
      level: SecurityTier.paranoid,
      modifiers: result.modifiers,
    );
    AppLogger.instance.log(
      'First launch: master password (Paranoid) enabled (fallback)',
      name: 'App',
    );
  }

  Future<void> _firstLaunchKeychain(
    SecuritySetupResult result,
    SecureKeyStorage keyStorage,
  ) async {
    if (!result.keychainAvailable) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychain,
      modifiers: result.modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychain();
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: keychain encryption enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / write failed — fall back to direct
    // Dart pipeline so flutter_test contexts still resolve.
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.keychain,
        modifiers: result.modifiers,
      );
      AppLogger.instance.log(
        'First launch: keychain encryption enabled (fallback)',
        name: 'App',
      );
    } else {
      await _injectDatabase();
      AppLogger.instance.log(
        'First launch: keychain write failed, falling back to plaintext',
        name: 'App',
        level: LogLevel.warn,
      );
    }
  }

  Future<bool> _autoSetupKeychain(SecureKeyStorage keyStorage) async {
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychain,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychain();
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: auto-selected T1 (keychain)',
        name: 'App',
      );
      return true;
    }
    // Orchestrator unreachable / write failed — fall back to direct
    // Dart pipeline.
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(key: key, level: SecurityTier.keychain);
      AppLogger.instance.log(
        'First launch: auto-selected T1 (keychain, fallback)',
        name: 'App',
      );
      return true;
    }
    AppLogger.instance.log(
      'First launch: auto-select T1 keychain write rejected — '
      'leaving DB uninitialised for the wizard fallback',
      name: 'App',
      level: LogLevel.warn,
    );
    return false;
  }

  /// Pre-write the SecurityConfig so the listener's
  /// `_persistSecurityTier` no-ops (existing modifiers match), arm
  /// the listener, dispatch the first-launch orchestrator, await
  /// the cascade. Returns true on success, false on orchestrator
  /// failure / FRB unreachable so the caller takes the Dart-side
  /// fallback.
  Future<bool> _runFirstLaunchOrchestrator({
    required SecurityTier tier,
    SecurityTierModifiers? modifiers,
    required Future<bool> Function() dispatch,
  }) async {
    final resolved = modifiers ?? SecurityTierModifiers.defaults;
    final cfg = SecurityConfig(tier: tier, modifiers: resolved);
    await ref
        .read(configProvider.notifier)
        .update((c) => c.copyWithSecurity(security: cfg));
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock();
    bool staged;
    try {
      staged = await dispatch();
    } catch (e) {
      listener.cancelPending();
      AppLogger.instance.log(
        'First launch orchestrator FRB unreachable for $tier: $e',
        name: 'App',
        level: LogLevel.warn,
      );
      return false;
    }
    if (!staged) {
      listener.cancelPending();
      AppLogger.instance.log(
        'First launch orchestrator returned non-staged for $tier',
        name: 'App',
        level: LogLevel.warn,
      );
      return false;
    }
    final result = await unlockDone.timeout(
      const Duration(seconds: 5),
      onTimeout: () => TierUnlockOutcome.failed,
    );
    if (result == TierUnlockOutcome.unlocked) return true;
    AppLogger.instance.log(
      'First launch listener returned $result after Staged for $tier',
      name: 'App',
      level: LogLevel.warn,
    );
    return false;
  }

  void _queueFirstLaunchBanner(SecurityCapabilities caps) {
    ref
        .read(firstLaunchBannerProvider.notifier)
        .set(
          FirstLaunchBannerData(
            activeTier: SecurityTier.keychain,
            hardwareUpgradeAvailable: caps.hardwareVaultAvailable,
            hardwareUnavailableReason: caps.hardwareVaultAvailable
                ? null
                : defaultHardwareUnavailableReason(),
          ),
        );
  }

  Future<void> _firstLaunchKeychainWithPassword({
    required SecureKeyStorage keyStorage,
    required String? shortPassword,
    SecurityTierModifiers? modifiers,
  }) async {
    if (shortPassword == null || shortPassword.isEmpty) {
      await _injectDatabase();
      return;
    }
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.keychainWithPassword,
      modifiers: modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchKeychainWithPassword(
          password: shortPassword,
        );
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: keychain+password (L2) enabled',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart pipeline so flutter_test contexts still resolve.
    final gate = ref.read(keychainPasswordGateProvider);
    await gate.setPassword(shortPassword);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.keychainWithPassword,
        modifiers: modifiers,
      );
      AppLogger.instance.log(
        'First launch: keychain+password (L2) enabled (fallback)',
        name: 'App',
      );
      return;
    }
    await gate.clear();
    await _injectDatabase();
    AppLogger.instance.log(
      'First launch: L2 keychain write failed — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<void> _firstLaunchHardware(
    String? pin, [
    SecurityTierModifiers? modifiers,
  ]) async {
    final ok = await _runFirstLaunchOrchestrator(
      tier: SecurityTier.hardware,
      modifiers: modifiers,
      dispatch: () async {
        final outcome = await rust_orch.tierFirstLaunchHardware(pin: pin);
        return outcome is rust_orch.DbUnlockOutcome_Staged;
      },
    );
    if (ok) {
      AppLogger.instance.log(
        'First launch: hardware vault (L3) sealed',
        name: 'App',
      );
      return;
    }
    // Orchestrator unreachable / staging failed — fall back to the
    // pure-Dart pipeline so flutter_test contexts (no FRB native
    // lib) still resolve.
    final vault = ref.read(hardwareTierVaultProvider);
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await vault.store(dbKey: key, pin: pin);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.hardware,
        modifiers: modifiers,
      );
      AppLogger.instance.log(
        'First launch: hardware vault (L3) sealed (fallback)',
        name: 'App',
      );
      return;
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'First launch: hardware-vault seal failed — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  // ── DB injection + helpers ────────────────────────────────

  Future<void> _injectDatabase({
    Uint8List? key,
    SecurityTier level = SecurityTier.plaintext,
    SecurityTierModifiers? modifiers,
  }) async {
    if (_disposed) return;
    // Stores read/write through FRB into `lfs_core.db`; the unlock
    // handshake invalidates each store's in-memory cache so the next
    // read pulls fresh rows after the engine swap.
    ref.read(sessionProvider.notifier).invalidateCache();
    ref.read(sshKeysProvider.notifier).invalidateCache();
    ref.read(knownHostsProvider.notifier).invalidateCache();
    if (key != null) {
      ref.read(securityStateProvider.notifier).set(level, key);
    }
    // Open the Rust-owned sqlite handle, keyed off the same master
    // key the tier-derivation step just produced. Failures degrade
    // silently — see ensureRustDbOpen.
    await ensureRustDbOpen(key: key);
    await _persistSecurityTier(level, modifiers);
  }

  Future<void> _retryUnlockUnderDifferentTier() async {
    _corruptionRetries++;
    _securityReady = false;
    _safeRustDbClose();
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    await ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWithSecurity(security: null, securityProbeCache: null),
        );
    _credentialsWereReset = false;
    AppLogger.instance.log(
      'DB corruption: retrying unlock under legacy-infer path '
      '(attempt $_corruptionRetries/$_maxCorruptionRetries)',
      name: 'App',
    );
    if (!isMounted()) return;
    await _initSecurity();
    if (!isMounted()) return;
    if (_corruptionRetries > _maxCorruptionRetries) {
      await _wipeAndRestartFromScratch();
      return;
    }
    await handleCorruption();
  }

  Future<void> _wipeAndRestartFromScratch() async {
    _securityReady = false;
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    _safeRustDbClose();
    await WipeAllService(
      credentialCacheEvict: ref.read(sessionCredentialCacheProvider).evictAll,
    ).wipeAll();
    await ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWithSecurity(security: null, securityProbeCache: null),
        );
    _credentialsWereReset = true;
    _corruptionRetries = 0;
    if (!isMounted()) return;
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    await _firstLaunchSetup(manager, keyStorage);
    if (await _verifyReadable()) {
      _markSecurityReady();
    }
  }

  void _markSecurityReady() {
    if (_securityReady) return;
    _securityReady = true;
    unawaited(ref.read(autoLockMinutesProvider.notifier).load());
  }

  Future<void> _persistSecurityTier(
    SecurityTier tier, [
    SecurityTierModifiers? modifiers,
  ]) async {
    final existing = ref.read(configProvider).security;
    final resolved =
        modifiers ?? existing?.modifiers ?? SecurityTierModifiers.defaults;
    if (existing != null &&
        existing.tier == tier &&
        existing.modifiers == resolved) {
      return;
    }
    final next = SecurityConfig(tier: tier, modifiers: resolved);
    await ref
        .read(configProvider.notifier)
        .update((cfg) => cfg.copyWithSecurity(security: next));
  }

  /// Drop the running Rust DB handle, swallowing the
  /// RustLib-not-initialised throw the unit-test runner raises (no
  /// native lib in flutter_test). Used in the lock / wipe / retry
  /// paths where the close is best-effort.
  void _safeRustDbClose() {
    try {
      rust_app.dbClose();
    } catch (e) {
      AppLogger.instance.log(
        'Rust DB close failed (no native lib in unit tests?): $e',
        name: 'App',
      );
    }
  }
}
