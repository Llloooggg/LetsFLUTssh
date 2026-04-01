import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connection/connection.dart';
import 'core/deeplink/deeplink_handler.dart';
import 'core/session/qr_codec.dart';
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'core/import/import_service.dart';
import 'features/settings/export_import.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/lfs_import_dialog.dart';
import 'widgets/cross_marquee_controller.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/app_shell.dart';
import 'widgets/hover_region.dart';
import 'widgets/toast.dart';
import 'features/file_browser/file_browser_tab.dart';
import 'features/settings/settings_screen.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_bar.dart';
import 'features/tabs/tab_controller.dart';
import 'features/tabs/tab_model.dart';
import 'features/tabs/welcome_screen.dart';
import 'features/terminal/split_node.dart';
import 'features/terminal/terminal_tab.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/update/update_service.dart';
import 'providers/update_provider.dart';
import 'providers/version_provider.dart';
import 'features/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;

/// Global navigator key for showing dialogs from non-UI contexts
/// (e.g., host key verification during SSH handshake).
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();
  AppLogger.instance.log('App starting', name: 'App');
  runApp(const ProviderScope(child: LetsFLUTsshApp()));
}

class LetsFLUTsshApp extends ConsumerStatefulWidget {
  const LetsFLUTsshApp({super.key});

  @override
  ConsumerState<LetsFLUTsshApp> createState() => _LetsFLUTsshAppState();
}

class _LetsFLUTsshAppState extends ConsumerState<LetsFLUTsshApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _setupHostKeyCallbacks();
    _lifecycleListener = AppLifecycleListener(
      onRestart: _reloadSessions,
      onResume: _reloadSessions,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(appVersionProvider.notifier).load();
      await ref.read(configProvider.notifier).load();
      ref.read(sessionProvider.notifier).load();
      if (plat.isMobilePlatform) {
        ref.read(foregroundServiceProvider).init();
      }
      if (ref.read(configProvider).checkUpdatesOnStart) {
        ref.read(updateProvider.notifier).check();
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    AppLogger.instance.log('App resumed — reloading sessions', name: 'App');
    ref.read(sessionProvider.notifier).load();
  }

  void _setupHostKeyCallbacks() {
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
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));

    // Sync AppTheme brightness before building the widget tree
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
    AppTheme.setBrightness(isDark ? Brightness.dark : Brightness.light);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'LetsFLUTssh',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(uiScale),
          ),
          child: child!,
        );
      },
      home: const MainScreen(),
    );
  }
}

