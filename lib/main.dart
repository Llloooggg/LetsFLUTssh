import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:package_info_plus/package_info_plus.dart';

import 'l10n/app_localizations.dart';
import 'app/app_toolbar.dart';
import 'app/connection_state_announcer.dart';
import 'app/deep_link_wiring.dart';
import 'app/credential_prompt_listener.dart';
import 'app/fatal_error_app.dart';
import 'app/host_key_prompt_listener.dart';
import 'app/hardware_vault_probe_prompt_listener.dart';
import 'app/hardware_vault_seal_prompt_listener.dart';
import 'app/hardware_vault_unlock_prompt_listener.dart';
import 'app/keychain_probe_prompt_listener.dart';
import 'app/recovery_prompt_listener.dart';
import 'app/ssh_agent_prompt_listener.dart';
import 'app/tier_state_observer.dart';
import 'app/global_error_dialog.dart';
import 'app/import_flow.dart';
import 'app/navigator_key.dart';
import 'app/security_init_controller.dart';
import 'app/update_dialog_flow.dart';
import 'widgets/core/shortcut_registry.dart';
import 'core/bus/app_bus.dart';
import 'core/security/backup_exclusion.dart';
import 'core/security/kdf_params.dart';
import 'core/session/session.dart';
import 'providers/lock_state.dart';
import 'core/security/process_hardening.dart';
import 'core/security/session_lock_listener.dart';
import 'features/mobile/mobile_shell.dart';
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'features/session_manager/session_panel.dart';
import 'features/session_manager/session_save_persistence.dart';
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
import 'providers/log_store_provider.dart';
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
import 'widgets/core/app_shell.dart';
import 'widgets/security/auto_lock_detector.dart';
import 'widgets/security/first_launch_security_toast.dart';
import 'widgets/security/lock_screen.dart';
import 'widgets/core/toast.dart';

// LetsFLUTsshApp + MainScreen live in part siblings so the entry-point
// scaffolding (main, _mainBody, error handlers, config preload) stays
// the focus of this file. Same `part of` pattern the settings_screen /
// session_panel split uses.
part 'main_app.dart';
part 'main_screen.dart';

