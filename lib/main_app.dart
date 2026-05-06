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

    // Rust core load — DEFERRED past the first frame on purpose.
    // `_mainBody` painted the splash overlay immediately (via
    // `runApp(LetsFLUTsshApp)`), so the user already sees the
    // spinner; the ~3 s Defender scan of the bundled `.so/.dll`
    // on Windows IoT happens here, behind the splash, instead of
    // in front of a blank desktop. Pre-`runApp` callers that need
    // FRB (`AppConfig.fromJson` → Rust sanitize, `SecurityCapabilities
    // .fromJson`) detect `!RustLib.instance.initialized` and use a
    // pure-Dart fallback path; their result is canonically the same
    // for healthy `config.json` content because the per-sub-config
    // `fromJson` factories run their own `.sanitized()` clamps.
    if (!await _initRustCoreOrFatal()) return;
    mark('rust_core');

    // Drain log-file chmod requests queued during the pre-FRB
    // window. `AppLogger._openSink` (and the `logCritical` write
    // path) call `pathHardenFilePerms` on every fresh log file;
    // before `_initRustCoreOrFatal` ran, those calls queued via
    // `_deferredHardenPaths` instead of throwing `StateError`. Now
    // that Rust is up, replay them so the file's perms tighten to
    // 0600 instead of staying at the umask-wide default.
    unawaited(AppLogger.instance.hardenPendingLogPerms());
    mark('log_perms_drained');

    // Activate the deep-link handler now that Rust is loaded —
    // `_MainScreenState.initState` registered the callbacks
    // pre-FRB but withheld `init()` so a cold-launch via
    // `letsflutssh://` URL or a double-clicked `.lfs` file does
    // not race `deeplinkDispatch` against the native-lib load.
    unawaited(activateDeepLinks(ref.read(deepLinkHandlerProvider)));
    mark('deep_links_activated');

    // Promote every `_SharedTopic` whose `Notifier.build()` ran
    // pre-FRB-init (Riverpod providers like `ConnectionsNotifier`
    // or `connectionActiveCountProvider` that widgets watch on the
    // first runApp frame) to a live FRB subscription. Without this
    // promotion, `AppBus.subscribe` calls during widget build
    // anchor a dead `_SharedTopic` whose `_frbSub` never attaches
    // — `Connection: Connected` and `[Progress]` events never
    // reach the Dart subscribers, the terminal pane sees no
    // shell-open trigger, and the user gets an empty tab. The
    // per-call retry in `AppBus.subscribe` would eventually fix
    // this on a follow-up subscription, but Riverpod notifiers
    // don't re-enter `subscribe` after their build runs, so we
    // promote them all at the FRB-ready boundary explicitly.
    AppBus.instance.retryFrbSubscriptions();
    mark('bus_subscriptions_promoted');

    // Drain any auto-lock lifecycle dispatches that the
    // `AutoLockDetector` queued during the first runApp pass —
    // pre-FRB lifecycle transitions on Win IoT (the ~3 s native
    // blob load window) used to silently disappear into a
    // try/catch swallow, so the Rust state machine never saw
    // the early `app paused` / `inactive` events. The detector
    // now queues into a module-static buffer; this drains it
    // through the live bus.
    unawaited(AutoLockDetector.replayPendingDispatches());
    mark('autolock_dispatches_drained');

    // FRB-dependent listeners owned directly by the boot chain
    // (prompt subscribers, tier-state observer, foreground bridge)
    // wire here. Centralised here so the FRB-readiness invariant
    // for boot-chain code is trivially auditable: only post-
    // `_initRustCoreOrFatal` code reaches `AppBus.subscribe`
    // through this path. Riverpod-driven subscribers go through
    // the retry promotion above instead.
    _wireFrbDependentBootstrapListeners();
    mark('bus_subscribers_attached');

    // Opt the app-support directory out of iCloud/iTunes backup (iOS) and
    // Time Machine (macOS) so secrets don't land in untrusted backups.
    // Routes through `lfs_os_security::backup_exclusion` (FRB sync) so
    // it has to land *after* `_initRustCoreOrFatal`. Idempotent, cheap,
    // refreshes the flag if a system action stripped the xattr.
    unawaited(BackupExclusion().applyOnStartup());

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

  /// Attach every `AppBus.subscribe`-using listener that runs for
  /// the process lifetime. Called from [_bootstrap] right after
  /// [_initRustCoreOrFatal] succeeds — every callsite below routes
  /// through `AppBus.subscribe(topic)` whose underlying FRB stream
  /// requires `RustLib.init` to have completed. Centralising the
  /// wiring here (rather than scattering `.start()` calls across
  /// `initState`s and provider constructors) makes the FRB-readiness
  /// invariant trivially auditable: only post-`_initRustCoreOrFatal`
  /// code can reach `AppBus.subscribe`.
  void _wireFrbDependentBootstrapListeners() {
    HostKeyPromptListener.start();
    // Keychain reachability probe subscriber — drives the
    // capabilities orchestrator's keychain-ping round-trip.
    KeychainProbePromptListener.start();
    // Hardware-vault probe subscriber — drives the orchestrator's
    // MethodChannel round-trip on Apple / Android / Windows. Linux
    // never fires this prompt.
    HardwareVaultProbePromptListener.start();
    // Hardware-vault unlock subscriber — drives the L3 tier
    // orchestrator's `HardwareTierVault.read(pin)` call which fans
    // out to tpm2-tools (Linux) or the platform method channel
    // (Apple / Android / Windows).
    HardwareVaultUnlockPromptListener.start();
    // Hardware-vault seal subscriber — drives the L3 first-launch
    // orchestrator's `HardwareTierVault.store(dbKey, pin)` call (the
    // wrap-and-persist counterpart of the unlock prompt).
    HardwareVaultSealPromptListener.start();
    // Diagnostic observer for tier_machine transitions — logs every
    // Locked / Unlocking / Unlocked / Wiping flip a support trace
    // can read back. Non-functional until per-tier handlers wire
    // production unlock through the actor.
    TierStateObserver.start();
    // Activate the bus → foreground-service bridge. The provider's
    // body wires `ref.listen` against the active-count stream; the
    // act of reading it once installs the listener for the process
    // lifetime.
    ref.read(foregroundActiveCountListenerProvider);
    // Same pattern: install the `securityCapabilitiesProvider` →
    // `config.security_probe_cache` listener for the process
    // lifetime. The capabilities provider itself is now pure (no
    // side-effects in its async build); this listener is the
    // single writer for the persisted cache slot.
    ref.read(securityProbeCachePersisterProvider);
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
      // The observer feeds `activeOverlayModalCount` so the startup
      // splash can hide itself while a `PopupRoute` (showDialog /
      // showModalBottomSheet / showMenu) sits on top of the navigator.
      // Without this, bootstrap-time recovery dialogs (showTierReset,
      // showDbCorrupt) paint underneath the splash overlay and the
      // user can't click them — the spinner spins forever. See
      // `app/navigator_key.dart` for the rationale + counter contract.
      navigatorObservers: [overlayModalRouteObserver],
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
              //
              // Hides itself while a `PopupRoute` (dialog / bottom
              // sheet / menu) sits on top of the navigator —
              // bootstrap-time recovery dialogs (showTierReset,
              // showDbCorrupt) live inside the navigator and would
              // otherwise paint *under* the opaque splash overlay,
              // blocking the user from acting on them. Tracked via
              // the singleton `overlayModalRouteObserver` attached to
              // `MaterialApp.navigatorObservers` above.
              if (debugShowStartupSplash)
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _securityController.readiness,
                    builder: (context, ready, _) {
                      if (ready) return const SizedBox.shrink();
                      return ValueListenableBuilder<int>(
                        valueListenable: activeOverlayModalCount,
                        builder: (context, modalCount, _) {
                          if (modalCount > 0) return const SizedBox.shrink();
                          return const _StartupSplash();
                        },
                      );
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
