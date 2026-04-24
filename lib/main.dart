import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'app/already_running_app.dart';
import 'app/app_toolbar.dart';
import 'app/deep_link_wiring.dart';
import 'app/global_error_dialog.dart';
import 'app/import_flow.dart';
import 'app/navigator_key.dart';
import 'app/security_init_controller.dart';
import 'app/update_dialog_flow.dart';
import 'core/config/config_store.dart';
import 'core/shortcut_registry.dart';
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
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;
import 'utils/sanitize.dart';
import 'widgets/app_shell.dart';
import 'widgets/auto_lock_detector.dart';
import 'widgets/first_launch_security_toast.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/lock_screen.dart';
import 'widgets/passphrase_dialog.dart';
import 'widgets/toast.dart';

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
  // The pre-loaded store is injected via override so ConfigNotifier.build()
  // reads the real config instead of defaults.
  final configStore = ConfigStore();
  final config = await configStore.load();
  await loggerInit; // ensure log path resolved before enabling file logging
  // `--dart-define=LETSFLUTSSH_LOG_LEVEL=<level>` overrides the on-
  // disk config on dev / beta-tester builds so fresh installs start
  // with logs enabled without a Settings-tweak round-trip. Release
  // builds ship without the flag → we honour whatever the user
  // stored in config.json (default: null / off).
  await AppLogger.instance.setThreshold(
    buildTimeLogLevelOverride ?? config.logLevel,
  );

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
          showGlobalErrorDialog(ctx, error);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    },
  );
}

class LetsFLUTsshApp extends ConsumerStatefulWidget {
  const LetsFLUTsshApp({super.key});

  @override
  ConsumerState<LetsFLUTsshApp> createState() => _LetsFLUTsshAppState();
}

class _LetsFLUTsshAppState extends ConsumerState<LetsFLUTsshApp> {
  late final AppLifecycleListener _lifecycleListener;
  late final SecurityInitController _securityController;

  /// Last value of `securityReinitProvider` we acted on — lets
  /// `listenManual` fire `reinitFromReset` only when the counter
  /// goes up, not on the provider's initial read.
  int _lastReinitTick = 0;