/// Load the bundled native blob, initialise the Rust AppState
/// singleton, wire the config-store actor, attach the Rust→Dart log
/// pipe, and apply process hardening. Returns `true` when the core
/// is ready and `_mainBody` should continue, `false` when load
/// failed and the caller replaced the widget tree with [FatalErrorApp].
///
/// Runs **before** `loadAppConfigFromDisk` + `runApp` from inside
/// `_mainBody` so the config load route can snapshot the Rust
/// `config_store` actor instead of touching `dart:io File` itself.
/// The narrow pre-FRB window collapses to the few ms spent inside
/// `RustLib.init()`; `logCritical` writes during that window still
/// buffer through `_preFrbCriticalBuffer` and drain via
/// [AppLogger.onFrbReady] right after this function returns.
///
/// Failure-mode escape valve: every SSH / SFTP / keypair / crypto
/// call routes through here, and a missing core makes downstream
/// FRB calls throw. The migration runner catches those throws and
/// routes the user into `DbCorruptDialog` whose "Reset and start
/// fresh" button calls `WipeAllService.wipeAll()` — destroying their
/// data over what is usually a transient packaging issue. Bail to a
/// dedicated fatal screen instead so the wipe path is unreachable.
///
/// **Don't move this call later than `_mainBody`.** Splitting the
/// Rust core load off the pre-`runApp` slice would mean the first
/// frame paints before the user's saved theme is read (silent
/// theme-flash regression) and would re-introduce the Dart-side
/// `dart:io File.readAsString` on `config.json` the load route
/// dropped.
Future<bool> _initRustCoreOrFatal() async {
  // Track which sub-steps landed so the catch arm can roll the
  // pieces back in reverse order. A partial init that leaks the
  // RustLib + AppState handles into the fatal screen kept the
  // native blob mapped + the singleton alive — a clean re-launch
  // attempt would either re-init twice (now caught above) or
  // serve stale state.
  var rustLibInitialised = false;
  var appInited = false;
  try {
    // `RustLib.init()` throws "Should not initialize twice" on a
    // re-entry — that happens under flutter_test where
    // `requireFrbLoaded()` already ran in `setUpAll`. Tolerate that
    // specific shape and continue; every other StateError /
    // load-time failure still routes through the catch below and
    // lands on FatalErrorApp.
    try {
      await RustLib.init();
      rustLibInitialised = true;
    } on StateError catch (e) {
      if (!e.message.contains('Should not initialize')) rethrow;
      AppLogger.instance.log(
        'RustLib already initialised — skipping re-init',
        name: 'RustCore',
      );
      // Already initialised in this process — treat as ours so the
      // rollback in the catch arm reaches it the same way.
      rustLibInitialised = true;
    }
    // Initialise the AppState singleton in lfs_core. Subsequent
    // commands (secrets_*, sessions/connections/forwards) attach
    // to it. Idempotent.
    await rust_app.appInit();
    appInited = true;
    // Wire the Rust `lfs_core::config_store::Store` actor so
    // `loadAppConfigFromDisk` (next step in `_mainBody`) parses
    // through the Rust-side `AppConfig::from_json_value` sanitizer
    // and subsequent `ConfigNotifier.save` calls land via the
    // atomic-write path.
    await bootstrapRustConfigStore();
    // Wire the Rust→Dart log pipe — every `lfs_core::app_log` call
    // gets folded into the same on-disk `letsflutssh.log` the
    // Dart-side AppLogger writes through. Must be after `app_init`
    // because `bus_subscribe` reaches into `lfs_core::app::instance()`.
    AppLogger.instance.attachCoreLogPipe();
    AppLogger.instance.log(
      'Rust core loaded: ${rust_core.ping()}',
      name: 'RustCore',
    );
    // Disable core dumps + ptrace attach as early as possible —
    // before any secrets touch RAM. Best-effort, swallowed on
    // failure.
    ProcessHardening.applyOnStartup();
    // Forensic breadcrumb: a debugger attached *despite* the
    // hardening pass landed (debug-signed macOS bundle / Linux
    // host with `cap_sys_ptrace` / Xcode-attached dev build).
    // Logged via `logCritical` so the trail survives the opt-in
    // file-sink gate; the live gate that actually refuses
    // biometric unlock lives in `_tryBiometricCommit`.
    if (ProcessHardening.isBeingDebugged()) {
      unawaited(
        AppLogger.instance.logCritical(
          'Debugger attached at startup — biometric unlock will refuse '
          'until detach (tier secrets force typed-secret entry)',
          name: 'ProcessHardening',
        ),
      );
    }
    return true;
  } on AppConfigParseException {
    // Surfaced by `bootstrapRustConfigStore` when the on-disk
    // `config.json` exists but does not parse. Route to the
    // config-corrupt fatal screen the caller in `_mainBody`
    // owns, not the native-blob fatal screen below — the user's
    // recovery is "delete or restore the settings file", not
    // "reinstall the app".
    rethrow;
  } catch (e, st) {
    await AppLogger.instance.logCritical(
      'Rust core failed to load — bailing to fatal screen: $e',
      name: 'RustCore',
      error: e,
      stackTrace: st,
    );
    // Roll back any sub-steps that landed before the failure. The
    // FRB-side `appInit` / `bootstrapRustConfigStore` are idempotent
    // and don't expose an explicit teardown — the native blob's
    // `RustLib.dispose()` is what actually frees the singleton +
    // releases the dynamic library. Best-effort: a failing dispose
    // is swallowed and the FatalErrorApp screen still paints, so
    // the user has a recovery surface even if the library is stuck
    // mapped.
    if (appInited) {
      // Nothing exposes a Rust-side `app_state.shutdown()` yet —
      // the AppState singleton is reclaimed when RustLib.dispose
      // unloads the native blob below.
    }
    if (rustLibInitialised) {
      try {
        RustLib.dispose();
      } catch (disposeErr) {
        AppLogger.instance.log(
          'RustLib.dispose during fatal rollback failed: $disposeErr',
          name: 'RustCore',
          level: LogLevel.warn,
        );
      }
    }
    runApp(
      const FatalErrorApp(
        summary: _fatalStartSummary,
        detail:
            'The bundled native core failed to load. This usually means the '
            'application bundle is incomplete or incompatible with this '
            'platform. Reinstalling the app should restore it. Your saved '
            'sessions and data are not affected.',
      ),
    );
    return false;
  }
}

