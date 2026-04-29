import 'dart:async' show unawaited;
import 'dart:io' show Directory, Platform, exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/rust_db_init.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/crypto.dart' as rust_crypto;
import '../src/rust/api/tier_machine.dart' as rust_tier;
import '../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../core/migration/migration_runner.dart';
import '../core/security/hardware_tier_vault.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/master_password.dart';
import '../core/security/password_rate_limiter.dart';
import '../core/security/secure_key_storage.dart';
import '../core/security/security_bootstrap.dart';
import '../core/security/security_tier.dart';
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
import 'security_dialogs.dart';
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
        await _unlockKeychainWithPassword(keyStorage);
      case SecurityTier.keychain:
        await _unlockKeychain(keyStorage);
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
  /// `_injectDatabase` when either side is unreachable
  /// (flutter_test contexts that don't load the FRB native
  /// lib).
  Future<void> _runPlaintextUnlockCascade() async {
    try {
      final listener = ref.read(tierUnlockedListenerProvider)..start();
      // Arm BEFORE dispatch — the orchestrator's UnlockSucceeded
      // event delivery is async (FRB stream → Dart microtask)
      // but Dart can't process it before this call returns
      // control to the event loop, so the arm always lands
      // before the listener handler runs.
      final unlockDone = listener.awaitNextUnlock();
      _routePlaintextThroughTierMachine();
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

  /// Push the active tier into the `tier_machine` actor +
  /// dispatch the unlock cascade so observers (TierStateObserver
  /// + future per-tier handlers) see the transition. Single FRB
  /// hop — the Rust `tier_unlock_orchestrator::unlock_plaintext`
  /// owns the set_tier + UnlockRequested + UnlockSucceeded chain
  /// internally. Best-effort — orchestrator unreachable in
  /// flutter_test contexts that don't load the FRB native lib.
  void _routePlaintextThroughTierMachine() {
    try {
      rust_orch.tierUnlockPlaintext();
    } catch (e) {
      AppLogger.instance.log(
        'tier_machine plaintext route failed: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
  }

  /// Set the active tier + emit `unlock_requested` so the
  /// `tier_machine` actor + every observer sees the cascade
  /// start. Per-tier paths invoke this before their async unlock
  /// work; the matching `_emitTierUnlockResolved` fires when
  /// the work completes (or fails).
  void _emitTierUnlockStart(String tierWireName) {
    try {
      rust_tier.tierMachineSetTier(tierWireName: tierWireName);
      rust_tier.tierMachineDispatch(
        event: const rust_tier.DbTierEvent(discriminant: 'unlock_requested'),
      );
    } catch (e) {
      AppLogger.instance.log(
        'tier_machine $tierWireName start failed: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
  }

  /// Resolve the in-flight `unlock_requested` with success or
  /// failure. Failure reasons map to `UnlockFailureReason` —
  /// the Dart caller passes the discriminant; the typed payload
  /// (plugin code / corruption detail) is best-effort empty
  /// today and gets enriched as per-tier handlers move into
  /// Rust.
  void _emitTierUnlockResolved({
    required bool succeeded,
    String failureDiscriminant = 'wrong_secret',
  }) {
    try {
      if (succeeded) {
        rust_tier.tierMachineDispatch(
          event: const rust_tier.DbTierEvent(discriminant: 'unlock_succeeded'),
        );
      } else {
        rust_tier.tierMachineDispatch(
          event: rust_tier.DbTierEvent(
            discriminant: 'unlock_failed',
            failReason: rust_tier.DbUnlockFailureReason(
              discriminant: failureDiscriminant,
              code: '',
              detail: '',
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'tier_machine resolve failed: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
  }

  Future<void> _unlockParanoid(MasterPasswordManager manager) async {
    if (!isMounted()) return;
    // Cascade emit (UnlockRequested → UnlockSucceeded /
    // UnlockFailed) fires inside `manager.verifyAndDerive(...,
    // useRateLimit: true)` which routes through the
    // `tier_unlock_paranoid` orchestrator. The dismiss-without-
    // submit branch below explicitly emits the cancel cascade
    // so every attempt lands a paired terminal-state event.
    final derivedKey = await _dialogs.showMasterPasswordUnlock(manager);
    if (derivedKey != null) {
      await _injectDatabase(key: derivedKey, level: SecurityTier.paranoid);
      AppLogger.instance.log('Master password unlocked', name: 'App');
    } else {
      try {
        rust_orch.tierUnlockParanoidCancel();
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_paranoid_cancel FRB unreachable: $e',
          name: 'TierMachine',
          level: LogLevel.warn,
        );
      }
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'Master password reset — credentials cleared',
        name: 'App',
      );
    }
  }

  Future<void> _unlockKeychain(SecureKeyStorage keyStorage) async {
    // Production routes through `tier_unlock_orchestrator::unlock_keychain`
    // which dispatches the cascade events + reads the keychain
    // slot via the prompt registry. Falls back to the inline
    // Dart helper when the FRB native lib is not loaded
    // (flutter_test contexts that don't bootstrap RustLib).
    Uint8List? keychainKey;
    var fellBack = false;
    try {
      final bytes = await rust_orch.tierUnlockKeychain();
      keychainKey = bytes == null ? null : Uint8List.fromList(bytes);
    } catch (e) {
      AppLogger.instance.log(
        'tier_unlock_keychain FRB unreachable, falling back to '
        'Dart pipeline: $e',
        name: 'App',
      );
      _emitTierUnlockStart('keychain');
      keychainKey = await keyStorage.readKey();
      fellBack = true;
    }
    if (keychainKey != null) {
      await _injectDatabase(key: keychainKey, level: SecurityTier.keychain);
      if (fellBack) _emitTierUnlockResolved(succeeded: true);
      AppLogger.instance.log('Keychain key loaded (tier=L1)', name: 'App');
      return;
    }
    if (fellBack) {
      _emitTierUnlockResolved(
        succeeded: false,
        failureDiscriminant: 'plugin_unavailable',
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

  Future<void> _unlockKeychainWithPassword(SecureKeyStorage keyStorage) async {
    _emitTierUnlockStart('keychain_with_password');
    final gate = ref.read(keychainPasswordGateProvider);
    if (!await gate.isConfigured()) {
      _emitTierUnlockResolved(
        succeeded: false,
        failureDiscriminant: 'plugin_unavailable',
      );
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L2 configured but gate state missing — plaintext fallback',
        name: 'App',
        level: LogLevel.warn,
      );
      return;
    }
    var biometricAttempted = false;
    final vault = ref.read(biometricKeyVaultProvider);
    final bio = ref.read(biometricAuthProvider);
    if (await vault.isStored() && await bio.isAvailable()) {
      biometricAttempted = true;
      final bioKey = await _tryBiometricUnlock();
      if (bioKey != null) {
        await _injectDatabase(
          key: bioKey,
          level: SecurityTier.keychainWithPassword,
        );
        _emitTierUnlockResolved(succeeded: true);
        AppLogger.instance.log(
          'L2 keychain+password unlocked via biometrics',
          name: 'App',
        );
        return;
      }
    }
    final key = await _showL2UnlockDialog(
      gate,
      keyStorage,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (key != null) {
      await _injectDatabase(
        key: Uint8List.fromList(key),
        level: SecurityTier.keychainWithPassword,
      );
      // Cascade `UnlockSucceeded` already fired inside the
      // dialog's verify callback (orchestrator owns it); the
      // dialog open itself emitted `UnlockRequested` via the
      // Dart helper above. Nothing to re-emit here.
      AppLogger.instance.log('L2 keychain+password unlocked', name: 'App');
      return;
    }
    // Dialog dismissed without a successful unlock. Fire the
    // cancel cascade so `UnlockRequested` from `_emitTierUnlockStart`
    // above lands a paired terminal-state event; idempotent on
    // an already-Locked machine (the orchestrator's own
    // WrongSecret emit may have already returned us there).
    try {
      rust_orch.tierUnlockKeychainWithPasswordCancel();
    } catch (e) {
      AppLogger.instance.log(
        'tier_unlock_keychain_with_password_cancel FRB unreachable: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L2 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<List<int>?> _showL2UnlockDialog(
    KeychainPasswordGate gate,
    SecureKeyStorage keyStorage, {
    bool autoTriggerBiometric = true,
  }) async {
    final limiter = await gate.rateLimiter();
    if (!isMounted()) return null;
    return _showL2DialogSync(
      gate,
      keyStorage,
      limiter,
      autoTriggerBiometric: autoTriggerBiometric,
    );
  }

  Future<List<int>?> _showL2DialogSync(
    KeychainPasswordGate gate,
    SecureKeyStorage keyStorage,
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
        // Production routes through the
        // `tier_unlock_keychain_with_password` orchestrator
        // which composes the gate verify + keychain key read
        // into one FRB hop AND emits the
        // `BusEvent::TierStateChanged` cascade. The pure-Dart
        // `gate.verify + keyStorage.readKey` chain stays as
        // the flutter_test fallback (no FRB native lib).
        try {
          return await rust_orch.tierUnlockKeychainWithPassword(
            password: password,
          );
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_keychain_with_password FRB unreachable, '
            'falling back to Dart pipeline: $e',
            name: 'App',
          );
        }
        if (!await gate.verify(password)) return null;
        final fallback = await keyStorage.readKey();
        return fallback;
      },
      biometricUnlock: _biometricUnlockForTierDialog,
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

  Future<List<int>?> _biometricUnlockForTierDialog() async {
    final ctx = navigatorKey.currentContext;
    final reason = ctx != null
        ? S.of(ctx).biometricUnlockPrompt
        : 'Biometric unlock';
    try {
      final vault = ref.read(biometricKeyVaultProvider);
      if (!await vault.isStored()) return null;
      final bio = ref.read(biometricAuthProvider);
      if (!await bio.isAvailable()) return null;
      if (!await bio.authenticate(reason)) return null;
      final key = await vault.read();
      return key;
    } catch (e) {
      AppLogger.instance.log(
        'Tier-secret dialog biometric unlock failed: $e',
        name: 'App',
        error: e,
      );
      return null;
    }
  }

  Future<void> _unlockHardware() async {
    _emitTierUnlockStart('hardware');
    final vault = ref.read(hardwareTierVaultProvider);
    if (!await vault.isStored()) {
      _emitTierUnlockResolved(
        succeeded: false,
        failureDiscriminant: 'plugin_unavailable',
      );
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
    if (mods != null && !mods.password) {
      // Passwordless variant — vault was sealed without a user
      // secret. Production routes through the
      // `tier_unlock_hardware(null)` orchestrator which fans
      // out to the platform vault via the prompt registry +
      // emits the cascade. Falls back to direct `vault.read`
      // for flutter_test contexts (no FRB native lib).
      List<int>? unsealed;
      var orchestratorRoute = false;
      try {
        unsealed = await rust_orch.tierUnlockHardware();
        orchestratorRoute = true;
      } catch (e) {
        AppLogger.instance.log(
          'tier_unlock_hardware (passwordless) FRB unreachable, '
          'falling back to Dart pipeline: $e',
          name: 'App',
        );
        unsealed = await vault.read(null);
      }
      if (unsealed != null) {
        await _injectDatabase(
          key: Uint8List.fromList(unsealed),
          level: SecurityTier.hardware,
          modifiers: mods,
        );
        if (!orchestratorRoute) _emitTierUnlockResolved(succeeded: true);
        AppLogger.instance.log(
          'L3 hardware-vault unlocked (passwordless)',
          name: 'App',
        );
        return;
      }
      if (!orchestratorRoute) {
        _emitTierUnlockResolved(
          succeeded: false,
          failureDiscriminant: 'corruption',
        );
      }
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
      final bioKey = await _tryBiometricUnlock();
      if (bioKey != null) {
        await _injectDatabase(
          key: bioKey,
          level: SecurityTier.hardware,
          modifiers: mods,
        );
        _emitTierUnlockResolved(succeeded: true);
        AppLogger.instance.log(
          'L3 hardware-vault unlocked via biometrics',
          name: 'App',
        );
        return;
      }
    }
    final unlocked = await _showL3UnlockDialog(
      vault,
      mods,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (unlocked) {
      // Cascade `UnlockSucceeded` already fired inside the
      // dialog's verify callback (orchestrator owns it for the
      // PIN path).
      AppLogger.instance.log('L3 hardware-vault unlocked', name: 'App');
      return;
    }
    // Dialog dismissed without success. Fire the cancel
    // cascade so the dialog-open `UnlockRequested` lands a
    // paired terminal-state event; idempotent on an already-
    // Locked machine.
    try {
      rust_orch.tierUnlockHardwareCancel();
    } catch (e) {
      AppLogger.instance.log(
        'tier_unlock_hardware_cancel FRB unreachable: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
    await _injectDatabase();
    AppLogger.instance.log(
      'L3 reset — plaintext fallback',
      name: 'App',
      level: LogLevel.warn,
    );
  }

  Future<bool> _showL3UnlockDialog(
    HardwareTierVault vault,
    SecurityTierModifiers? mods, {
    bool autoTriggerBiometric = true,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final l10n = S.of(ctx);
    final limiter = HardwareRateLimiter();
    final key = await _dialogs.showTierSecretUnlock(
      ctx: ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l3UnlockTitle,
        hint: l10n.l3UnlockHint,
        inputLabel: l10n.pinLabel,
        wrongSecretLabel: l10n.l3WrongPin,
      ),
      rateLimiter: limiter,
      verify: (pin) async {
        // Production routes through `tier_unlock_hardware(pin)`
        // which fans out to the platform vault via the prompt
        // registry + emits the cascade. Falls back to direct
        // `vault.read(pin)` for flutter_test contexts (no FRB
        // native lib).
        List<int>? unsealed;
        try {
          unsealed = await rust_orch.tierUnlockHardware(pin: pin);
        } catch (e) {
          AppLogger.instance.log(
            'tier_unlock_hardware FRB unreachable, falling back '
            'to Dart pipeline: $e',
            name: 'App',
          );
          unsealed = await vault.read(pin);
        }
        if (unsealed == null) return null;
        await _injectDatabase(
          key: Uint8List.fromList(unsealed),
          level: SecurityTier.hardware,
          modifiers: mods,
        );
        return unsealed;
      },
      biometricUnlock: () async {
        final key = await _biometricUnlockForTierDialog();
        if (key == null) return null;
        await _injectDatabase(
          key: Uint8List.fromList(key),
          level: SecurityTier.hardware,
          modifiers: mods,
        );
        return key;
      },
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
    return key != null;
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
    final result = await _dialogs.showFirstLaunchWizard(
      fallbackCtx,
      keyStorage: keyStorage,
    );
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
        await _injectDatabase();
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
    final key = await manager.enable(password);
    await _injectDatabase(
      key: key,
      level: SecurityTier.paranoid,
      modifiers: result.modifiers,
    );
    AppLogger.instance.log(
      'First launch: master password (Paranoid) enabled',
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
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(
        key: key,
        level: SecurityTier.keychain,
        modifiers: result.modifiers,
      );
      AppLogger.instance.log(
        'First launch: keychain encryption enabled',
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
    final key = rust_crypto.cryptoAesGcmRandomKey();
    final stored = await keyStorage.writeKey(key);
    if (stored) {
      await _injectDatabase(key: key, level: SecurityTier.keychain);
      AppLogger.instance.log(
        'First launch: auto-selected T1 (keychain)',
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
        'First launch: keychain+password (L2) enabled',
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
        'First launch: hardware vault (L3) sealed',
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
    ref.read(sessionStoreProvider).invalidateCache();
    ref.read(keyStoreProvider).invalidateCache();
    ref.read(knownHostsProvider).invalidateCache();
    if (key != null) {
      ref.read(securityStateProvider.notifier).set(level, key);
    }
    // Open the Rust-owned sqlite handle, keyed off the same master
    // key the tier-derivation step just produced. Failures degrade
    // silently — see ensureRustDbOpen.
    await ensureRustDbOpen(key: key);
    await _persistSecurityTier(level, modifiers);
  }

  Future<Uint8List?> _tryBiometricUnlock() async {
    final bio = ref.read(biometricAuthProvider);
    final reason = localizedBiometricReason();
    final ok = await bio.authenticate(reason);
    if (!ok) return null;
    final vault = ref.read(biometricKeyVaultProvider);
    return vault.read();
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