  @override
  void initState() {
    super.initState();
    _securityController = SecurityInitController(
      ref: ref,
      isMounted: () => mounted,
    );
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
        await _securityController.reinitFromReset();
      });
    });
  }

  /// Re-open the drift / MC handle after a lock → unlock
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
          await _securityController.reopenAfterUnlock();
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
    // Kick the tier-availability probe off in parallel with migrations
    // + unlock. `securityCapabilitiesProvider` caches its result to
    // `config.json`, so warm starts read the cached snapshot on the
    // first microtask (no work) and fall through. On first launch the
    // probe is a real round-trip against Keychain / LAContext /
    // BiometricManager / TPM2. Starting the probe here overlaps it
    // with the migration runner and `_initSecurity` inside the
    // controller so by the time `_firstLaunchSetup` awaits the same
    // future the work is either done or well in flight.
    _warmProbeCaches();
    // Migration runner + security init + corruption probe + initial
    // session load all now live inside [SecurityInitController.bootstrap].
    await _securityController.bootstrap();
    _maybeShowCredentialsResetToast();
    if (plat.isMobilePlatform) {
      AppLogger.instance.log('Initializing foreground service', name: 'App');
      ref.read(foregroundServiceProvider).init();
    }
    if (ref.read(configProvider).checkUpdatesOnStart) {
      AppLogger.instance.log('Checking for updates on start', name: 'App');
      ref.read(updateProvider.notifier).check();
    }
  }

  void _maybeShowCredentialsResetToast() {
    if (!_securityController.takeAndClearCredentialsResetFlag()) return;
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
  ///
  /// Invoked twice in the bootstrap graph: once at the *start* of
  /// [_bootstrap] so the probe runs in parallel with migrations + DB
  /// unlock (the critical first-launch path where `_firstLaunchSetup`
  /// blocks on `probeCapabilities`), and implicitly a second time via
  /// the Settings "Re-check" flow which invalidates the providers.
  /// The double-fire is safe because the provider de-duplicates
  /// in-flight futures — the second `ref.read(...future)` returns the
  /// same `Future` as the first until it resolves.
  void _warmProbeCaches() {
    unawaited(ref.read(securityCapabilitiesProvider.future));
    unawaited(ref.read(hardwareProbeDetailProvider.future));
    unawaited(ref.read(keyringProbeDetailProvider.future));
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _securityController.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    // Lifecycle `onResume` fires before the controller's bootstrap
    // finishes on cold-start + early re-foreground flows. Gating on
    // the controller's explicit ready flag avoids issuing drift
    // queries against a DB whose cipher key is either not yet set
    // or turned out to be wrong — the DB-corruption dialog is the
    // single entry point that authorises unlocked reads.
    if (!_securityController.isReady) return;
    AppLogger.instance.log('App resumed — reloading sessions', name: 'App');
    ref.read(sessionProvider.notifier).load();
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
    wireDeepLinks(_deepLinkHandler, ref);
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
    ref.listenManual<FirstLaunchBannerData?>(
      firstLaunchBannerProvider,
      _onFirstLaunchBannerChanged,
      fireImmediately: true,
    );
  }

  void _onFirstLaunchBannerChanged(
    FirstLaunchBannerData? prev,
    FirstLaunchBannerData? next,
  ) {
    if (next == null || _firstLaunchBannerShown) return;
    _firstLaunchBannerShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _showFirstLaunchBannerToast(ctx, next);
    });
  }

  // Top-right toast — the auto-selected tier is a safe default the app
  // already landed on, so a blocking modal would be out of scale for
  // what the user has to do (nothing). The toast surfaces the same copy
  // + the upgrade path when T2 is within reach, and auto-dismisses on a
  // timer. The reduced-wizard path (both keychain + hardware out of
  // reach) still routes through the full SecuritySetupDialog modal —
  // that is a real decision the user has to make.
  void _showFirstLaunchBannerToast(
    BuildContext ctx,
    FirstLaunchBannerData data,
  ) {
    FirstLaunchSecurityToast.show(
      ctx,
      data: data,
      onOpenSettings: _openSettingsFromBanner,
      onDismiss: _clearFirstLaunchBanner,
    );
  }

  void _openSettingsFromBanner() {
    final inner = navigatorKey.currentContext;
    if (inner == null || !inner.mounted) return;
    if (plat.isMobilePlatform) {
      SettingsScreen.show(inner);
    } else {
      SettingsDialog.show(inner);
    }
  }

  void _clearFirstLaunchBanner() {
    if (mounted) {
      ref.read(firstLaunchBannerProvider.notifier).set(null);
    }
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
      showUpdateDialog(context: ctx, ref: ref, info: next.info!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar).
    //
    // An earlier iteration wrapped the entire MobileShell in
    // `AppSelectionArea` so every plain Text across the mobile tree
    // supported drag-select + long-press copy. That collided with the
    // xterm widget on the Terminal page: Android's long-press on the
    // SelectionArea surfaced the system Paste / Select-All toolbar
    // over the terminal even though the xterm subtree has no
    // selectable text — `SelectionContainer.disabled` inside
    // MobileTerminalView was not enough because the SelectionArea's
    // own gesture recognizers (TapAndDragGestureRecognizer,
    // LongPressGestureRecognizer) still win the arena across the
    // whole subtree. Terminal taps must not trigger a system
    // selection toolbar — the dedicated Copy button is the
    // sanctioned copy surface on mobile. Text selection on the
    // non-terminal mobile screens is wired per-screen via local
    // `AppSelectionArea` wrappers where the feature earns its keep.
    if (plat.isMobilePlatform) {
      return const MobileShell();
    }

    final ws = ref.watch(workspaceProvider);

    // No top-level `SelectionArea` on desktop. Text selection is
    // opt-in: specific informational surfaces (threat list rows in
    // security tier cards, release-notes bodies, help prose) wrap
    // their own `AppSelectionArea` locally. The previous iteration
    // shipped one giant `SelectionArea` over the whole shell with
    // `HoverRegion` auto-wrapping clickables in
    // `SelectionContainer.disabled` to suppress the I-beam cursor
    // and Ctrl+C hijack on buttons — but that collapsed the moment
    // a `ThresholdDraggable` sat inside a `HoverRegion`, because the
    // SelectionArea's `TapAndDragGestureRecognizer` claims pan
    // ahead of Draggable in the arena and the opt-out wrap sits
    // above the drag subtree instead of protecting it. Scoping
    // selection to just the prose that needs it sidesteps every
    // gesture-arena race, keeps drag native, and removes the I-beam
    // from clickables for free (nothing claims selection there).
    return CallbackShortcuts(
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
      showLfsImportDialog(context, ref, lfsFiles.first.path);
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

  AppToolbar _buildToolbar({
    required bool isNarrow,
    required TabEntry? activeTab,
  }) {
    final tab = activeTab;
    final hasTab = tab != null;
    return AppToolbar(
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
}
