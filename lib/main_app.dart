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

    // Rust core was loaded synchronously inside `_mainBody` via
    // `_initRustCoreOrFatal` so every pre-`runApp` FRB call (config
    // sanitize, capability decode, store init) had FRB ready. By the
    // time this post-frame callback runs, FRB is up and AppState is
    // initialised — `_bootstrap` can dive straight into Riverpod work.

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
    // The splash sits in the same Stack as MaterialApp's `home` but
    // *above* the Navigator that owns Material's DefaultTextStyle —
    // so any plain `Text` here renders with the framework's debug
    // double-yellow underline ("missing default text style"). Wrap
    // explicitly so the Text inherits a proper style.
    return ColoredBox(
      color: AppTheme.bg0,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: false),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: AppFonts.lg,
            fontWeight: FontWeight.w600,
            color: AppTheme.fg,
            decoration: TextDecoration.none,
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(height: 16),
                Text('LetsFLUTssh'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
