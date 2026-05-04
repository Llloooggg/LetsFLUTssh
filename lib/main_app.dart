part of 'main.dart';

/// Tests bypass the bootstrap-pending splash overlay because they
/// never run the real `bootstrap()` (no FRB migrations, no real
/// keychain unlock) so [SecurityInitController.readiness] would
/// stay `false` forever and pin the splash on top of the widget
/// tree the test is trying to inspect / interact with. Flip to
/// `false` at top of every test that mounts [LetsFLUTsshApp] —
/// the existing `test/main_test.dart` setUp already does so.
@visibleForTesting
bool debugShowStartupSplash = true;

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
    // Interactive passphrase prompt + TOFU host-key verification
    // land through the Rust-side prompt-protocol arcs (russh's
    // `check_server_key` already routes through the bus for
    // `KnownHostPromptRequest`; the passphrase prompt follows the
    // same shape). Until the russh layer fans out a
    // `PassphrasePromptRequest` event there's nothing to wire
    // here — the Rust transport surfaces `PassphraseIncorrect` /
    // `PassphraseRequired` as connect errors which the workspace
    // surfaces as a re-edit hint on the session row.
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

  /// Re-open the rusqlite handle after a lock → unlock transition.
  /// `AutoLockDetector._triggerLock` now always closes the DB (so
  /// SQLCipher's C-layer page-cipher state is zeroed alongside the
  /// Dart-side `SecretBuffer`), so every unlock needs a fresh
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
    final sw = Stopwatch()..start();
    void mark(String phase) {
      AppLogger.instance.log(
        'bootstrap phase=$phase elapsed=${sw.elapsedMilliseconds}ms',
        name: 'Boot',
      );
    }

    // Rust security/transport core load DEFERRED past the first
    // frame on purpose. Win32 hides its window until the engine
    // paints the first frame (`flutter_window.cpp:42`), so doing
    // RustLib.init / appInit / ProcessHardening synchronously
    // before runApp leaves the user staring at a blank desktop
    // for the entire native-lib load duration (Defender real-time
    // scan on Windows IoT pushes that to ~3-4s). With the load
    // deferred, runApp paints the splash overlay immediately —
    // user sees the spinner from the second the window appears,
    // and every dependent step (FRB calls, capability probes,
    // unlock cascade) waits on this single completion.
    if (!await _initRustCore()) return;
    mark('rust_core');

    await ref.read(appVersionProvider.notifier).load();
    mark('app_version_load');
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
    mark('warm_probes_kicked');
    // Migration runner + security init + corruption probe + initial
    // session load all now live inside [SecurityInitController.bootstrap].
    await _securityController.bootstrap();
    mark('security_bootstrap');
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

  /// Load the bundled native blob + initialise the Rust AppState
  /// singleton + apply process hardening. Returns true on success
  /// so the caller's `_bootstrap` can continue, false when the
  /// load failed and the entire widget tree was replaced with
  /// [FatalErrorApp] (no further bootstrap work is meaningful in
  /// that branch — every downstream FRB call would throw).
  ///
  /// Failure-mode escape valve: every SSH / SFTP / keypair / crypto
  /// call routes through here, and a missing core makes downstream
  /// FRB calls throw. The migration runner catches those throws
  /// and routes the user into `DbCorruptDialog` whose "Reset and
  /// start fresh" button calls `WipeAllService.wipeAll()` —
  /// destroying their data over what is usually a transient
  /// packaging issue. We bail to a dedicated fatal screen instead
  /// so the wipe path is unreachable.
  Future<bool> _initRustCore() async {
    try {
      // `RustLib.init()` throws "Should not initialize twice" on a
      // re-entry — that happens under flutter_test where
      // `requireFrbLoaded()` already ran in `setUpAll`. Tolerate
      // that specific shape and continue; every other StateError
      // / load-time failure still routes through the catch below
      // and lands on FatalErrorApp.
      try {
        await RustLib.init();
      } on StateError catch (e) {
        if (!e.message.contains('Should not initialize')) rethrow;
        AppLogger.instance.log(
          'RustLib already initialised — skipping re-init',
          name: 'RustCore',
        );
      }
      // Initialise the AppState singleton in lfs_core. Subsequent
      // commands (secrets_*, sessions/connections/forwards) attach
      // to it. Idempotent.
      await rust_app.appInit();
      // Wire the Rust→Dart log pipe — every `lfs_core::app_log`
      // call gets folded into the same on-disk `letsflutssh.log`
      // the Dart-side AppLogger writes through. Must be after
      // `app_init` because `bus_subscribe` reaches into
      // `lfs_core::app::instance()`.
      AppLogger.instance.attachCoreLogPipe();
      AppLogger.instance.log(
        'Rust core loaded: ${rust_core.ping()}',
        name: 'RustCore',
      );
      // Disable core dumps + ptrace attach as early as possible —
      // before any secrets touch RAM. The previous `main()` ordering
      // ran this before bootstrap; deferring the whole core-load
      // here keeps the same "harden before secrets" invariant since
      // the unlock cascade fires inside `_securityController.
      // bootstrap()` further down. Best-effort, swallowed on
      // failure.
      ProcessHardening.applyOnStartup();
      return true;
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
      return false;
    }
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
              // Startup splash — covers the empty-workspace skeleton
              // while bootstrap (FRB load + migrations + tier unlock +
              // DB cipher probe) is still in flight. Flips off via the
              // controller's [ValueNotifier] the moment
              // `_markSecurityReady()` fires. Sits ABOVE the lock
              // overlay because the auto-lock idle timer can't fire
              // before bootstrap finishes anyway, and visually it's
              // the same "you can't interact yet" state.
              if (debugShowStartupSplash)
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _securityController.readiness,
                    builder: (context, ready, _) {
                      if (ready) return const SizedBox.shrink();
                      return const _StartupSplash();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cold-start overlay shown until the security controller marks
/// itself ready. Renders an opaque themed background + centred
/// spinner + the app name so the user sees a deliberate "loading"
/// state rather than the empty-workspace skeleton flash that used
/// to greet them during the few hundred ms (warm start) to several
/// seconds (Windows IoT cold start, post-wipe re-init) the
/// bootstrap sequence takes.
///
/// Lives in this file so it shares the part-of-main library scope
/// with the rest of the app shell — keeps it next to the
/// [AutoLockDetector] / [LockScreen] stack it overlays.
class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    // The shell's `disableAnimations: true` MediaQuery would normally
    // freeze CircularProgressIndicator's ticker — that flag is meant
    // to hard-off route / implicit animations the user can't opt out
    // of, NOT a load indicator that's the only signal the app isn't
    // hung. Re-enable the ticker here via `MediaQuery` override so
    // the spinner actually rotates while bootstrap (Windows IoT
    // sees ~5 s of `dbInit` + `hardenFilePerms`) is in flight.
    // Tests skip the splash entirely via [debugShowStartupSplash],
    // so re-enabling animations here doesn't pin `pumpAndSettle`.
    return ColoredBox(
      color: AppTheme.bg0,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: false),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                'LetsFLUTssh',
                style: TextStyle(
                  fontSize: AppFonts.lg,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
