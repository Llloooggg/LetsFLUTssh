part of 'main.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _updateDialogShown = false;
  bool _sidebarOpen = true;
  final _workspaceKey = GlobalKey<WorkspaceViewState>();
  final _sessionPanelKey = GlobalKey<SessionPanelState>();
  final _sidebarActivated = ValueNotifier<int>(0);

  bool _firstLaunchBannerShown = false;

  @override
  void initState() {
    super.initState();
    // Pure-Dart wiring only. Every FRB-touching listener (HostKey,
    // Keychain probe, HardwareVault probe / unlock / seal, tier
    // state observer, foreground-service bridge) wires up from
    // `_LetsFLUTsshAppState._bootstrap` — see the comment block on
    // `wireFrbDependentBootstrapListeners`. Centralising the
    // wiring keeps every `AppBus.subscribe` attachment in one
    // auditable place rather than scattering them across widget
    // `initState`s where each new tile silently adds another
    // subscription, and it lets the bootstrap stopwatch mark a
    // single `bus_subscribers_attached` phase that captures the
    // whole set.
    //
    // Deep-link callbacks register here (pure Dart); the handler's
    // `init()` — which dispatches the cold-start initial link
    // through Rust — fires from `_bootstrap` via
    // `activateDeepLinks`, so a `letsflutssh://` cold launch or a
    // double-clicked `.lfs` file lands inside the bootstrap chain
    // alongside the security init + DB unlock instead of running
    // ahead of them.
    wireDeepLinks(ref.read(deepLinkHandlerProvider), ref);
    _listenForStartupUpdate();
    _listenForFirstLaunchBanner();
  }

  @override
  void dispose() {
    // Deep-link handler lives in `deepLinkHandlerProvider` for the
    // process lifetime — `_MainScreenState` registers callbacks but
    // does not own the handle. The provider scope outlives this
    // state, and disposing here would break a navigator-rebuild
    // scenario (test harness re-mounts MainScreen) by leaving a
    // dead listener on the next mount.
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
    // **Don't wrap the entire MobileShell in `AppSelectionArea`** —
    // the SelectionArea's own gesture recognizers
    // (TapAndDragGestureRecognizer, LongPressGestureRecognizer)
    // win the arena across the xterm subtree on the Terminal
    // page, surfacing Android's system Paste / Select-All toolbar
    // over the terminal even though xterm has no selectable text
    // there. `SelectionContainer.disabled` inside MobileTerminalView
    // does not save it — the recognizers fire above the disabled
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
    // their own `AppSelectionArea` locally. **Don't** wrap the
    // whole shell in one `SelectionArea` — its
    // `TapAndDragGestureRecognizer` claims pan ahead of
    // `MultiDragGestureRecognizer` in the arena, so any
    // `ThresholdDraggable` inside a `HoverRegion` (session
    // sidebar, tab bar, file pane) becomes intermittent.
    // `HoverRegion`'s `SelectionContainer.disabled` wrap doesn't
    // save the drag — it sits above the drag subtree, not under
    // it. Scoping selection to just the prose that needs it
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
    // the rusqlite handle, so reaching Settings or "new session"
    // while locked would throw "db not initialized" on the first
    // FRB DAO read.
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
    Session session,
  ) => SessionConnect.connectSftp(context, ref, session);

  Future<void> _connectSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) => SessionConnect.connectTerminal(context, ref, session);

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
