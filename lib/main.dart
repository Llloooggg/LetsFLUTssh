import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:io' show exit;
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'core/config/config_store.dart';
import 'core/shortcut_registry.dart';
import 'core/deeplink/deeplink_handler.dart';
import 'core/single_instance/single_instance.dart';
import 'core/session/qr_codec.dart';
import 'core/db/database.dart';
import 'core/db/database_opener.dart';
import 'core/security/aes_gcm.dart';
import 'core/security/lock_state.dart';
import 'core/security/backup_exclusion.dart';
import 'core/security/process_hardening.dart';
import 'core/security/master_password.dart';
import 'core/security/secure_key_storage.dart';
import 'core/security/security_bootstrap.dart';
import 'core/import/import_service.dart';
import 'core/progress/progress_reporter.dart';
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'features/settings/export_import.dart';
import 'widgets/app_dialog.dart';
import 'widgets/app_selection_area.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/passphrase_dialog.dart';
import 'widgets/auto_lock_detector.dart';
import 'widgets/lock_screen.dart';
import 'widgets/security_setup_dialog.dart';
import 'widgets/tier_secret_unlock_dialog.dart';
import 'widgets/unlock_dialog.dart';
import 'widgets/db_corrupt_dialog.dart';
import 'widgets/first_launch_security_toast.dart';
import 'widgets/tier_reset_dialog.dart';
import 'core/security/hardware_tier_vault.dart';
import 'core/security/keychain_password_gate.dart';
import 'core/security/wipe_all_service.dart';
import 'core/migration/artefacts/config_artefact.dart';
import 'core/migration/migration_runner.dart';
import 'core/migration/registry.dart';
import 'core/migration/schema_versions.dart';
import 'core/security/password_rate_limiter.dart';
import 'core/security/security_tier.dart';
import 'features/settings/security_tier_switcher.dart';
import 'widgets/lfs_import_dialog.dart';
import 'widgets/link_import_preview_dialog.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/app_shell.dart';
import 'widgets/hover_region.dart';
import 'widgets/toast.dart';
import 'features/settings/settings_screen.dart';
import 'features/tools/tools_dialog.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_model.dart';
import 'features/workspace/workspace_controller.dart';
import 'features/workspace/workspace_node.dart';
import 'features/workspace/workspace_view.dart';
import 'providers/auto_lock_provider.dart';
import 'providers/config_provider.dart';
import 'providers/first_launch_banner_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/key_provider.dart';
import 'providers/master_password_provider.dart';
import 'providers/security_provider.dart';
import 'providers/security_reinit_provider.dart';
import 'providers/session_credential_cache_provider.dart';
import 'providers/session_provider.dart';
import 'providers/snippet_provider.dart';
import 'providers/tag_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/update/update_service.dart';
import 'providers/update_provider.dart';
import 'providers/version_provider.dart';
import 'features/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';
import 'utils/format.dart';
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;
import 'utils/sanitize.dart';

/// Global navigator key for showing dialogs from non-UI contexts
/// (e.g., host key verification during SSH handshake).
final navigatorKey = GlobalKey<NavigatorState>();

/// Single-instance lock — kept alive for the process lifetime.
/// The OS releases the file lock automatically on exit (even on crash).
@visibleForTesting
SingleInstance? singleInstanceLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Animation hard-off is layered:
  //   * `_NoTransitionsBuilder` in `AppTheme.pageTransitionsTheme`
  //     kills route push/pop transitions on every platform.
  //   * `disableAnimations: true` on the root `MediaQuery` silences
  //     implicit animations (`AnimatedContainer`, `AnimatedSwitcher`,
  //     `AnimatedOpacity`, etc.) that honour the accessibility flag.
  //   * Widget-level opt-outs for the handful of Material surfaces
  //     that own their own `AnimationController` and ignore the
  //     flag: `Toast` keeps a zero-length controller (no fade /
  //     slide), and every `PopupMenuButton` passes
  //     `popUpAnimationStyle: AnimationStyle.noAnimation`.
  //
  // An earlier `timeDilation = 0.01` blanket scaled every `Ticker`
  // in the framework and caught the offenders above in one line —
  // but it also compressed the scroll-physics simulations
  // (`BouncingScrollPhysics`, `ClampingScrollPhysics`, `PageView`
  // snap, overscroll glow decay) to near-zero, which made mobile
  // swipes feel janky: the finger would release and the list
  // would teleport to its rest position instead of settling
  // smoothly. Physics simulations need real time; animations
  // don't. Split them accordingly instead of nuking both.

  // Unlock the Linux-only subprocess probe (gdbus Peer.Ping against
  // org.freedesktop.secrets) used by SecureKeyStorage.probe. Widget
  // tests do not run this entry point, so the flag stays false for
  // them and the subprocess path is skipped — necessary because
  // Process.run under FakeAsync leaks Timers onto the pending-timer
  // list and breaks unrelated widget tests. Production app sets it
  // here before the first provider evaluates.
  SecureKeyStorage.enableRuntimeSubprocessProbes();

  // Start logger init early — runs in parallel with config/lock I/O below.
  // Log path resolves in background; log() calls buffer to dev.log until ready.
  final loggerInit = AppLogger.instance.init();

  // Global error boundary — catch unhandled Flutter framework errors
  // (build, layout, paint errors — logged but don't show dialog).
  // `logCritical` bypasses the user toggle so crash traces land on
  // disk even when routine logging is disabled, which is exactly the
  // window where a trace matters most.
  FlutterError.onError = (details) {
    final sanitizedMsg = sanitizeErrorMessage(details.exceptionAsString());
    unawaited(
      AppLogger.instance.logCritical(
        'FlutterError: $sanitizedMsg',
        name: 'ErrorBoundary',
        error: details.exception,
        stackTrace: details.stack,
      ),
    );
  };

  // Catch errors that escape the Flutter zone entirely (timers, isolate messages)
  PlatformDispatcher.instance.onError = (error, stack) {
    final sanitizedMsg = sanitizeErrorMessage(error.toString());
    unawaited(
      AppLogger.instance.logCritical(
        'Unhandled platform error: $sanitizedMsg',
        name: 'ErrorBoundary',
        error: error,
        stackTrace: stack,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _showGlobalErrorDialog(ctx, error);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return true;
  };

  // Replace the red error screen with a user-friendly widget
  ErrorWidget.builder = (details) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: const Text(
        'Something went wrong.\n'
        'Try restarting the app.',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: 14, color: Color(0xFFABB2BF)),
      ),
    );
  };

  AppLogger.instance.log('App starting', name: 'App');

  // Disable core dumps and ptrace attach as early as possible — before any
  // secrets touch RAM. Best-effort, swallowed on failure.
  ProcessHardening.applyOnStartup();

  // Opt the app-support directory out of iCloud/iTunes backup (iOS) and
  // Time Machine (macOS) so secrets don't land in untrusted backups.
  // Runs every launch — idempotent, cheap, refreshes the flag if a
  // system action stripped the xattr.
  unawaited(BackupExclusion().applyOnStartup());

  if (plat.isDesktopPlatform) {
    singleInstanceLock = SingleInstance();
    final acquired = await singleInstanceLock!.acquire();
    if (!acquired) {
      AppLogger.instance.log(
        'Another instance detected — showing blocker',
        name: 'App',
      );
      runApp(const _AlreadyRunningApp());
      return;
    }
  }

  // Load config before first frame to prevent light-theme flash.
  // The pre-loaded store is injected via override so ConfigNotifier.build()
  // reads the real config instead of defaults.
  final configStore = ConfigStore();
  final config = await configStore.load();
  await loggerInit; // ensure log path resolved before enabling file logging
  AppLogger.instance.setEnabled(config.enableLogging);

  // Wrap the entire app in runZonedGuarded to catch all async errors.
  // This catches errors from onPressed, Futures, streams, timers, etc.
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          overrides: [configStoreProvider.overrideWithValue(configStore)],
          child: const LetsFLUTsshApp(),
        ),
      );
    },
    (error, stack) {
      final sanitizedMsg = sanitizeErrorMessage(error.toString());
      unawaited(
        AppLogger.instance.logCritical(
          'Unhandled async error: $sanitizedMsg',
          name: 'ErrorBoundary',
          error: error,
          stackTrace: stack,
        ),
      );
      // Show dialog after next frame — ensures Navigator is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showGlobalErrorDialog(ctx, error);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    },
  );
}

