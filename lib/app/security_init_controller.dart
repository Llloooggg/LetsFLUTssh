import 'dart:async' show unawaited;
import 'dart:convert' show utf8;
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/db/rust_db_init.dart';
import '../core/security/active_dbkey.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/crypto.dart' as rust_crypto;
import '../src/rust/api/macos_resign.dart' as rust_macos_resign;
import '../src/rust/api/tier_unlock_orchestrator.dart' as rust_orch;
import '../core/migration/migration_runner.dart';
import '../core/security/keychain_password_gate.dart';
import '../core/security/master_password.dart';
import '../core/security/password_rate_limiter.dart';
import '../core/security/process_hardening.dart';
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

// Per-tier unlock + first-launch flows extracted into part siblings.
// Both live as `extension on SecurityInitController` so the helpers
// reach private fields (`_credentialsWereReset`, `_dialogs`, …) and
// private methods (`_injectDatabase`, `_tryBiometricCommit`) without
// going through a public surface; `part of` joins the files into
// the same library so library-private names stay reachable.
part 'security_init_controller_first_launch.dart';
part 'security_init_controller_unlock.dart';

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
/// Signature of the `letsflutssh.db` existence probe. Lets tests flip
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
  /// against the live `letsflutssh.db`. Gates every follow-on query path —
  /// session reloads, auto-lock load — so nothing hits the DB
  /// before the cipher is validated.
  ///
  /// Backed by a [ValueNotifier] so the shell can render a startup
  /// splash overlay until bootstrap finishes (FRB native-lib load +
  /// migrations + tier unlock + DB cipher probe stack). Without the
  /// gate the user sees the empty-workspace skeleton during the few
  /// hundred ms to several seconds the bootstrap takes — reads as
  /// "the app is broken" rather than "loading".
  final ValueNotifier<bool> _readyNotifier = ValueNotifier<bool>(false);

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
  bool get isReady => _readyNotifier.value;

  /// Observable flavour of [isReady] for UI surfaces that need to
  /// rebuild on transitions (the startup splash overlay flips off
  /// when this turns true; reset / wipe paths flip it back to false
  /// briefly while the controller re-runs first-launch).
  ValueListenable<bool> get readiness => _readyNotifier;

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
    _readyNotifier.dispose();
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
    // data. **Don't sequentialise corruption probe → load**: each
    // hits SQLCipher's first-query warm-up cost once, and stacking
    // them adds ~200 ms to cold start on every run. Parallel kicks
    // overlap the warm-up and save roughly that window on plaintext
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
    if (!security.hasActiveDbKey) {
      AppLogger.instance.log(
        'Unlock re-open: active SecretStore slot empty — skipping',
        name: 'App',
      );
      return;
    }
    final modifiers = ref.read(configProvider).security?.modifiers;
    // SecretRef path: `dbInitFromSecret(ACTIVE_DBKEY_SECRET_ID)`
    // reads the staged bytes Rust-internal; `_injectDatabase`'s
    // `setActive` flips the Riverpod tier slot. No bytes cross
    // the FRB boundary outwards.
    await _injectDatabase(
      secretId: kActiveDbKeySecretId,
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
    _readyNotifier.value = false;
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

  /// Surface "configured tier is unreachable" to the user instead of
  /// silently downgrading to the plaintext branch. Called from each
  /// per-tier unlock flow when its vault entry is missing
  /// (`SecureKeyStorage` keychain entry gone, `KeychainPasswordGate`
  /// state file absent, `HardwareTierVault` SE/TPM blob lost).
  ///
  /// Reuses the [DbCorruptDialog] shape because the user-visible
  /// situation matches: the on-disk data cannot be opened with the
  /// security state we have. The previous behaviour fell through to
  /// `_injectDatabase()` which opened the encrypted DB without a
  /// key; the corruption probe then caught the SQLCipher mismatch
  /// and rerouted into the same dialog — but framed as data
  /// corruption rather than security-state loss, leaving a user who
  /// actually had a vault-state problem one click away from
  /// `WipeAllService.wipeAll()`. Surfacing the choice up front keeps
  /// the user informed about what is being wiped and why.
  Future<void> _handleVaultStateMissing(String tierLabel) async {
    // Idempotency probe — every caller arrives here through a
    // listener-timeout fallback (`tierUnlockedListenerWaitTimeout`).
    // If `TierUnlockedListener._handleUnlocked` finished its
    // `ensureRustDbOpen` cascade after the timeout fired but before
    // we got here, the DB is already open and we'd otherwise show
    // the user a corrupt-DB dialog over a perfectly-fine vault —
    // and "Reset and setup fresh" wipes the DB they could just be
    // using. Probe first; only show the dialog when the DB is
    // actually unreadable.
    if (await _verifyReadable()) {
      AppLogger.instance.log(
        'Vault state missing dialog skipped — listener cascade '
        'completed after $tierLabel timeout; DB is readable',
        name: 'App',
      );
      _markSecurityReady();
      return;
    }
    await AppLogger.instance.logCritical(
      'Configured tier ($tierLabel) is unreachable — vault state '
      'missing. Surfacing recovery dialog instead of plaintext fallback.',
      name: 'App',
    );
    final choice = await _dialogs.showDbCorrupt();
    switch (choice) {
      case DbCorruptChoice.exitApp:
        AppLogger.instance.log(
          'Vault state missing — user chose to exit',
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
        configVersion >= 0 && configVersion < currentConfigSchemaVersion();
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
      await _unlockByTier(
        currentSecurity.tier,
        currentSecurity.modifiers,
        manager,
        keyStorage,
      );
      return;
    }

    // Legacy-inference path — no explicit tier field yet.
    if (await manager.isEnabled()) {
      await _unlockParanoid(manager);
      return;
    }
    // SecretRef path: the keychain bytes land directly in the
    // active SecretStore slot Rust-side; `dbInitFromSecret` then
    // opens SQLCipher under them without any FRB byte crossing.
    final loaded = await keyStorage.readKeyToSecret(kActiveDbKeySecretId);
    if (loaded) {
      await _injectDatabase(
        secretId: kActiveDbKeySecretId,
        level: SecurityTier.keychain,
      );
      AppLogger.instance.log('Keychain key loaded', name: 'App');
      return;
    }
    // DB exists but no encryption credentials — plaintext mode.
    await _injectDatabase();
    AppLogger.instance.log('Plaintext mode (existing DB)', name: 'App');
  }

  Future<void> _unlockByTier(
    SecurityTier tier,
    SecurityTierModifiers modifiers,
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    switch (tier) {
      case SecurityTier.hardware:
        await _unlockHardware();
      case SecurityTier.keychain:
        // Bank-style v3: T1+password is `keychain` + `modifiers
        // .password`; the dispatch was previously a dedicated
        // `keychainWithPassword` arm and is now a modifier check
        // inside the keychain arm.
        if (modifiers.password) {
          await _unlockKeychainWithPassword();
        } else {
          await _unlockKeychain();
        }
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
        AppLogger.instance.log('Plaintext mode (tier=T0)', name: 'App');
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
        tierUnlockedListenerWaitTimeout,
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

  /// Read the biometric-vault DB key + commit it through the
  /// `tier_unlock_biometric_commit` shim so the cascade fires +
  /// the `TierUnlockedListener` runs the post-unlock cascade.
  /// Returns true on success, false on plugin-unavailable / wrong-
  /// auth / vault-empty.
  Future<bool> _tryBiometricCommit(SecurityTier tier) async {
    // Live anti-debug gate: a debugger attached to this process can
    // read the just-released DB key out of RAM the moment biometric
    // succeeds. Refuse the shortcut and let the user fall through
    // to the typed-secret form (the typed bytes still cross the
    // FRB boundary once, but the attacker has to social-engineer
    // the user instead of harvesting an OS-stored password).
    // Probe is fail-safe-false on FRB error so a hardened-/proc
    // host can't brick legit unlock.
    if (ProcessHardening.isBeingDebugged()) {
      unawaited(
        AppLogger.instance.logCritical(
          'Biometric unlock refused: debugger attached (tier=${tier.wireName})',
          name: 'ProcessHardening',
        ),
      );
      return false;
    }
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
      // SecretRef path: the vault unseals straight into the active
      // SecretStore slot, the orchestrator commits from there.
      // Bytes never cross the FRB boundary on this path.
      if (!await vault.readToActive()) return false;
      try {
        return rust_orch.tierUnlockBiometricCommitFromSecret(
          tierWireName: tier.wireName,
          secretId: kActiveDbKeySecretId,
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

  // ── DB injection + helpers ────────────────────────────────

  /// Open the encrypted `letsflutssh.db` and commit the active
  /// security tier in Riverpod state.
  ///
  /// [secretId] non-null = encrypted tier. The caller stages the
  /// DB key Rust-side (typically through
  /// `cryptoAesGcmRandomKeyToSecret`, the master-password
  /// `enableToSecret`, the keychain `readToSecret`, or the
  /// hardware-vault `readToSecret` shims). `dbInitFromSecret`
  /// atomically opens SQLCipher under the staged bytes AND
  /// promotes them to `app.dbkey.active` so downstream consumers
  /// (recorder HKDF, biometric vault store, mid-session reopen)
  /// read from the canonical slot.
  ///
  /// [secretId] null = plaintext tier. The active SecretStore
  /// slot is cleared and SQLCipher opens unencrypted.
  ///
  /// Bytes never cross the FRB boundary on this path.
  Future<void> _injectDatabase({
    String? secretId,
    SecurityTier level = SecurityTier.plaintext,
    SecurityTierModifiers? modifiers,
  }) async {
    if (_disposed) return;
    // Open the Rust-owned sqlite handle BEFORE invalidating provider
    // caches. The invalidate triggers a rebuild that calls back into
    // `letsflutssh.db` (`db_sessions_list_all`, `db_ssh_keys_list_metadata`,
    // `db_known_hosts_list`); calling those before `ensureRustDbOpen`
    // returns produces a "db not initialized" error and the providers
    // fall back to empty state. The rebuild has to land AFTER the
    // sqlite handle is up so the first read pulls real rows.
    await ensureRustDbOpen(secretId: secretId);
    // SecurityState records tier + active-slot presence. Plaintext
    // path: `dbInitFromSecret` already dropped the active slot inside
    // `ensureRustDbOpen`; encrypted path: the slot now holds the
    // promoted bytes (`db_init_from_secret` → `secrets.rename(src,
    // ACTIVE)`).
    ref
        .read(securityStateProvider.notifier)
        .setActive(level, hasKey: secretId != null);
    // Stores read/write through FRB into `letsflutssh.db`; the unlock
    // handshake invalidates each store's in-memory cache so the next
    // read pulls fresh rows after the engine swap.
    ref.read(sessionProvider.notifier).invalidateCache();
    ref.read(sshKeysProvider.notifier).invalidateCache();
    ref.read(knownHostsProvider.notifier).invalidateCache();
    await _persistSecurityTier(level, modifiers);
  }

  Future<void> _retryUnlockUnderDifferentTier() async {
    _corruptionRetries++;
    _readyNotifier.value = false;
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
    final sw = Stopwatch()..start();
    void mark(String phase) {
      AppLogger.instance.log(
        'wipe restart phase=$phase elapsed=${sw.elapsedMilliseconds}ms',
        name: 'WipeRestart',
      );
    }

    _readyNotifier.value = false;
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    _safeRustDbClose();
    mark('db_close');
    await WipeAllService(
      credentialCacheEvict: ref.read(sessionCredentialCacheProvider).evictAll,
    ).wipeAll();
    mark('wipe_all');
    await ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWithSecurity(security: null, securityProbeCache: null),
        );
    mark('config_clear');
    _credentialsWereReset = true;
    _corruptionRetries = 0;
    if (!isMounted()) return;
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    await _firstLaunchSetup(manager, keyStorage);
    mark('first_launch_setup');
    if (await _verifyReadable()) {
      _markSecurityReady();
      mark('verify_readable');
    }
  }

  void _markSecurityReady() {
    if (_readyNotifier.value) return;
    _readyNotifier.value = true;
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