/// Which content the desktop shell is currently showing.
enum ShellMode { sessions, settings }

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final _deepLinkHandler = DeepLinkHandler();
  final _crossMarquee = CrossMarqueeController();
  bool _updateDialogShown = false;
  bool _sidebarOpen = true;
  ShellMode _mode = ShellMode.sessions;
  int _settingsIndex = 0;
  final Map<String, GlobalKey<TerminalTabState>> _terminalKeys = {};

  GlobalKey<TerminalTabState> _keyForTab(String tabId) =>
      _terminalKeys.putIfAbsent(tabId, () => GlobalKey<TerminalTabState>());

  @override
  void initState() {
    super.initState();
    _setupDeepLinks();
    _listenForStartupUpdate();
  }

  @override
  void dispose() {
    _deepLinkHandler.dispose();
    _crossMarquee.dispose();
    super.dispose();
  }

  void _listenForStartupUpdate() {
    ref.listenManual(updateProvider, (prev, next) {
      if (_updateDialogShown) return;
      if (next.status == UpdateStatus.updateAvailable && next.info != null) {
        final skipped = ref.read(configProvider).skippedVersion;
        if (skipped != null && skipped == next.info!.latestVersion) return;
        _updateDialogShown = true;
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showUpdateDialog(ctx, next.info!);
        }
      }
    });
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    final hasAsset = info.assetUrl != null && plat.isDesktopPlatform;
    showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: _buildUpdateDialogContent(info),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(configProvider.notifier).update(
                (c) => c.withSkippedVersion(info.latestVersion),
              );
            },
            child: const Text('Skip This Version'),
          ),
          _buildPrimaryUpdateAction(ctx, context, info, hasAsset),
        ],
      ),
    );
  }

  Widget _buildUpdateDialogContent(UpdateInfo info) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Version ${info.latestVersion} is available (current: v${info.currentVersion}).'),
        if (info.changelog != null && info.changelog!.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Release notes:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Text(info.changelog!, style: TextStyle(fontSize: AppFonts.lg)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPrimaryUpdateAction(
    BuildContext ctx,
    BuildContext outerContext,
    UpdateInfo info,
    bool hasAsset,
  ) {
    if (hasAsset) {
      return FilledButton(
        onPressed: () {
          Navigator.pop(ctx);
          ref.read(updateProvider.notifier).download(autoInstall: true);
        },
        child: const Text('Download & Install'),
      );
    }
    return FilledButton(
      onPressed: () async {
        Navigator.pop(ctx);
        final url = Uri.parse(info.releaseUrl);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          if (outerContext.mounted) {
            Clipboard.setData(ClipboardData(text: info.releaseUrl));
            Toast.show(outerContext,
                message: 'Could not open browser — URL copied to clipboard',
                level: ToastLevel.warning);
          }
        }
      },
      child: const Text('Open in Browser'),
    );
  }

  void _setupDeepLinks() {
    _deepLinkHandler.onConnect = (config) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final manager = ref.read(connectionManagerProvider);
      final conn = manager.connectAsync(config, label: config.displayName);
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    };
    _deepLinkHandler.onLfsFileOpened = (filePath) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _showLfsImportDialog(ctx, filePath);
      }
    };
    _deepLinkHandler.onKeyFileOpened = (filePath) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Toast.show(ctx, message: 'SSH key received: ${filePath.split('/').last}', level: ToastLevel.info);
      }
    };
    _deepLinkHandler.onQrImport = (data) {
      _handleQrImport(data);
    };
    _deepLinkHandler.init();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar)
    if (plat.isMobilePlatform) {
      return const MobileShell();
    }

    final tabState = ref.watch(tabProvider);
    // Watch connection state changes so SFTP button updates when connect finishes
    ref.watch(connectionsProvider);

    return CallbackShortcuts(
      bindings: _buildKeyBindings(context, tabState),
      child: DropTarget(
          onDragDone: (details) => _handleLfsDrop(context, details),
          child: LayoutBuilder(
          builder: (context, constraints) =>
              _buildDesktopLayout(context, constraints, tabState),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(
      BuildContext context, TabState tabState) {
    return {
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
        _newSession(context, ref);
      },
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
        final active = tabState.activeTab;
        if (active != null) {
          ref.read(tabProvider.notifier).closeTab(active.id);
        }
      },
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
        _switchTab(tabState, 1);
      },
      const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () {
        _switchTab(tabState, -1);
      },
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
        setState(() => _sidebarOpen = !_sidebarOpen);
      },
      // Split shortcuts
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): () {
        final active = tabState.activeTab;
        if (active?.kind == TabKind.terminal) {
          _terminalKeys[active!.id]
              ?.currentState
              ?.splitFocused(SplitDirection.vertical);
          setState(() {});
        }
      },
      const SingleActivator(LogicalKeyboardKey.backslash, control: true, shift: true): () {
        final active = tabState.activeTab;
        if (active?.kind == TabKind.terminal) {
          _terminalKeys[active!.id]
              ?.currentState
              ?.splitFocused(SplitDirection.horizontal);
          setState(() {});
        }
      },
      // Settings
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        _toggleSettings();
      },
    };
  }

  void _switchTab(TabState tabState, int delta) {
    if (tabState.tabs.length > 1) {
      final index = (tabState.activeIndex + delta + tabState.tabs.length) %
          tabState.tabs.length;
      ref.read(tabProvider.notifier).selectTab(index);
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

  void _toggleSettings() {
    setState(() {
      _mode = _mode == ShellMode.settings
          ? ShellMode.sessions
          : ShellMode.settings;
    });
  }

  Widget _buildDesktopLayout(
      BuildContext context, BoxConstraints constraints, TabState tabState) {
    final isNarrow = constraints.maxWidth < 600;
    final activeTab = tabState.activeTab;
    final inSettings = _mode == ShellMode.settings;

    final Widget sidebar;
    final Widget body;

    if (inSettings) {
      sidebar = SettingsSidebar(
        selectedIndex: _settingsIndex,
        onSelect: (i) => setState(() => _settingsIndex = i),
      );
      body = SettingsContent(selectedIndex: _settingsIndex);
    } else {
      sidebar = SessionPanel(
        onConnect: (session) => _connectSession(context, ref, session),
        onQuickConnect: (config) => SessionConnect.connectConfig(context, ref, config),
        onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
        crossMarquee: _crossMarquee,
      );
      body = _buildSessionBody(context, tabState, activeTab);
    }

    return AppShell(
      toolbar: _buildToolbar(
        isNarrow: isNarrow,
        inSettings: inSettings,
        activeTab: activeTab,
      ),
      sidebar: sidebar,
      sidebarOpen: _sidebarOpen,
      useDrawer: isNarrow,
      body: body,
      statusBar: inSettings ? null : _StatusBar(tabState: tabState),
    );
  }

  Widget _buildSessionBody(
      BuildContext context, TabState tabState, TabEntry? activeTab) {
    final connected = activeTab?.connection.isConnected ?? false;
    final isTerminalTab = activeTab?.kind == TabKind.terminal;
    final content = activeTab != null
        ? _buildTabContent(tabState)
        : WelcomeScreen(onNewSession: () => _newSession(context, ref));
    return Column(
      children: [
        AppTabBar(onNewSession: () => _newSession(context, ref)),
        if (activeTab != null)
          _ConnectionBar(
            activeTab: activeTab,
            onOpenSftp: (isTerminalTab && connected)
                ? () => _openSftp(ref, activeTab.connection)
                : null,
            onOpenSsh: (activeTab.kind == TabKind.sftp && connected)
                ? () => _openSsh(ref, activeTab.connection)
                : null,
          ),
        Expanded(child: content),
      ],
    );
  }

  _Toolbar _buildToolbar({
    required bool isNarrow,
    required bool inSettings,
    required TabEntry? activeTab,
  }) {
    final canSplit = !inSettings && activeTab?.kind == TabKind.terminal;
    return _Toolbar(
      sidebarOpen: _sidebarOpen,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      onNewSession: () => _newSession(context, ref),
      showMenuButton: isNarrow,
      isTerminalTab: canSplit,
      onSplitVertical: canSplit
          ? () {
              _terminalKeys[activeTab!.id]
                  ?.currentState
                  ?.splitFocused(SplitDirection.vertical);
              setState(() {});
            }
          : null,
      onSplitHorizontal: canSplit
          ? () {
              _terminalKeys[activeTab!.id]
                  ?.currentState
                  ?.splitFocused(SplitDirection.horizontal);
              setState(() {});
            }
          : null,
      onSettings: _toggleSettings,
      inSettings: inSettings,
    );
  }

  Widget _buildTabContent(TabState tabState) {
    final currentIds = tabState.tabs.map((t) => t.id).toSet();
    _terminalKeys.removeWhere((id, _) => !currentIds.contains(id));
    return IndexedStack(
      index: tabState.activeIndex,
      children: tabState.tabs.map((tab) {
        switch (tab.kind) {
          case TabKind.terminal:
            return TerminalTab(
              key: _keyForTab(tab.id),
              tabId: tab.id,
              connection: tab.connection,
            );
          case TabKind.sftp:
            return FileBrowserTab(
              key: ValueKey(tab.id),
              connection: tab.connection,
              crossMarquee: _crossMarquee,
            );
        }
      }).toList(),
    );
  }

  void _openSftp(WidgetRef ref, Connection connection) {
    ref.read(tabProvider.notifier).addSftpTab(connection);
  }

  void _openSsh(WidgetRef ref, Connection connection) {
    ref.read(tabProvider.notifier).addTerminalTab(connection);
  }

  void _connectSessionSftp(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectSftp(context, ref, session);

  void _connectSession(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectTerminal(context, ref, session);

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final store = ref.read(sessionStoreProvider);
    final result = await SessionEditDialog.show(
      context,
      existingGroups: store.groups(),
    );
    if (result == null || !context.mounted) return;
    switch (result) {
      case ConnectOnlyResult(:final config):
        SessionConnect.connectConfig(context, ref, config);
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect && context.mounted) {
          SessionConnect.connectTerminal(context, ref, session);
        }
    }
  }

  Future<void> _handleQrImport(QrImportData data) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    for (final session in data.sessions) {
      await ref.read(sessionProvider.notifier).add(session);
    }
    for (final group in data.emptyGroups) {
      await ref.read(sessionProvider.notifier).addEmptyGroup(group);
    }

    if (ctx.mounted) {
      Toast.show(
        ctx,
        message: 'Imported ${data.sessions.length} session(s) via QR',
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _showLfsImportDialog(BuildContext context, String filePath) async {
    AppLogger.instance.log('LFS import started: ${filePath.split('/').last}', name: 'App');
    final result = await LfsImportDialog.show(context, filePath: filePath);
    if (result == null || !context.mounted) return;

    // Show progress while PBKDF2 + decryption runs in isolate
    showDialog(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      final importResult = await ExportImport.import_(
        filePath: filePath,
        masterPassword: result.password,
        mode: result.mode,
        importConfig: true,
        importKnownHosts: true,
      );

      await _buildImportService().applyResult(importResult);

      AppLogger.instance.log(
        'LFS import success: ${importResult.sessions.length} session(s)',
        name: 'App',
      );
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        Toast.show(
          context,
          message: 'Imported ${importResult.sessions.length} session(s)',
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('LFS import failed: $e', name: 'App', error: e);
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        Toast.show(context, message: 'Import failed: $e', level: ToastLevel.error);
      }
    }
  }

  ImportService _buildImportService() {
    return ImportService(
      addSession: (s) => ref.read(sessionProvider.notifier).add(s),
      deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
      getSessions: () => ref.read(sessionProvider),
      applyConfig: (config) => ref.read(configProvider.notifier).update((_) => config),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final VoidCallback onNewSession;
  final bool showMenuButton;
  final bool isTerminalTab;
  final VoidCallback? onSplitVertical;
  final VoidCallback? onSplitHorizontal;
  final VoidCallback onSettings;
  final bool inSettings;

  const _Toolbar({
    required this.sidebarOpen,
    required this.onToggleSidebar,
    required this.onNewSession,
    this.showMenuButton = false,
    this.isTerminalTab = false,
    this.onSplitVertical,
    this.onSplitHorizontal,
    required this.onSettings,
    this.inSettings = false,
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
            tooltip: 'Sessions',
            color: AppTheme.fgDim,
          )
        else
          AppIconButton(
            icon: Icons.view_sidebar,
            onTap: onToggleSidebar,
            tooltip: 'Sidebar (Ctrl+B)',
            active: sidebarOpen,
          ),
        const Spacer(),
        if (isTerminalTab) ...[
          AppIconButton(
            icon: Icons.vertical_split,
            onTap: onSplitVertical,
            tooltip: 'Split Vertical (Ctrl+\\)',
          ),
          AppIconButton(
            icon: Icons.horizontal_split,
            onTap: onSplitHorizontal,
            tooltip: 'Split Horizontal (Ctrl+Shift+\\)',
          ),
          _Divider(),
        ] else
          _Divider(),
        AppIconButton(
          icon: inSettings ? Icons.arrow_back : Icons.settings,
          onTap: onSettings,
          tooltip: inSettings ? 'Back' : 'Settings',
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _StatusBar extends ConsumerWidget {
  final TabState tabState;

  const _StatusBar({required this.tabState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.45);

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          Text(
            '${tabState.tabs.length} tabs',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.xs,
              color: dimColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  final TabEntry activeTab;
  final VoidCallback? onOpenSftp;
  final VoidCallback? onOpenSsh;

  const _ConnectionBar({
    required this.activeTab,
    this.onOpenSftp,
    this.onOpenSsh,
  });

  @override
  Widget build(BuildContext context) {
    final conn = activeTab.connection;
    final cfg = conn.sshConfig;
    final isTerminal = activeTab.kind == TabKind.terminal;
    final onCompanion = isTerminal ? onOpenSftp : onOpenSsh;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimColor = scheme.onSurface.withValues(alpha: 0.6);
    final faintColor = scheme.onSurface.withValues(alpha: 0.45);

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Flex(
        direction: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: conn.isConnected ? AppTheme.green : faintColor,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: conn.isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(fontFamily: 'Inter', fontSize: AppFonts.xs, color: dimColor),
                ),
                TextSpan(
                  text: ' · ',
                  style: TextStyle(fontSize: AppFonts.xs, color: faintColor),
                ),
                TextSpan(
                  text: '${cfg.user}@${cfg.host}:${cfg.effectivePort}',
                  style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: AppFonts.xs, color: dimColor),
                ),
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCompanion != null)
            _companionButton(isTerminal, onCompanion, scheme),
        ],
      ),
    );
  }

  Widget _companionButton(bool isTerminal, VoidCallback onTap, ColorScheme scheme) {
    final btnColor = isTerminal ? AppTheme.yellow : scheme.primary;
    final label = isTerminal ? 'Files' : 'Terminal';
    final icon = isTerminal ? Icons.folder_open : Icons.terminal;
    return Tooltip(
      message: label,
      child: HoverRegion(
        onTap: onTap,
        builder: (hovered) => Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: btnColor.withValues(alpha: hovered ? 0x25 / 255.0 : 0x18 / 255.0),
            border: Border.all(
              color: btnColor.withValues(alpha: hovered ? 0x60 / 255.0 : 0x40 / 255.0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: btnColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontFamily: 'Inter', fontSize: AppFonts.xs, fontWeight: FontWeight.w500, color: btnColor, height: 1.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