/// Shows a user-friendly error dialog for unhandled async errors.
/// Error is already logged by the global error handler — this just shows a brief message.
void _showGlobalErrorDialog(BuildContext context, Object error) {
  final errorType = error.runtimeType.toString();
  final loggingEnabled = AppLogger.instance.enabled;

  try {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return AppDialog(
          title: 'Unexpected Error',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An unexpected error occurred. The app will continue running.',
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
              ),
              const SizedBox(height: 8),
              Text(
                loggingEnabled
                    ? 'Full details have been saved to the log file.'
                    : 'Enable logging in Settings to save error details.',
                style: TextStyle(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Error: $errorType',
                style: TextStyle(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.fgFaint,
                  fontFamily: 'JetBrains Mono',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!loggingEnabled)
              AppDialogAction.secondary(
                label: 'Enable Logging',
                onTap: () {
                  AppLogger.instance.setEnabled(true);
                  AppLogger.instance.log(
                    'Logging enabled after error: $errorType',
                    name: 'ErrorBoundary',
                  );
                  Navigator.of(ctx).pop();
                  Toast.show(
                    ctx,
                    message:
                        'Logging enabled — errors will be saved to log file',
                    level: ToastLevel.success,
                  );
                },
              ),
            AppDialogAction.primary(
              label: 'OK',
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  } catch (e) {
    // If dialog fails to show, at least log it
    AppLogger.instance.log(
      'Failed to show error dialog: $e',
      name: 'ErrorBoundary',
    );
  }
}

class LetsFLUTsshApp extends ConsumerStatefulWidget {
  const LetsFLUTsshApp({super.key});

  @override
  ConsumerState<LetsFLUTsshApp> createState() => _LetsFLUTsshAppState();
}

class _LetsFLUTsshAppState extends ConsumerState<LetsFLUTsshApp> {
  late final AppLifecycleListener _lifecycleListener;

  /// Last value of `securityReinitProvider` we acted on — lets
  /// `listenManual` fire `_reinitSecurityFromReset` only when the
  /// counter goes up, not on the provider's initial read.
  int _lastReinitTick = 0;

  @override
  void initState() {
    super.initState();
    _setupHostKeyCallbacks();
    _lifecycleListener = AppLifecycleListener(
      onRestart: _reloadSessions,
      onResume: _reloadSessions,
    );
    _wireReinitListener();
    _wireLockStateListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Settings → Reset All Data pokes `securityReinitProvider` after
  /// `WipeAllService.wipeAll()` so the app re-enters the same first-
  /// launch provisioning path that runs on a cold-start fresh
  /// install. Without the listener the reset flow would leave the
  /// app in `security: null` with no DB open — every subsequent UI
  /// action would crash on a missing handle.
  void _wireReinitListener() {
    ref.listenManual<int>(securityReinitProvider, (prev, next) {
      if (next <= _lastReinitTick) return;
      _lastReinitTick = next;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _reinitSecurityFromReset();
      });
    });
  }

  /// Re-open the drift / SQLCipher handle after a lock → unlock
  /// transition. `AutoLockDetector._triggerLock` now always closes
  /// the DB (so the C-layer page cipher cache is zeroed alongside
  /// the Dart-side `SecretBuffer`), so every unlock needs a fresh
  /// `_injectDatabase` under the key the lock-screen unlock flow
  /// just pushed back into `securityStateProvider`. Previous-state
  /// gate filters the initial false → false emission plus any
  /// redundant lock→lock transitions.
  void _wireLockStateListener() {
    ref.listenManual<bool>(lockStateProvider, (prev, next) {
      if (prev == true && next == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _reopenDatabaseAfterUnlock();
        });
      }
    });
  }

  /// App bootstrap sequence — run once on the first frame after
  /// `initState`. Split from `initState` so the method body stays
  /// under the S3776 cognitive-complexity threshold and so each
  /// step (migrations, security init, corruption probe, session
  /// load, foreground service, probe warm-up, update check) can
  /// be read top-to-bottom as the startup contract.
  Future<void> _bootstrap() async {
    await ref.read(appVersionProvider.notifier).load();
    // Migration runner gates everything else — a failed or mismatched
    // artefact would make both the unlock flow and the corrupt-DB
    // probe read stale state. When it surfaces a reset, the migration
    // handler runs the full wipe + wizard on its own, so skip the
    // follow-up _initSecurity / corruption probe.
    final migrationOk = await _runMigrations();
    if (!migrationOk) return;
    await _initSecurity();
    // Integrity probe: if the DB file on disk cannot be read under
    // the cipher we just opened it with, the chosen tier does not
    // match the actual file — fall into the reset dialog instead of
    // surfacing drift's "file is not a database" from a later async
    // gap. The user is the only one who can consent to a wipe;
    // `_handleDatabaseCorruption` shows the non-dismissible reset /
    // quit choice and never auto-deletes anything.
    await _handleDatabaseCorruption();
    await ref.read(sessionProvider.notifier).load();
    _maybeShowCredentialsResetToast();
    if (plat.isMobilePlatform) {
      AppLogger.instance.log('Initializing foreground service', name: 'App');
      ref.read(foregroundServiceProvider).init();
    }
    _warmProbeCaches();
    if (ref.read(configProvider).checkUpdatesOnStart) {
      AppLogger.instance.log('Checking for updates on start', name: 'App');
      ref.read(updateProvider.notifier).check();
    }
  }

  void _maybeShowCredentialsResetToast() {
    if (!_credentialsWereReset) return;
    _credentialsWereReset = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Toast.show(
          ctx,
          message: S.of(ctx).credentialsReset,
          level: ToastLevel.warning,
        );
      }
    });
  }

  /// Eager-prefetch the capability + probe snapshots off the main
  /// bootstrap path. `securityCapabilitiesProvider` is a
  /// FutureProvider — the first `ref.watch` on it inside Settings
  /// (or the wizard) would otherwise trigger the deep probes on
  /// the Dart async gap where the user first interacts. With
  /// Android + macOS deep probes now running real SE / Keystore
  /// round-trips, the lazy path made tier cards flash "unavailable
  /// → available" as the probe raced the first frame. Warming the
  /// cache here means Settings opens against ready data — no
  /// flicker. A user-facing "Re-check" button in Settings →
  /// Security invalidates + re-awaits the same cache when the user
  /// wants a fresh result.
  void _warmProbeCaches() {
    unawaited(ref.read(securityCapabilitiesProvider.future));
    unawaited(ref.read(hardwareProbeDetailProvider.future));
    unawaited(ref.read(keyringProbeDetailProvider.future));
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    // Lifecycle `onResume` fires before `_initSecurity` finishes on
    // cold-start + early re-foreground flows. Gating on the explicit
    // ready flag avoids issuing drift queries against a DB whose
    // cipher key is either not yet set or turned out to be wrong —
    // the DB-corruption dialog in `_handleDatabaseCorruption` is the
    // single entry point that authorises unlocked reads.
    if (!_securityReady) return;
    AppLogger.instance.log('App resumed — reloading sessions', name: 'App');
    ref.read(sessionProvider.notifier).load();
  }

  /// True once `_handleDatabaseCorruption` has observed a successful
  /// readability probe on the currently-attached AppDatabase. Gates
  /// every follow-on query path — session reloads, auto-lock load —
  /// so nothing hits the DB before the cipher is validated.
  bool _securityReady = false;

  /// Counts how many times the corruption dialog has fired with the
  /// "try other credentials" option. Limits the recursion so a
  /// genuinely broken file cannot loop forever.
  int _corruptionRetries = 0;
  static const _maxCorruptionRetries = 2;

  /// True when the user chose "forgot password" — used to show a toast
  /// after sessions load (needs l10n context).
  bool _credentialsWereReset = false;

  /// Walk every framework-registered artefact and bring its on-disk
  /// state up to the current build's [SchemaVersions]. Runs BEFORE
  /// `_initSecurity` so the unlock path always reads the post-migration
  /// shape.
  ///
  /// Returns `true` when the startup sequence may continue into
  /// `_initSecurity`; `false` when the failure-handling path has
  /// already taken over (either exiting the app or wiping + re-entering
  /// the first-launch wizard), in which case the caller must stop.
  Future<bool> _runMigrations() async {
    final MigrationReport report;
    try {
      final registry = buildAppMigrationRegistry();
      report = await MigrationRunner(registry).runOnStartup();
    } catch (e, st) {
      // Uncaught migration failure is a crash-class event — the user
      // is about to see the `DbCorruptDialog`, so guarantee the
      // underlying exception lands on disk regardless of the routine
      // logging toggle.
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
      // Reported failure follows the same breadcrumb rule as the
      // uncaught-throw branch above — the `DbCorruptDialog` comes
      // next, so the failure summary must survive even when routine
      // logging is off.
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

  /// Surface a failed or future-version migration as a blocking
  /// corrupt-state dialog. The user picks reset (full wipe + wizard
  /// via [_wipeAndRestartFromScratch]) or exit (leaves disk untouched
  /// so a newer build can re-read the same artefacts). "Try other
  /// credentials" is meaningless at this point — the failure is not
  /// about which key we attempted — so it collapses into the exit
  /// branch.
  Future<void> _handleMigrationFailure() async {
    final choice = await _showDbCorruptDialog();
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

  /// Determine security level on startup.
  ///
  /// First launch is detected by the absence of any data: no master password
  /// salt, no keychain key, and no session files. In that case the
  /// [SecuritySetupDialog] wizard is shown.
  ///
  /// After resolving, injects the encryption key into all three stores
  /// (SessionStore, KeyStore, KnownHostsManager) and updates the global
  /// [securityStateProvider].
  Future<void> _initSecurity() async {
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);

    await _clearPendingTierTransition();

    // Crash-safety: if the previous run started a wipe that did not
    // finish, re-run the full sweep idempotently before anything
    // else touches the app-support dir.
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

    final dbExists = await databaseFileExists();
    if (dbExists) {
      await _unlockExistingDatabase(manager, keyStorage);
      return;
    }

    // No DB file — first launch. Show security setup wizard.
    await _firstLaunchSetup(manager, keyStorage);
  }

  /// Crash-recovery: if the previous run died mid-switch, a
  /// `.tier-transition-pending` marker is still on disk. The switcher
  /// writes the marker *before* PRAGMA rekey, so the DB on disk is
  /// either under the source key (rekey never ran) or under the
  /// target key (rekey ran but wrapper / config write did not).
  /// Completing the pending switch safely requires prompting the
  /// user for the target credential, which the L2 / L3 unlock
  /// paths do not yet ship. For now the marker is cleared here
  /// and the standard unlock flow runs — if it fails the user can
  /// use the forgot-password reset to recover. Deliberate so the
  /// marker never persists across multiple launches into a dirtier
  /// state.
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

  /// Breaking-change gate for upgrades from pre-tier / v1-tier
  /// installs. Returns true when the legacy path took over and
  /// [_initSecurity] must stop; false when no legacy state was
  /// detected and the caller should continue into the normal
  /// DB-exists / first-launch branches.
  ///
  /// Two detection shapes, both route through the same
  /// tier-reset dialog + WipeAllService path:
  ///
  ///   (1) no persisted `security` in config but on-disk artefacts
  ///       exist — an upgrade from a pre-tier build that inferred
  ///       security from file presence alone.
  ///   (2) config exists but its `config_schema_version` is older
  ///       than the current build's target — an upgrade from the v1
  ///       tier model (pre-bank-style-modifier refactor) where the
  ///       native hw-vault ACL shape changes incompatibly. Detecting
  ///       via schema version instead of inspecting individual
  ///       fields keeps the gate simple and tamper-resistant.
  Future<bool> _handleLegacyStateIfPresent(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
    WipeAllService wiper,
  ) async {
    final currentSecurity = ref.read(configProvider).security;
    final configArtefact = ConfigArtefact();
    final configVersion = await configArtefact.readVersion();
    final legacyConfig =
        configVersion >= 0 && configVersion < SchemaVersions.config;
    final orphanArtefacts =
        currentSecurity == null && await wiper.hasAnyState();
    if (!legacyConfig && !orphanArtefacts) return false;
    if (!mounted) return true;
    final choice = await _showTierResetDialog();
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

  /// Existing install unlock path. Prefer the explicit tier persisted
  /// in config.json when present; otherwise fall back to the legacy
  /// infer-from-state path for paranoid / keychain / plaintext.
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
        await _injectDatabase();
        AppLogger.instance.log('Plaintext mode (tier=L0)', name: 'App');
    }
  }

  /// Paranoid (master password) unlock — biometric shortcut first,
  /// then the dialog. Extracted so both the explicit-tier branch and
  /// the legacy-infer fallback reach the same code path.
  Future<void> _unlockParanoid(MasterPasswordManager manager) async {
    var biometricAttempted = false;
    if (await manager.isEnabled()) {
      final vault = ref.read(biometricKeyVaultProvider);
      final bio = ref.read(biometricAuthProvider);
      if (await vault.isStored() && await bio.isAvailable()) {
        biometricAttempted = true;
        final bioKey = await _tryBiometricUnlock();
        if (bioKey != null) {
          await _injectDatabase(key: bioKey, level: SecurityTier.paranoid);
          AppLogger.instance.log(
            'Master password unlocked via biometrics',
            name: 'App',
          );
          return;
        }
      }
    }
    if (!mounted) return;
    final derivedKey = await _showUnlockDialog(
      manager,
      autoTriggerBiometric: !biometricAttempted,
    );
    if (derivedKey != null) {
      await _injectDatabase(key: derivedKey, level: SecurityTier.paranoid);
      AppLogger.instance.log('Master password unlocked', name: 'App');
    } else {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'Master password reset — credentials cleared',
        name: 'App',
      );
    }
  }

  Future<void> _unlockKeychain(SecureKeyStorage keyStorage) async {
    final keychainKey = await keyStorage.readKey();
    if (keychainKey != null) {
      await _injectDatabase(key: keychainKey, level: SecurityTier.keychain);
      AppLogger.instance.log('Keychain key loaded (tier=L1)', name: 'App');
      return;
    }
    // Configured for L1 but the keychain entry is gone — fall back
    // to plaintext so the user can still reach Settings and recover.
    _credentialsWereReset = true;
    await _injectDatabase();
    AppLogger.instance.log(
      'L1 configured but keychain entry missing — plaintext fallback',
      name: 'App',
    );
  }

  /// L2 (keychain + short password) unlock: show the password gate,
  /// verify via [KeychainPasswordGate], then read the DB key from
  /// the OS keychain and inject.
  Future<void> _unlockKeychainWithPassword(SecureKeyStorage keyStorage) async {
    final gate = ref.read(keychainPasswordGateProvider);
    if (!await gate.isConfigured()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L2 configured but gate state missing — plaintext fallback',
        name: 'App',
      );
      return;
    }
    final key = await _showL2UnlockDialog(gate, keyStorage);
    if (key != null) {
      await _injectDatabase(
        key: Uint8List.fromList(key),
        level: SecurityTier.keychainWithPassword,
      );
      AppLogger.instance.log('L2 keychain+password unlocked', name: 'App');
      return;
    }
    await _injectDatabase();
    AppLogger.instance.log('L2 reset — plaintext fallback', name: 'App');
  }

  Future<List<int>?> _showL2UnlockDialog(
    KeychainPasswordGate gate,
    SecureKeyStorage keyStorage,
  ) async {
    // Resolve the persisted rate limiter before touching any context —
    // keeps the use_build_context_synchronously lint happy.
    final limiter = await gate.rateLimiter();
    if (!mounted) return null;
    return _showL2DialogSync(gate, keyStorage, limiter);
  }

  Future<List<int>?> _showL2DialogSync(
    KeychainPasswordGate gate,
    SecureKeyStorage keyStorage,
    PasswordRateLimiter? limiter,
  ) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    final l10n = S.of(ctx);
    return TierSecretUnlockDialog.show(
      ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l2UnlockTitle,
        hint: l10n.l2UnlockHint,
        inputLabel: l10n.password,
        wrongSecretLabel: l10n.l2WrongPassword,
      ),
      rateLimiter: limiter,
      verify: (password) async {
        if (!await gate.verify(password)) return null;
        return keyStorage.readKey();
      },
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        // Fire the same reinit signal the Settings → Reset All Data
        // flow uses. Without it the unlock caller falls through to
        // `_injectDatabase()` (plaintext) and the app ends up in a
        // decrypted-but-empty state; with it, the listener on
        // `_LetsFLUTsshAppState` takes over and re-runs
        // `_firstLaunchSetup` to provision T1 cleanly.
        requestSecurityReinit(ref);
      },
    );
  }

  /// L3 (hardware + PIN) unlock: show the PIN pad, call
  /// [HardwareTierVault.read] which asks the hardware module to
  /// unseal the DB key under `HMAC(salt, pin)`. Hardware rate-limit
  /// is the real brake against brute force.
  ///
  /// Passwordless T2 branch: when `config.security.modifiers.password`
  /// is false the vault sealed the DB key under an empty auth value
  /// at setup time. We skip the PIN pad entirely and unseal with
  /// `pin == null` — matching the store-side derivation. Failures
  /// fall through to the same plaintext-fallback path so a corrupted
  /// vault state still yields a usable (but wiped-style) app rather
  /// than a hung spinner.
  Future<void> _unlockHardware() async {
    final vault = ref.read(hardwareTierVaultProvider);
    if (!await vault.isStored()) {
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 configured but vault state missing — plaintext fallback',
        name: 'App',
      );
      return;
    }
    final mods = ref.read(configProvider).security?.modifiers;
    if (mods != null && !mods.password) {
      final unsealed = await vault.read(null);
      if (unsealed != null) {
        await _injectDatabase(
          key: Uint8List.fromList(unsealed),
          level: SecurityTier.hardware,
          modifiers: mods,
        );
        AppLogger.instance.log(
          'L3 hardware-vault unlocked (passwordless)',
          name: 'App',
        );
        return;
      }
      _credentialsWereReset = true;
      await _injectDatabase();
      AppLogger.instance.log(
        'L3 passwordless unseal failed — plaintext fallback',
        name: 'App',
      );
      return;
    }
    final key = await _showL3UnlockDialog(vault);
    if (key != null) {
      await _injectDatabase(
        key: Uint8List.fromList(key),
        level: SecurityTier.hardware,
        modifiers: mods,
      );
      AppLogger.instance.log('L3 hardware-vault unlocked', name: 'App');
      return;
    }
    await _injectDatabase();
    AppLogger.instance.log('L3 reset — plaintext fallback', name: 'App');
  }

  Future<List<int>?> _showL3UnlockDialog(HardwareTierVault vault) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    final l10n = S.of(ctx);
    // Hardware lockout is the real brake; `HardwareRateLimiter` is a
    // software counter on top of it for defense-in-depth.
    final limiter = HardwareRateLimiter();
    return TierSecretUnlockDialog.show(
      ctx,
      labels: TierSecretUnlockLabels(
        title: l10n.l3UnlockTitle,
        hint: l10n.l3UnlockHint,
        inputLabel: l10n.pinLabel,
        wrongSecretLabel: l10n.l3WrongPin,
      ),
      // T2 used to enforce a 4-6 digit numeric PIN. We now surface
      // the field as a free-form password per user-facing
      // terminology: any characters, any length, so a user who wants
      // a real password (not just a PIN) can set one. The hardware
      // rate limiter still throttles brute force at the TPM / SE
      // layer — length is not the security control.
      rateLimiter: limiter,
      verify: (pin) async {
        final unsealed = await vault.read(pin);
        if (unsealed == null) return null;
        return unsealed;
      },
      onReset: () async {
        await WipeAllService(
          credentialCacheEvict: ref
              .read(sessionCredentialCacheProvider)
              .evictAll,
        ).wipeAll();
        _credentialsWereReset = true;
        // Fire the same reinit signal the Settings → Reset All Data
        // flow uses. Without it the unlock caller falls through to
        // `_injectDatabase()` (plaintext) and the app ends up in a
        // decrypted-but-empty state; with it, the listener on
        // `_LetsFLUTsshAppState` takes over and re-runs
        // `_firstLaunchSetup` to provision T1 cleanly.
        requestSecurityReinit(ref);
      },
    );
  }

  /// First-launch flow: probe the platform, auto-pick the default
  /// tier when the keychain is reachable, fall through to the
  /// wizard only when the user actually needs to make a choice
  /// (no keychain → plaintext vs. Paranoid).
  ///
  /// Auto-select rationale: the overwhelmingly common case — every
  /// desktop with a working libsecret / Credential Manager /
  /// Keychain, every iOS device, every Android with EncryptedSP —
  /// gives us a sane default that "just works" without scaring the
  /// user with a five-option wizard on their first launch. T1
  /// (keychain) protects against the cold-disk-theft case without
  /// a password prompt; T2 and Paranoid remain one tap away in
  /// Settings for users who want stronger binding or zero OS trust.
  Future<void> _firstLaunchSetup(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    if (!mounted) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    var caps = await probeCapabilities(
      keyStorage: keyStorage,
      hardwareVault: ref.read(hardwareTierVaultProvider),
    );
    if (!mounted) return;

    // Auto-setup path: keychain is reachable → silently land on T1
    // and queue the post-setup banner so the user learns what we
    // picked and how to upgrade.
    //
    // Probe reports "available" when the keychain API answered the
    // round-trip at all. On platforms where signing identity matters
    // (notably macOS without an Apple Developer ID cert) the probe
    // can succeed but the first real write fails with an entitlement
    // error surfaced as `PlatformException -34018`. Treat a failed
    // write the same as a failed probe: widen the capabilities
    // snapshot to `keychainAvailable = false` and fall into the
    // wizard, which already handles that branch with the right
    // greyout + tooltip. Previously the write failure silently
    // landed the user on plaintext (T0) with no UI, which looked
    // exactly like a wipe.
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
      );
      caps = caps.copyWith(keychainAvailable: false);
    }

    // Fallback: keychain unreachable. Hand the user the existing
    // wizard — it already greys out T1 / T2 with reason tooltips,
    // so the remaining choice is T0 vs Paranoid.
    final fallbackCtx = navigatorKey.currentContext;
    if (fallbackCtx == null || !fallbackCtx.mounted) return;
    final result = await SecuritySetupDialog.show(
      fallbackCtx,
      keyStorage: keyStorage,
    );
    if (!mounted) return;
    await _applyFirstLaunchWizardResult(
      result: result,
      manager: manager,
      keyStorage: keyStorage,
    );
  }

  /// Apply the user's wizard choice on first launch. Split out of
  /// [_firstLaunchSetup] so the probe + auto-setup flow stays under
  /// the S3776 threshold; each tier branch already delegates to a
  /// named helper (`_firstLaunchHardware`,
  /// `_firstLaunchKeychainWithPassword`) so the switch itself is
  /// pure dispatch.
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
    final key = AesGcm.generateKey();
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
      );
    }
  }

  /// Auto-setup path used on first launch when `caps.keychainAvailable`
  /// is true. Generates a fresh DB key, stores it in the OS keychain,
  /// and injects the database at T1 — zero dialogs, zero prompts.
  /// Falls through to plaintext if the keychain write fails for any
  /// reason (mirror of the existing wizard-path fallback).
  /// Returns true when the keychain write succeeded and the DB is now
  /// attached under T1; false when the write was rejected (caller
  /// owns the fallback — usually "re-open the wizard with T1
  /// greyed"). No side effects on the failure branch: the DB is NOT
  /// injected, no toast is queued, nothing is persisted to
  /// `config.security`. That keeps the caller's follow-on reset /
  /// wizard paths idempotent.
  Future<bool> _autoSetupKeychain(SecureKeyStorage keyStorage) async {
    final key = AesGcm.generateKey();
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
    );
    return false;
  }

  /// Populate [firstLaunchBannerProvider] so the main screen pops a
  /// one-shot dialog informing the user of the tier we picked and
  /// whether a hardware upgrade is reachable. The dialog clears the
  /// provider on dismiss; no persistence — the banner belongs to the
  /// launch where the auto-setup ran.
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

  /// L2 first-launch: configure the keychain password gate, then write
  /// a fresh DB key to the OS keychain.
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
    final key = AesGcm.generateKey();
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
    );
  }

  /// L3 first-launch: generate a DB key, seal it in the hardware vault
  /// under `HMAC(salt, pin)`, and open the DB with that key.
  ///
  /// Passwordless T2 (`pin == null || pin.isEmpty`) is now a first-
  /// class path: the vault seals under an empty auth value instead
  /// of rejecting the secret, and the DB opens under the hardware
  /// tier without prompting for a PIN on future unlocks (the
  /// `SecurityTierModifiers.password = false` flag persisted here
  /// tells the read side to skip the prompt).
  Future<void> _firstLaunchHardware(
    String? pin, [
    SecurityTierModifiers? modifiers,
  ]) async {
    final vault = ref.read(hardwareTierVaultProvider);
    final key = AesGcm.generateKey();
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
    );
  }

  /// Tracks the AppDatabase currently installed in the stores, so the
  /// post-`_initSecurity` readability probe can close it cleanly if
  /// the on-disk file turns out to be unreadable under the chosen
  /// tier's cipher (e.g. `config.security == plaintext` on a DB that
  /// is still encrypted from a pre-tier install).
  AppDatabase? _activeDatabase;

  /// Open the database (with optional encryption) and inject into all stores.
  ///
  /// Awaits `_persistSecurityTier` before returning so the next launch
  /// always sees the resolved tier in `config.json`. A previous
  /// fire-and-forget version raced the OS lifecycle on Android: the
  /// app could be backgrounded after the first-launch wizard before
  /// the atomic config write hit disk, leaving `security_tier`
  /// missing on next launch and the unlock path silently downgrading
  /// to plaintext.
  Future<void> _injectDatabase({
    Uint8List? key,
    SecurityTier level = SecurityTier.plaintext,
    SecurityTierModifiers? modifiers,
  }) async {
    final db = openDatabase(encryptionKey: key);
    _activeDatabase = db;
    ref.read(sessionStoreProvider).setDatabase(db);
    ref.read(keyStoreProvider).setDatabase(db);
    ref.read(knownHostsProvider).setDatabase(db);
    ref.read(snippetStoreProvider).setDatabase(db);
    ref.read(tagStoreProvider).setDatabase(db);
    ref.read(autoLockStoreProvider).setDatabase(db);
    if (key != null) {
      ref.read(securityStateProvider.notifier).set(level, key);
    }
    await _persistSecurityTier(level, modifiers);
    // Auto-lock is loaded only after `_handleDatabaseCorruption`
    // confirms the DB is readable — firing it here would race the
    // probe and surface "file is not a database" through the global
    // error boundary before the user ever sees the corruption dialog.
  }

  /// Attempt to unlock with biometrics. The caller has already checked
  /// that the vault is stashed and the platform reports biometrics ready;
  /// this method invokes the prompt and returns the cached DB key on
  /// success, null on user cancel / auth failure.
  Future<Uint8List?> _tryBiometricUnlock() async {
    final bio = ref.read(biometricAuthProvider);
    final reason = _localizedBiometricReason();
    final ok = await bio.authenticate(reason);
    if (!ok) return null;
    final vault = ref.read(biometricKeyVaultProvider);
    return vault.read();
  }

  /// Show the tier-reset dialog shown once per install to users
  /// coming off the pre-tier security model.
  Future<TierResetChoice> _showTierResetDialog() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(TierResetChoice.exitApp);
    return TierResetDialog.show(ctx);
  }

  /// Show the DB-corruption reset dialog via the synchronously-resolved
  /// navigator context so the BuildContext never escapes an async gap.
  Future<DbCorruptChoice> _showDbCorruptDialog() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(DbCorruptChoice.exitApp);
    return DbCorruptDialog.show(ctx);
  }

  /// Post-`_initSecurity` integrity probe. Runs one trivial SELECT
  /// against the DB we just attached; on failure asks the user
  /// whether to try a different unlock path, wipe and start fresh,
  /// or quit. Never deletes anything without explicit consent — the
  /// destructive branch runs only when the user picks "Reset".
  Future<void> _handleDatabaseCorruption() async {
    final db = _activeDatabase;
    if (db == null) {
      _markSecurityReady();
      return;
    }
    if (await verifyDatabaseReadable(db)) {
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
    final choice = await _showDbCorruptDialog();
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

  /// Clear `config.security` so the legacy-infer branch of
  /// `_initSecurity` (master password probe → keychain probe →
  /// plaintext fall-through) gets a second chance. Capped to
  /// [_maxCorruptionRetries] to avoid a loop when every path is
  /// broken; after the cap the corruption dialog re-fires without
  /// the "try other" button effectively available.
  Future<void> _retryUnlockUnderDifferentTier() async {
    _corruptionRetries++;
    // Gate every DB-backed read while the retry is mid-flight. Drift
    // queries against the closed handle throw
    // `DatabaseClosedException`, and any widget that rebuilds between
    // `db.close()` below and the subsequent `_injectDatabase` inside
    // `_initSecurity` will hit that path. Tests + Android lifecycle
    // callbacks both use `_securityReady` as the "can touch the DB?"
    // gate, so flipping it off reuses the existing guard.
    _securityReady = false;
    final db = _activeDatabase;
    if (db != null) {
      try {
        await db.close();
      } catch (e) {
        AppLogger.instance.log('DB close before retry failed: $e', name: 'App');
      }
    }
    _activeDatabase = null;
    // Clear the cached capability + probe snapshots. The persisted
    // `securityProbeCache` in config.json has to be nulled alongside
    // the in-memory providers — otherwise the next provider read
    // would rehydrate from the stale on-disk snapshot and skip the
    // real probe. The combined update also clears `security: null`,
    // so the same `configProvider.notifier.update` call handles both
    // wipes in one debounced write.
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    await ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWithSecurity(security: null, securityProbeCache: null),
        );
    // Clear the reset-toast flag before re-entering the security
    // pipeline: the nested `_initSecurity` paths set it in half a
    // dozen places (`legacy-orphan wipe`, `_unlockParanoid`,
    // `_firstLaunchHardware`, `_wipeAndRestartFromScratch`), and
    // without the pre-clear the toast can fire twice or leak across
    // the next launch.
    _credentialsWereReset = false;
    AppLogger.instance.log(
      'DB corruption: retrying unlock under legacy-infer path '
      '(attempt $_corruptionRetries/$_maxCorruptionRetries)',
      name: 'App',
    );
    if (!mounted) return;
    await _initSecurity();
    if (!mounted) return;
    if (_corruptionRetries > _maxCorruptionRetries) {
      // Ran out of retries — any further probe failure must go to
      // the destructive / quit branches, so force the dialog without
      // the tryOtherTier option being useful again.
      await _wipeAndRestartFromScratch();
      return;
    }
    await _handleDatabaseCorruption();
  }

  /// Re-open the drift / SQLCipher handle after a lock → unlock
  /// transition. The auto-lock path unconditionally closes the DB
  /// handle so SQLCipher's C-layer page-cipher cache is zeroed
  /// alongside the Dart-side [SecretBuffer]. On unlock the lock
  /// screen re-derives the DB key (paranoid master password path)
  /// or reads it from the biometric vault, pushes it back into
  /// [securityStateProvider], and flips [lockStateProvider] off —
  /// this callback then walks the usual injection path so every
  /// store gets a fresh DB reference. The per-session
  /// [SessionCredentialCache] is Riverpod-scoped and survives the
  /// whole cycle, so live connections reconnect without re-prompting.
  Future<void> _reopenDatabaseAfterUnlock() async {
    if (!mounted) return;
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
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).load();
  }

  /// Re-enter the first-launch provisioning path after a user-driven
  /// wipe completed elsewhere (Settings → Reset All Data). Closes
  /// the stale DB handle, re-runs `_firstLaunchSetup`, and re-probes
  /// the freshly-opened DB for readability. The wipe itself has
  /// already happened at the call site via `WipeAllService.wipeAll`;
  /// this method is only the "now bring the app back to a working
  /// state" half.
  ///
  /// Fired by the listener on [securityReinitProvider] installed in
  /// `initState`. Keeps `_firstLaunchSetup` + `_handleDatabaseCorruption`
  /// private to this state class while still letting the Settings
  /// reset path reach them.
  Future<void> _reinitSecurityFromReset() async {
    if (!mounted) return;
    final db = _activeDatabase;
    if (db != null) {
      try {
        await db.close();
      } catch (e) {
        AppLogger.instance.log(
          'DB close before reinit failed (continuing): $e',
          name: 'App',
        );
      }
    }
    _activeDatabase = null;
    _corruptionRetries = 0;
    _securityReady = false;
    // Drop the cached `FutureProvider` snapshots so Settings UI
    // reads fresh probe results after the reset. Without this the
    // Security tier cards showed the pre-wipe availability + reason
    // strings until the user closed and reopened Settings.
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    if (!mounted) return;
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    await _firstLaunchSetup(manager, keyStorage);
    if (!mounted) return;
    await _handleDatabaseCorruption();
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).load();
  }

  /// Destructive path — user consented to a full wipe. Closes the
  /// broken handle, drops every security artefact via
  /// [WipeAllService], zeroes `config.security`, and re-runs the
  /// first-launch wizard from a clean slate.
  Future<void> _wipeAndRestartFromScratch() async {
    // Same rationale as `_retryUnlockUnderDifferentTier`: block DB
    // reads from any widget that rebuilds while the wipe + re-setup
    // is in flight. Invalidate cached probe snapshots so the first
    // launch wizard sees the current state instead of a pre-wipe
    // cached verdict.
    _securityReady = false;
    ref.invalidate(securityCapabilitiesProvider);
    ref.invalidate(hardwareProbeDetailProvider);
    ref.invalidate(keyringProbeDetailProvider);
    final db = _activeDatabase;
    if (db != null) {
      try {
        await db.close();
      } catch (e) {
        AppLogger.instance.log(
          'DB close before wipe failed (continuing): $e',
          name: 'App',
        );
      }
    }
    _activeDatabase = null;
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
    if (!mounted) return;
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);
    await _firstLaunchSetup(manager, keyStorage);
    // Freshly-opened DB after the wizard — run the probe one more
    // time so the ready flag can flip and lifecycle callbacks can
    // start issuing queries.
    final fresh = _activeDatabase;
    if (fresh != null && await verifyDatabaseReadable(fresh)) {
      _markSecurityReady();
    }
  }

  /// Called exactly once per successful unlock path to flip the
  /// gate that permits DB-backed work: auto-lock loads the persisted
  /// timeout, session lifecycle reloads are no longer short-circuited.
  void _markSecurityReady() {
    if (_securityReady) return;
    _securityReady = true;
    unawaited(ref.read(autoLockMinutesProvider.notifier).load());
  }

  /// Persist the active `SecurityTier` + modifiers into `config.json`
  /// after each successful `_injectDatabase` call. Writing the marker
  /// unconditionally keeps the tier-reset dialog from re-firing on
  /// every launch. L2 (keychain + password) and L3 (Hardware) are
  /// not yet reachable from the current wizard — they become
  /// selectable when the full tier-switcher wiring lands.
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

  /// Resolve the biometric prompt reason string synchronously. Kept
  /// separate so the `BuildContext` never escapes across an await.
  String _localizedBiometricReason() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return 'Unlock LetsFLUTssh';
    return S.of(ctx).biometricUnlockPrompt;
  }

  /// Show unlock dialog using the navigator key context.
  ///
  /// Separated to avoid the `use_build_context_synchronously` lint — the
  /// context is obtained synchronously within this method, not across an
  /// async gap.
  Future<Uint8List?> _showUnlockDialog(
    MasterPasswordManager manager, {
    bool autoTriggerBiometric = true,
  }) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    return UnlockDialog.show(
      ctx,
      manager: manager,
      autoTriggerBiometric: autoTriggerBiometric,
    );
  }

  void _setupHostKeyCallbacks() {
    // Interactive passphrase prompt for encrypted SSH keys.
    final connManager = ref.read(connectionManagerProvider);
    connManager.onPassphraseRequired = (host, attempt) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return null;
      final result = await PassphraseDialog.show(
        ctx,
        host: host,
        attempt: attempt,
      );
      if (result == null) return null;
      return (passphrase: result.passphrase, remember: result.remember);
    };

    final knownHosts = ref.read(knownHostsProvider);
    knownHosts.onUnknownHost = (host, port, keyType, fingerprint) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      return HostKeyDialog.showNewHost(
        ctx,
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    };
    knownHosts.onHostKeyChanged = (host, port, keyType, fingerprint) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      return HostKeyDialog.showKeyChanged(
        ctx,
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));

    _syncThemeBrightness(themeMode);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'LetsFLUTssh',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => _buildAppShell(context, child, uiScale),
      home: const MainScreen(),
    );
  }

  /// Push the resolved brightness into [AppTheme] before the widget
  /// tree consumes it. `ThemeMode.system` reads the platform
  /// brightness so the first frame already matches OS preference.
  void _syncThemeBrightness(ThemeMode themeMode) {
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    AppTheme.setBrightness(isDark ? Brightness.dark : Brightness.light);
  }

  /// [MaterialApp.builder] body: wraps the active route child with
  /// the app-wide MediaQuery overrides, the idle-timer detector, and
  /// the lock overlay. Extracted from [build] so the method stays
  /// readable — the builder closure is the largest piece of the
  /// widget tree and does not need `build`'s local scope.
  Widget _buildAppShell(BuildContext context, Widget? child, double uiScale) {
    final mediaQuery = MediaQuery.of(context);
    final locked = ref.watch(lockStateProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        // Hard-off every animation/transition in the app — route page
        // transitions, Material implicit animations, AnimatedSwitcher,
        // etc. Flutter honours this flag across the framework; we use
        // the same knob the OS "Reduce motion" accessibility toggle
        // would set, applied unconditionally. Keep alongside
        // textScaler so a single MediaQuery wrap controls both
        // signals.
        data: mediaQuery.copyWith(
          textScaler: TextScaler.linear(uiScale),
          disableAnimations: true,
        ),
        // AutoLockDetector wraps the real UI so every pointer/key
        // event resets the idle timer. LockScreen overlays on top
        // with zero hit-test for the app beneath while locked.
        //
        // `SelectionArea` cannot live at this layer — its
        // `SelectableRegion` walks up the widget tree for an
        // `Overlay` ancestor, and `Overlay` is provided by the
        // `Navigator` *inside* MaterialApp's home, i.e. below this
        // builder. A global wrap here fails with "No Overlay widget
        // found". Per-route / per-dialog `SelectionArea` is the only
        // working shape: MainScreen wraps the desktop + mobile
        // shells, `AppDialog` wraps every dialog path, and pushed
        // mobile routes wrap themselves (see
        // `SettingsScreen._MobileSettingsScreen`).
        child: AutoLockDetector(
          child: Stack(
            children: [
              ?child,
              if (locked) const Positioned.fill(child: LockScreen()),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final _deepLinkHandler = DeepLinkHandler();
  bool _updateDialogShown = false;
  bool _sidebarOpen = true;
  final _workspaceKey = GlobalKey<WorkspaceViewState>();
  final _sessionPanelKey = GlobalKey<SessionPanelState>();
  final _sidebarActivated = ValueNotifier<int>(0);

  bool _firstLaunchBannerShown = false;

  @override
  void initState() {
    super.initState();
    _setupDeepLinks();
    _listenForStartupUpdate();
    _listenForFirstLaunchBanner();
  }

  @override
  void dispose() {
    _deepLinkHandler.dispose();
    _sidebarActivated.dispose();
    super.dispose();
  }

  void _listenForStartupUpdate() {
    ref.listenManual(updateProvider, (prev, next) => _handleUpdateState(next));
  }

  /// Watch the in-memory banner provider. When the first-launch
  /// auto-setup runs it writes a [FirstLaunchBannerData]; we pop a
  /// one-shot dialog and clear the state on dismiss so a later
  /// rebuild does not re-open it.
  void _listenForFirstLaunchBanner() {
    ref.listenManual<FirstLaunchBannerData?>(firstLaunchBannerProvider, (
      prev,
      next,
    ) {
      if (next == null || _firstLaunchBannerShown) return;
      _firstLaunchBannerShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        // Top-right toast — the auto-selected tier is a safe default
        // the app already landed on, so a blocking modal would be
        // out of scale for what the user has to do (nothing). The
        // toast surfaces the same copy + the upgrade path when T2
        // is within reach, and auto-dismisses on a timer. The
        // reduced-wizard path (both keychain + hardware out of
        // reach) still routes through the full SecuritySetupDialog
        // modal — that is a real decision the user has to make.
        FirstLaunchSecurityToast.show(
          ctx,
          data: next,
          onOpenSettings: () {
            final inner = navigatorKey.currentContext;
            if (inner == null || !inner.mounted) return;
            if (plat.isMobilePlatform) {
              SettingsScreen.show(inner);
            } else {
              SettingsDialog.show(inner);
            }
          },
          onDismiss: () {
            if (mounted) {
              ref.read(firstLaunchBannerProvider.notifier).set(null);
            }
          },
        );
      });
    }, fireImmediately: true);
  }

  void _handleUpdateState(UpdateState next) {
    if (_updateDialogShown) return;
    if (next.status != UpdateStatus.updateAvailable || next.info == null) {
      return;
    }

    final skipped = ref.read(configProvider).skippedVersion;
    if (skipped != null && skipped == next.info!.latestVersion) return;

    // A newer version supersedes the previously skipped one — clear stale skip.
    if (skipped != null) {
      ref
          .read(configProvider.notifier)
          .update(
            (c) =>
                c.copyWith(behavior: c.behavior.copyWith(skippedVersion: null)),
          );
    }

    _updateDialogShown = true;
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      _showUpdateDialog(ctx, next.info!);
    }
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    final hasAsset = info.assetUrl != null && plat.isDesktopPlatform;
    AppDialog.show(
      context,
      builder: (ctx) => AppDialog(
        title: S.of(ctx).updateAvailable,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S
                  .of(ctx)
                  .updateVersionAvailable(
                    info.latestVersion,
                    info.currentVersion,
                  ),
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            ),
            if (info.changelog != null && info.changelog!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                S.of(ctx).releaseNotes,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppFonts.md,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    info.changelog!,
                    style: TextStyle(
                      fontSize: AppFonts.md,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx)),
          AppDialogAction.secondary(
            label: S.of(ctx).skipThisVersion,
            onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(configProvider.notifier)
                  .update(
                    (c) => c.copyWith(
                      behavior: c.behavior.copyWith(
                        skippedVersion: info.latestVersion,
                      ),
                    ),
                  );
            },
          ),
          _buildPrimaryUpdateAction(ctx, context, info, hasAsset),
        ],
      ),
    );
  }

  Widget _buildPrimaryUpdateAction(
    BuildContext ctx,
    BuildContext outerContext,
    UpdateInfo info,
    bool hasAsset,
  ) {
    if (hasAsset) {
      return AppDialogAction.primary(
        label: S.of(ctx).downloadAndInstall,
        onTap: () {
          Navigator.pop(ctx);
          ref.read(updateProvider.notifier).download(autoInstall: true);
        },
      );
    }
    return AppDialogAction.primary(
      label: S.of(ctx).openInBrowser,
      onTap: () async {
        Navigator.pop(ctx);
        final url = Uri.parse(info.releaseUrl);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          if (outerContext.mounted) {
            Clipboard.setData(ClipboardData(text: info.releaseUrl));
            Toast.show(
              outerContext,
              message: S.of(outerContext).couldNotOpenBrowser,
              level: ToastLevel.warning,
            );
          }
        }
      },
    );
  }

  void _setupDeepLinks() {
    _deepLinkHandler.onConnect = (config) {
      AppLogger.instance.log(
        'Deep link: connect to ${config.displayName}',
        name: 'DeepLink',
      );
      // Defer to next frame — when resuming from background the navigator
      // context may not be available yet on the current frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        final manager = ref.read(connectionManagerProvider);
        final conn = manager.connectAsync(config, label: config.displayName);
        ref.read(workspaceProvider.notifier).addTerminalTab(conn);
      });
    };
    _deepLinkHandler.onLfsFileOpened = (filePath) {
      AppLogger.instance.log(
        'Deep link: LFS file opened — $filePath',
        name: 'DeepLink',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showLfsImportDialog(ctx, filePath);
        }
      });
    };
    _deepLinkHandler.onKeyFileOpened = (filePath) {
      AppLogger.instance.log(
        'Deep link: SSH key file received — $filePath',
        name: 'DeepLink',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Toast.show(
            ctx,
            message: S.of(ctx).sshKeyReceived(filePath.split('/').last),
            level: ToastLevel.info,
          );
        }
      });
    };
    _deepLinkHandler.onQrImport = (data) {
      AppLogger.instance.log(
        'Deep link: QR import — '
        '${data.sessions.length} session(s), '
        '${data.emptyFolders.length} folder(s)',
        name: 'DeepLink',
      );
      _handleQrImport(data);
    };
    _deepLinkHandler.onQrImportVersionTooNew = (found, supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Toast.show(
            ctx,
            message: S.of(ctx).errLfsUnsupportedVersion(found, supported),
            level: ToastLevel.warning,
          );
        }
      });
    };
    _deepLinkHandler.init();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar).
    // SelectionArea sits above MobileShell so every plain Text in
    // the mobile tree supports drag-select + long-press copy.
    if (plat.isMobilePlatform) {
      return const AppSelectionArea(child: MobileShell());
    }

    final ws = ref.watch(workspaceProvider);

    // SelectionArea wraps the desktop layout so every plain Text
    // widget supports drag-select + Ctrl+C like a VSCode panel.
    // Interactive widgets (buttons, switches, session tiles, SFTP
    // rows) keep their own tap / drag gestures because SelectionArea
    // yields to widgets that handle their own pointer events. The
    // terminal (CustomPaint with its own selection logic) renders
    // below the SelectionArea layer and is untouched — xterm keeps
    // its native drag-select.
    return AppSelectionArea(
      child: CallbackShortcuts(
        bindings: _buildKeyBindings(context, ws),
        child: Focus(
          autofocus: true,
          child: DropTarget(
            onDragDone: (details) => _handleLfsDrop(context, details),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildDesktopLayout(context, constraints, ws),
            ),
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(
    BuildContext context,
    WorkspaceState ws,
  ) {
    final notifier = ref.read(workspaceProvider.notifier);
    final focusedPanel = findPanel(ws.root, ws.focusedPanelId);
    final activeTab = focusedPanel?.activeTab;
    final reg = AppShortcutRegistry.instance;

    // Keyboard shortcuts can fire through the lock overlay because
    // the overlay only blocks pointer hit-testing — focus traversal
    // still lets Ctrl+N / Ctrl+, bubble past the LockScreen Focus
    // scope into MainScreen's CallbackShortcuts. Auto-lock closes
    // the encrypted store, so reaching Settings or "new session"
    // while locked would explode inside drift on the first DB read.
    // Short-circuit every shortcut via a common gate — each binding
    // wraps its body so the `if (locked) return` lives once, not
    // once per entry.
    VoidCallback guarded(VoidCallback body) => () {
      if (ref.read(lockStateProvider)) return;
      body();
    };

    return reg.buildCallbackMap({
      AppShortcut.newSession: guarded(() => _newSession(context, ref)),
      AppShortcut.closeTab: guarded(() {
        if (activeTab != null) {
          notifier.closeTab(ws.focusedPanelId, activeTab.id);
        }
      }),
      AppShortcut.nextTab: guarded(() => _switchTab(ws, 1)),
      AppShortcut.prevTab: guarded(() => _switchTab(ws, -1)),
      AppShortcut.toggleSidebar: guarded(
        () => setState(() => _sidebarOpen = !_sidebarOpen),
      ),
      AppShortcut.splitRight: guarded(() {
        if (activeTab != null) {
          notifier.duplicateTab(ws.focusedPanelId);
        }
      }),
      AppShortcut.splitDown: guarded(() {
        if (activeTab != null) {
          notifier.copyToNewPanel(ws.focusedPanelId, Axis.vertical);
        }
      }),
      AppShortcut.maximizePanel: guarded(
        () => notifier.toggleMaximizePanel(ws.focusedPanelId),
      ),
      AppShortcut.openSettings: guarded(() => SettingsDialog.show(context)),
    });
  }

  void _switchTab(WorkspaceState ws, int delta) {
    final panel = findPanel(ws.root, ws.focusedPanelId);
    if (panel != null && panel.tabs.length > 1) {
      final index =
          (panel.activeTabIndex + delta + panel.tabs.length) %
          panel.tabs.length;
      ref.read(workspaceProvider.notifier).selectTab(ws.focusedPanelId, index);
    }
  }

  void _handleLfsDrop(BuildContext context, DropDoneDetails details) {
    final lfsFiles = details.files
        .where((f) => f.path.endsWith('.lfs'))
        .toList();
    if (lfsFiles.isNotEmpty) {
      _showLfsImportDialog(context, lfsFiles.first.path);
    }
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    BoxConstraints constraints,
    WorkspaceState ws,
  ) {
    final isNarrow = constraints.maxWidth < 600;
    final focusedPanel = findPanel(ws.root, ws.focusedPanelId);
    final activeTab = focusedPanel?.activeTab;

    final sidebar = SessionPanel(
      key: _sessionPanelKey,
      onConnect: (session) => _connectSession(context, ref, session),
      onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
      onActivated: () => _sidebarActivated.value++,
    );

    final body = WorkspaceView(
      key: _workspaceKey,
      sidebarActivated: _sidebarActivated,
      onActivated: () => _sessionPanelKey.currentState?.clearDesktopSelection(),
    );

    return AppShell(
      toolbar: _buildToolbar(isNarrow: isNarrow, activeTab: activeTab),
      sidebar: sidebar,
      sidebarOpen: _sidebarOpen,
      useDrawer: isNarrow,
      body: body,
      statusBar: null,
    );
  }

  _Toolbar _buildToolbar({
    required bool isNarrow,
    required TabEntry? activeTab,
  }) {
    final tab = activeTab;
    final hasTab = tab != null;
    return _Toolbar(
      sidebarOpen: _sidebarOpen,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      showMenuButton: isNarrow,
      isTerminalTab: hasTab,
      onDuplicateTab: hasTab
          ? () {
              final ws = ref.read(workspaceProvider);
              ref
                  .read(workspaceProvider.notifier)
                  .duplicateTab(ws.focusedPanelId);
            }
          : null,
      onDuplicateDown: hasTab
          ? () {
              final ws = ref.read(workspaceProvider);
              ref
                  .read(workspaceProvider.notifier)
                  .copyToNewPanel(ws.focusedPanelId, Axis.vertical);
            }
          : null,
      onTools: () => ToolsDialog.show(context),
      onSettings: () => SettingsDialog.show(context),
    );
  }

  Future<void> _connectSessionSftp(
    BuildContext context,
    WidgetRef ref,
    session,
  ) => SessionConnect.connectSftp(context, ref, session);

  Future<void> _connectSession(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectTerminal(context, ref, session);

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final result = await SessionEditDialog.show(context);
    if (result == null || !context.mounted) return;
    switch (result) {
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect && context.mounted) {
          await SessionConnect.connectTerminal(context, ref, session);
        }
    }
  }

  Future<void> _handleQrImport(ExportPayloadData data) async {
    // Ask the user what to bring in before writing anything — mirrors the
    // .lfs and paste-link flows so QR imports aren't the only path that
    // silently clobbers merge/replace choices and data-type selection.
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final choice = await LinkImportPreviewDialog.show(ctx, payload: data);
    if (choice == null) return;

    // Build the full ImportResult from the payload, then let
    // [ImportResult.filtered] drop whatever the user unchecked.
    final fullResult = ImportResult(
      sessions: data.sessions,
      emptyFolders: data.emptyFolders,
      managerKeys: data.managerKeys,
      tags: data.tags,
      sessionTags: data.sessionTags,
      folderTags: data.folderTags,
      snippets: data.snippets,
      sessionSnippets: data.sessionSnippets,
      config: data.config,
      mode: choice.mode,
      knownHostsContent: data.knownHostsContent,
      includeTags: data.tags.isNotEmpty,
      includeSnippets: data.snippets.isNotEmpty,
      includeKnownHosts: data.knownHostsContent != null,
    );
    final importResult = fullResult.filtered(choice.options, choice.mode);

    try {
      final summary = await _buildImportService().applyResult(importResult);
      _invalidateImportProviders();

      AppLogger.instance.log(
        'QR import complete: ${summary.sessions} session(s), '
        '${summary.managerKeys} key(s), '
        '${summary.tags} tag(s), '
        '${summary.snippets} snippet(s)',
        name: 'App',
      );

      // Context may have been torn down during the import await — re-read
      // off the global navigator key so we don't paint onto a disposed tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final postCtx = navigatorKey.currentContext;
        if (postCtx != null && postCtx.mounted) {
          Toast.show(
            postCtx,
            message: formatImportSummary(S.of(postCtx), summary),
            level: ToastLevel.success,
          );
        }
      });
    } catch (e) {
      AppLogger.instance.log('QR import failed: $e', name: 'App', error: e);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final postCtx = navigatorKey.currentContext;
        if (postCtx != null && postCtx.mounted) {
          Toast.show(
            postCtx,
            message: S
                .of(postCtx)
                .importFailed(localizeError(S.of(postCtx), e)),
            level: ToastLevel.error,
          );
        }
      });
    }
  }

  Future<void> _showLfsImportDialog(
    BuildContext context,
    String filePath,
  ) async {
    AppLogger.instance.log(
      'LFS import started: ${filePath.split('/').last}',
      name: 'App',
    );
    // Classify the file before any prompt. Rejects non-LFS content
    // (e.g. an .apk picked by mistake — Android SAF ignores the .lfs
    // extension filter) and lets us skip the password prompt for
    // unencrypted (plain-ZIP) exports.
    final kind = ExportImport.probeArchive(filePath);
    if (kind == LfsArchiveKind.notLfs) {
      Toast.show(
        context,
        message: S.of(context).errLfsNotArchive,
        level: ToastLevel.error,
      );
      return;
    }
    final result = await LfsImportDialog.show(
      context,
      filePath: filePath,
      isEncrypted: kind == LfsArchiveKind.encryptedLfs,
    );
    if (result == null || !context.mounted) return;

    // Show progress bar while Argon2id + decryption run in isolate and
    // the subsequent per-store writes stream step counts back to the UI.
    final l10n = S.of(context);
    final progress = ProgressReporter(l10n.progressReadingArchive);
    AppProgressBarDialog.show(context, progress);
    var progressShown = true;

    try {
      final importResult = await ExportImport.import_(
        filePath: filePath,
        masterPassword: result.password,
        mode: result.mode,
        options: const ExportOptions(
          includeSessions: true,
          includeConfig: true,
          includeKnownHosts: true,
          includeManagerKeys: true,
          includeTags: true,
          includeSnippets: true,
        ),
        progress: progress,
        l10n: l10n,
      );

      final summary = await _buildImportService().applyResult(
        importResult,
        progress: progress,
        l10n: l10n,
      );
      _invalidateImportProviders();

      AppLogger.instance.log(
        'LFS import success: ${summary.sessions} session(s)',
        name: 'App',
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
        Toast.show(
          context,
          message: formatImportSummary(S.of(context), summary),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('LFS import failed: $e', name: 'App', error: e);
      if (progressShown && context.mounted) {
        Navigator.of(context).pop();
        progressShown = false;
      }
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    } finally {
      if (progressShown && context.mounted) {
        Navigator.of(context).pop();
      }
      progress.dispose();
    }
  }

  /// Refresh all cached FutureProviders after a QR or LFS import so the UI
  /// picks up newly imported keys, tags and snippets without an app restart.
  void _invalidateImportProviders() {
    ref.invalidate(sshKeysProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(snippetsProvider);
  }

  ImportService _buildImportService() {
    final store = ref.read(sessionStoreProvider);
    final keyStore = ref.read(keyStoreProvider);
    final tagStore = ref.read(tagStoreProvider);
    final snippetStore = ref.read(snippetStoreProvider);
    final knownHostsMgr = ref.read(knownHostsProvider);
    return ImportService(
      addSession: (s) => ref.read(sessionProvider.notifier).add(s),
      addEmptyFolder: (f) => store.addEmptyFolder(f),
      deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
      getSessions: () => ref.read(sessionProvider),
      applyConfig: (config) =>
          ref.read(configProvider.notifier).update((_) => config),
      saveManagerKey: (entry) => keyStore.importForMerge(entry),
      saveTag: (tag) async {
        await tagStore.add(tag);
        return tag.id;
      },
      tagSession: tagStore.tagSession,
      tagFolder: (folderId, tagId) => tagStore.tagFolder(folderId, tagId),
      saveSnippet: (snippet) async {
        await snippetStore.add(snippet);
        return snippet.id;
      },
      linkSnippetToSession: snippetStore.linkToSession,
      getEmptyFolders: () => store.emptyFolders,
      restoreSnapshot: (sessions, folders) =>
          store.restoreSnapshot(sessions, folders),
      existingTagIds: () async =>
          (await tagStore.loadAll()).map((t) => t.id).toSet(),
      existingSnippetIds: () async =>
          (await snippetStore.loadAll()).map((s) => s.id).toSet(),
      getCurrentConfig: () => ref.read(configProvider),
      loadAllTags: () => tagStore.loadAll(),
      deleteAllTags: () => tagStore.deleteAll(),
      loadAllSnippets: () => snippetStore.loadAll(),
      deleteAllSnippets: () => snippetStore.deleteAll(),
      exportKnownHosts: () => knownHostsMgr.exportToString(),
      clearKnownHosts: () => knownHostsMgr.clearAll(),
      importKnownHosts: (content) async {
        await knownHostsMgr.importFromString(content);
      },
      existingManagerKeyIds: () async =>
          (await keyStore.loadAll()).keys.toSet(),
      deleteManagerKey: keyStore.delete,
      runInTransaction: store.database == null
          ? null
          : <T>(body) => store.database!.transaction(body),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final bool showMenuButton;
  final bool isTerminalTab;
  final VoidCallback? onDuplicateTab;
  final VoidCallback? onDuplicateDown;
  final VoidCallback onTools;
  final VoidCallback onSettings;

  const _Toolbar({
    required this.sidebarOpen,
    required this.onToggleSidebar,
    this.showMenuButton = false,
    this.isTerminalTab = false,
    this.onDuplicateTab,
    this.onDuplicateDown,
    required this.onTools,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 2),
        if (showMenuButton)
          AppIconButton(
            icon: Icons.menu,
            onTap: () => Scaffold.of(context).openDrawer(),
            tooltip: S.of(context).sessions,
            color: AppTheme.fgDim,
          )
        else
          AppIconButton(
            icon: sidebarOpen ? Icons.chevron_left : Icons.chevron_right,
            onTap: onToggleSidebar,
            tooltip: sidebarOpen
                ? S.of(context).hideSidebar
                : S.of(context).showSidebar,
          ),
        _TextButton(label: S.of(context).tools, onTap: onTools),
        _TextButton(label: S.of(context).settings, onTap: onSettings),
        const Spacer(),
        if (isTerminalTab) ...[
          AppIconButton(
            icon: Icons.content_copy,
            onTap: onDuplicateTab,
            tooltip: S.of(context).duplicateTabShortcut,
          ),
          AppIconButton(
            icon: Icons.horizontal_split,
            onTap: onDuplicateDown,
            tooltip: S.of(context).duplicateDownShortcut,
          ),
        ],
        const SizedBox(width: 2),
      ],
    );
  }
}

/// VS Code-style text button for the toolbar.
class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TextButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // `HoverRegion` auto-disables selection on its child when a
    // gesture is bound (see `widgets/hover_region.dart`), so the
    // toolbar Tools / Settings labels stay outside the ambient
    // `SelectionArea` without an explicit wrap.
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) => Container(
        height: AppTheme.controlHeightXs,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: hovered ? AppTheme.hover : Colors.transparent,
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
      ),
    );
  }
}

/// Minimal app shown when another instance is already running.
class _AlreadyRunningApp extends StatelessWidget {
  const _AlreadyRunningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 48, color: AppTheme.fgDim),
              const SizedBox(height: 16),
              Text(
                'Another instance of LetsFLUTssh is already running.',
                style: TextStyle(fontSize: AppFonts.lg),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => exit(0), child: const Text('OK')),
            ],
          ),
        ),
      ),
    );
  }
}
