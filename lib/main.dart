import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'app/already_running_app.dart';
import 'app/app_toolbar.dart';
import 'app/deep_link_wiring.dart';
import 'app/fatal_error_app.dart';
import 'app/host_key_prompt_listener.dart';
import 'app/hardware_vault_probe_prompt_listener.dart';
import 'app/hardware_vault_seal_prompt_listener.dart';
import 'app/hardware_vault_unlock_prompt_listener.dart';
import 'app/keychain_probe_prompt_listener.dart';
import 'app/tier_state_observer.dart';
import 'app/global_error_dialog.dart';
import 'app/import_flow.dart';
import 'app/navigator_key.dart';
import 'app/security_init_controller.dart';
import 'app/update_dialog_flow.dart';
import 'widgets/shortcut_registry.dart';
import 'core/deeplink/deeplink_handler.dart';
import 'core/single_instance/single_instance.dart';
import 'core/security/backup_exclusion.dart';
import 'core/security/lock_state.dart';
import 'core/security/process_hardening.dart';
import 'core/security/secure_key_storage.dart';
import 'features/mobile/mobile_shell.dart';
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'features/session_manager/session_panel.dart';
import 'features/settings/settings_screen.dart';
import 'features/tabs/tab_model.dart';
import 'features/tools/tools_dialog.dart';
import 'features/workspace/workspace_controller.dart';
import 'features/workspace/workspace_node.dart';
import 'features/workspace/workspace_view.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/first_launch_banner_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/security_provider.dart';
import 'providers/security_reinit_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';
import 'providers/version_provider.dart';
import 'theme/app_theme.dart';
import 'src/rust/api.dart' as rust_core;
import 'src/rust/api/app.dart' as rust_app;
import 'src/rust/frb_generated.dart' show RustLib;
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;
import 'utils/sanitize.dart';
import 'widgets/app_shell.dart';
import 'widgets/auto_lock_detector.dart';
import 'widgets/first_launch_security_toast.dart';
import 'widgets/lock_screen.dart';
import 'widgets/toast.dart';

// LetsFLUTsshApp + MainScreen live in part siblings so the entry-point
// scaffolding (main, _mainBody, error handlers, single-instance,
// config preload) stays the focus of this file. Same `part of`
// pattern the settings_screen / session_panel split uses.
part 'main_app.dart';
part 'main_screen.dart';

/// Single-instance lock — kept alive for the process lifetime.
/// The OS releases the file lock automatically on exit (even on crash).
@visibleForTesting
SingleInstance? singleInstanceLock;

Future<void> main() async {
  // `WidgetsFlutterBinding.ensureInitialized()` must be called inside
  // the same zone as `runApp` — otherwise Flutter warns about a zone
  // mismatch on every launch and widget-test crashes blame the wrong
  // zone. Wrap everything below in `runZonedGuarded` from the very
  // first statement so both the binding init and the eventual
  // `runApp` share the custom zone.
  runZonedGuarded(_mainBody, (error, stack) {
    // Global error boundary — routes through AppLogger then into the
    // in-app dialog. Kept as a top-level Zone error handler so async
    // errors outside the widget tree (Futures, Streams, Timers) are
    // caught.
    unawaited(
      AppLogger.instance.logCritical(
        'Uncaught zone error: $error',
        name: 'ErrorBoundary',
        error: error,
        stackTrace: stack,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showGlobalErrorDialog(ctx, error);
      }
    });
  });
}

Future<void> _mainBody() async {
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
        showGlobalErrorDialog(ctx, error);
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

  // Rust security/transport core — load the bundled native blob and
  // verify the Dart bindings match. See ARCHITECTURE.md §3.14 +
  // docs/RUST_CORE_MIGRATION_PLAN.md. Every SSH/SFTP/keypair/crypto
  // call routes through here; failure to load is fatal — without
  // the core, every subsequent FRB call throws, and the migration
  // runner interprets those throws as a corrupt-DB signal. That
  // routes the user into `DbCorruptDialog` whose "Reset and start
  // fresh" button calls `WipeAllService.wipeAll()` — destroying
  // their data because of what is usually a transient packaging
  // issue. Bail out to a dedicated fatal screen instead so the
  // wipe path is unreachable.
  try {
    await RustLib.init();
    // Initialise the AppState singleton in lfs_core. Subsequent
    // commands (secrets_*, sessions/connections/forwards) attach to
    // it. Idempotent.
    await rust_app.appInit();
    AppLogger.instance.log(
      'Rust core loaded: ${rust_core.ping()}',
      name: 'RustCore',
    );
  } catch (e, st) {
    await AppLogger.instance.logCritical(
      'Rust core failed to load — bailing to fatal screen: $e',
      name: 'RustCore',
      error: e,
      stackTrace: st,
    );
    runApp(
      const FatalErrorApp(
        summary: 'LetsFLUTssh cannot start.',
        detail:
            'The bundled native core failed to load. This usually means the '
            'application bundle is incomplete or incompatible with this '
            'platform. Reinstalling the app should restore it. Your saved '
            'sessions and data are not affected.',
      ),
    );
    return;
  }

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
      runApp(const AlreadyRunningApp());
      return;
    }
  }

  // Load config before first frame to prevent light-theme flash.
  // The pre-loaded value is injected via [preloadedAppConfigProvider]
  // so ConfigNotifier.build() seeds state with it instead of falling
  // back to AppConfig.defaults.
  final loaded = await loadAppConfigFromDisk();
  final config = loaded.config;
  await loggerInit; // ensure log path resolved before enabling file logging
  // `--dart-define=LETSFLUTSSH_LOG_LEVEL=<level>` overrides the on-
  // disk config on dev / beta-tester builds so fresh installs start
  // with logs enabled without a Settings-tweak round-trip. Release
  // builds ship without the flag → we honour whatever the user
  // stored in config.json (default: null / off).
  await AppLogger.instance.setThreshold(
    buildTimeLogLevelOverride ?? config.logLevel,
  );

  // Already running inside `runZonedGuarded` from the outer `main()` —
  // launch the app directly; zone errors are routed through the outer
  // handler. Previously we opened a second nested `runZonedGuarded`
  // here, but Flutter's `WidgetsBinding.ensureInitialized` (called at
  // the top of `_mainBody`) must execute in the same zone as the
  // final `runApp` or the framework logs "Zone mismatch" on every
  // startup. Collapsing the two zone-guards into the single outer
  // one fixes that.
  runApp(
    ProviderScope(
      overrides: [preloadedAppConfigProvider.overrideWithValue(config)],
      child: const LetsFLUTsshApp(),
    ),
  );
}