/// Summary shown by [FatalErrorApp] on every unrecoverable cold-start
/// path (native-core load failure, fatal rollback, init crash).
const _fatalStartSummary = 'LetsFLUTssh cannot start.';

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

  // Bootstrap `package:intl` per-locale symbol tables once.
  // Locale-aware `DateFormat` constructors throw
  // `LocaleDataException` until the table for the requested locale
  // is loaded, which would crash `formatTimestamp(dt, locale: ...)`
  // the first time a user with a non-default locale opened the
  // file pane. `initializeDateFormatting()` with no args loads every
  // locale's symbols (~80 KB) — runs once at startup, sub-millisecond.
  await initializeDateFormatting();

  // Start logger init early — runs in parallel with config/lock I/O below.
  // `init()` only resolves `<app_support>/logs/letsflutssh.log` via
  // `path_provider`; the Rust-side sink (open / append / chmod) wakes
  // up lazily on the first `setThreshold` flip after FRB loads.
  // Pre-FRB `logCritical` writes buffer in memory + mirror to stderr;
  // `AppLogger.onFrbReady` (called below right after
  // `_initRustCoreOrFatal` lands) drains the buffer through Rust.
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        'Something went wrong.\n'
        'Try restarting the app.',
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      ),
    );
  };

  // Eager smoke-touch of critical singletons whose field
  // initializers run on first access. Triggering them here —
  // after FlutterError / PlatformDispatcher / Zone error
  // handlers are installed — converts a silent VM abort during
  // field init into a logCritical entry the watchdog can
  // capture.
  try {
    AppLogger.instance.liveEntries;
  } catch (e, st) {
    unawaited(
      AppLogger.instance.logCritical(
        'AppLogger live-stream smoke-touch failed',
        name: 'BootSmoke',
        error: e,
        stackTrace: st,
      ),
    );
    rethrow;
  }

  AppLogger.instance.log('App starting', name: 'App');

  // Single-instance enforcement happens in the native shell BEFORE
  // the Flutter engine boots, so a duplicate launch is rejected
  // without paying for engine init + Dart bootstrap:
  //   - Windows (`windows/runner/main.cpp`): a `Local\…` named mutex;
  //     the second launch sees `ERROR_ALREADY_EXISTS`, shows a native
  //     `MessageBoxW`, and exits.
  //   - Linux (`linux/runner/my_application.cc`): GtkApplication D-Bus
  //     uniqueness (no `G_APPLICATION_NON_UNIQUE`); the remote launch
  //     shows a `GtkMessageDialog` and exits.
  //   - macOS (`Info.plist` `LSMultipleInstancesProhibited`):
  //     NSApplication activates the running instance natively.
  // Only macOS focuses the existing window today; Win/Linux just
  // inform-and-exit. **Don't move the gate Dart-side** — a Dart
  // check fires only after the engine has already paid its boot cost.
  // Mobile (iOS / Android) doesn't need any of this — both OSes
  // manage single instance natively as part of the activity / scene
  // lifecycle.

  // Rust core init runs pre-`runApp` so the subsequent config load
  // + FRB-backed logging fire against a ready runtime. The
  // pre-FRB window narrows to the few ms during `RustLib.init()`
  // itself; `logCritical` writes during that window buffer through
  // `_preFrbCriticalBuffer` and drain via [AppLogger.onFrbReady]
  // below.
  //
  // `_initRustCoreOrFatal` already swaps the widget tree to the
  // native-blob FatalErrorApp on its own failure (returns `false`).
  // [AppConfigParseException] from `bootstrapRustConfigStore` is
  // rethrown out of the function so the config-corrupt FatalErrorApp
  // path below can carry the specific recovery message ("delete or
  // restore `config.json`") rather than the generic "reinstall the
  // app" copy.
  final bool rustCoreReady;
  try {
    rustCoreReady = await _initRustCoreOrFatal();
  } on AppConfigParseException catch (e, st) {
    // RustLib + appInit landed before `bootstrapRustConfigStore`
    // threw, so flip the logger gate now — `logCritical` writes
    // below (and inside FatalErrorApp's wipe handler) reach the
    // on-disk log instead of buffering past process exit.
    await AppLogger.instance.onFrbReady();
    await AppLogger.instance.logCritical(
      'config.json is unreadable — bailing to fatal screen so the '
      'corrupt file is not overwritten on the next save: $e',
      name: 'ConfigStore',
      error: e,
      stackTrace: st,
    );
    runApp(
      FatalErrorApp(
        summary: _fatalStartSummary,
        detail:
            'The settings file at ${e.path} could not be parsed. '
            'Your sessions and saved data are not affected — only '
            'app preferences live in this file. To recover, quit '
            'the app and either delete that file (preferences reset '
            'to defaults) or restore it from a backup, then relaunch.',
      ),
    );
    return;
  }
  if (!rustCoreReady) return;

  // Mirror the canonical Argon2id production profile from
  // `lfs_core::security::master_password::KdfParams::defaults` into
  // `KdfParams.productionDefaults`. Sync FRB call — safe to make
  // here because `_initRustCoreOrFatal` has already loaded the
  // native blob; the mirror has to be in place before
  // `MasterPasswordManager()` / `ExportImport.defaultKdfParams`
  // observe the `late` field on first access.
  KdfParams.bootstrapFromRust();

  // Flip the FRB-ready gate, register the log path Rust-side, open
  // the sink if a non-null threshold is already recorded, and drain
  // the pre-FRB `logCritical` ring buffer through
  // `logger_append_critical`. Runs here — after `_initRustCoreOrFatal`
  // succeeded, before `loadAppConfigFromDisk` snapshots the config
  // store — so the rest of `_mainBody` (and the post-frame
  // `_bootstrap` chain) sees a live logger from the next line.
  unawaited(AppLogger.instance.onFrbReady());

  // Snapshot the Rust `config_store` actor (already initialised
  // inside `_initRustCoreOrFatal` via `bootstrapRustConfigStore`).
  // The first frame paints the user's saved theme / locale /
  // `ui_scale` because the snapshot is injected via
  // `preloadedAppConfigProvider` before `runApp` below.
  //
  // [AppConfigParseException] from this call would mean the actor
  // returned `None` (init never ran — precondition violation, code
  // bug) or the canonical JSON did not decode (Rust + Dart encoders
  // drifted — schema bug). The corrupt-on-disk file path is already
  // caught by the `on AppConfigParseException` arm above, where the
  // throw originates inside `bootstrapRustConfigStore`. Treat any
  // reach-here exception as the same fatal-screen route so the
  // unread file is not overwritten.
  final LoadedAppConfig loaded;
  try {
    loaded = await loadAppConfigFromDisk();
  } on AppConfigParseException catch (e, st) {
    await AppLogger.instance.logCritical(
      'config_store snapshot unreadable — bailing to fatal screen: $e',
      name: 'ConfigStore',
      error: e,
      stackTrace: st,
    );
    runApp(
      FatalErrorApp(
        summary: _fatalStartSummary,
        detail:
            'The settings file at ${e.path} could not be parsed. '
            'Your sessions and saved data are not affected — only '
            'app preferences live in this file. To recover, quit '
            'the app and either delete that file (preferences reset '
            'to defaults) or restore it from a backup, then relaunch.',
      ),
    );
    return;
  }
  final config = loaded.config;
  await loggerInit; // ensure log path resolved before enabling file logging
  // Stamp the app version into the logger before the sink opens —
  // `setThreshold` below opens the sink which writes the session
  // banner including the version. `PackageInfo.fromPlatform` rides
  // on a Flutter platform channel; best-effort, a failed lookup
  // leaves the banner with a version-less form.
  try {
    final pkg = await PackageInfo.fromPlatform();
    AppLogger.instance.setAppVersion(pkg.version);
  } catch (_) {
    // Best-effort. The banner falls back to platform-only metadata.
  }
  // `--dart-define=LETSFLUTSSH_LOG_LEVEL=<level>` seeds the threshold
  // ONLY on the very first launch (no `config.json` on disk yet). After
  // that, the user's choice from Settings → Logging wins — including
  // an explicit `Off`. Without this gate the dart-define silently
  // overrides every restart on `make run`, which made the user
  // observe "Off was broken — logs kept being written" because the
  // dev-build override resurrected `info` on every cold start.
  // Release builds ship without the flag → the override is null and
  // the on-disk config is the only signal regardless of this branch.
  final effectiveLevel = loaded.loadedFromFile
      ? config.logLevel
      : (buildTimeLogLevelOverride ?? config.logLevel);
  await AppLogger.instance.setThreshold(effectiveLevel);

  // Already running inside `runZonedGuarded` from the outer `main()` —
  // launch the app directly; zone errors are routed through the outer
  // handler.
  runApp(
    ProviderScope(
      overrides: [preloadedAppConfigProvider.overrideWithValue(config)],
      child: const LetsFLUTsshApp(),
    ),
  );
}
