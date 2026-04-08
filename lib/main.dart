import 'dart:io' show exit;

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
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'core/import/import_service.dart';
import 'features/settings/export_import.dart';
import 'widgets/app_dialog.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/lfs_import_dialog.dart';
import 'widgets/cross_marquee_controller.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/app_shell.dart';
import 'widgets/toast.dart';
import 'features/settings/settings_screen.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_model.dart';
import 'features/workspace/workspace_controller.dart';
import 'features/workspace/workspace_node.dart';
import 'features/workspace/workspace_view.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/session_provider.dart';
import 'providers/locale_provider.dart';
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

/// Single-instance lock — kept alive for the process lifetime.
/// The OS releases the file lock automatically on exit (even on crash).
@visibleForTesting
SingleInstance? singleInstanceLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.init();
  AppLogger.instance.log('App starting', name: 'App');

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
  AppLogger.instance.setEnabled(config.enableLogging);

  runApp(
    ProviderScope(
      overrides: [configStoreProvider.overrideWithValue(configStore)],
      child: const LetsFLUTsshApp(),
    ),
  );
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
      ref.read(sessionProvider.notifier).load();
      if (plat.isMobilePlatform) {
        AppLogger.instance.log('Initializing foreground service', name: 'App');
        ref.read(foregroundServiceProvider).init();
      }
      if (ref.read(configProvider).checkUpdatesOnStart) {
        AppLogger.instance.log('Checking for updates on start', name: 'App');
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
    final locale = ref.watch(localeProvider);
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));

    // Sync AppTheme brightness before building the widget tree
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    AppTheme.setBrightness(isDark ? Brightness.dark : Brightness.light);

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
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(uiScale)),
            child: child!,
          ),
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
  final _reverseCrossMarquee = CrossMarqueeController();
  bool _updateDialogShown = false;
  bool _sidebarOpen = true;
  ShellMode _mode = ShellMode.sessions;
  int _settingsIndex = 0;
  final _workspaceKey = GlobalKey<WorkspaceViewState>();
  final _sessionPanelKey = GlobalKey<SessionPanelState>();
  final _sidebarActivated = ValueNotifier<int>(0);

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
    _reverseCrossMarquee.dispose();
    _sidebarActivated.dispose();
    super.dispose();
  }

  void _listenForStartupUpdate() {
    ref.listenManual(updateProvider, (prev, next) => _handleUpdateState(next));
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
    _deepLinkHandler.init();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar)
    if (plat.isMobilePlatform) {
      return const MobileShell();
    }

    final ws = ref.watch(workspaceProvider);

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

    return reg.buildCallbackMap({
      AppShortcut.newSession: () => _newSession(context, ref),
      AppShortcut.closeTab: () {
        if (activeTab != null) {
          notifier.closeTab(ws.focusedPanelId, activeTab.id);
        }
      },
      AppShortcut.nextTab: () => _switchTab(ws, 1),
      AppShortcut.prevTab: () => _switchTab(ws, -1),
      AppShortcut.toggleSidebar: () {
        setState(() => _sidebarOpen = !_sidebarOpen);
      },
      AppShortcut.splitRight: () {
        if (activeTab != null) {
          notifier.duplicateTab(ws.focusedPanelId);
        }
      },
      AppShortcut.splitDown: () {
        if (activeTab != null) {
          notifier.copyToNewPanel(ws.focusedPanelId, Axis.vertical);
        }
      },
      AppShortcut.openSettings: () => _toggleSettings(),
      AppShortcut.closeSettings: () {
        if (_mode == ShellMode.settings) {
          _toggleSettings();
        }
      },
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

  void _toggleSettings() {
    setState(() {
      _mode = _mode == ShellMode.settings
          ? ShellMode.sessions
          : ShellMode.settings;
    });
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    BoxConstraints constraints,
    WorkspaceState ws,
  ) {
    final isNarrow = constraints.maxWidth < 600;
    final inSettings = _mode == ShellMode.settings;
    final focusedPanel = findPanel(ws.root, ws.focusedPanelId);
    final activeTab = focusedPanel?.activeTab;

    final Widget sidebar;
    final Widget body;

    final sessionBody = WorkspaceView(
      key: _workspaceKey,
      crossMarquee: _crossMarquee,
      reverseCrossMarquee: _reverseCrossMarquee,
      sidebarActivated: _sidebarActivated,
      onActivated: () => _sessionPanelKey.currentState?.clearDesktopSelection(),
    );
    if (inSettings) {
      sidebar = SettingsSidebar(
        selectedIndex: _settingsIndex,
        onSelect: (i) => setState(() => _settingsIndex = i),
      );
      // Keep terminal tabs alive (Offstage) so SSH shells survive settings.
      body = Stack(
        children: [
          Offstage(child: sessionBody),
          SettingsContent(selectedIndex: _settingsIndex),
        ],
      );
    } else {
      sidebar = SessionPanel(
        key: _sessionPanelKey,
        onConnect: (session) => _connectSession(context, ref, session),
        onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
        crossMarquee: _crossMarquee,
        reverseCrossMarquee: _reverseCrossMarquee,
        onActivated: () => _sidebarActivated.value++,
      );
      body = sessionBody;
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
      statusBar: null,
    );
  }

  _Toolbar _buildToolbar({
    required bool isNarrow,
    required bool inSettings,
    required TabEntry? activeTab,
  }) {
    final tab = activeTab;
    final hasTab = !inSettings && tab != null;
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
      onCopyDown: hasTab
          ? () {
              final ws = ref.read(workspaceProvider);
              ref
                  .read(workspaceProvider.notifier)
                  .copyToNewPanel(ws.focusedPanelId, Axis.vertical);
            }
          : null,
      onSettings: _toggleSettings,
      inSettings: inSettings,
    );
  }

  void _connectSessionSftp(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectSftp(context, ref, session);

  void _connectSession(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectTerminal(context, ref, session);

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final result = await SessionEditDialog.show(context);
    if (result == null || !context.mounted) return;
    switch (result) {
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect && context.mounted) {
          SessionConnect.connectTerminal(context, ref, session);
        }
    }
  }

  Future<void> _handleQrImport(QrImportData data) async {
    // Data operations don't need UI context — always execute, even when
    // the app is still resuming from background.
    for (final session in data.sessions) {
      await ref.read(sessionProvider.notifier).add(session);
    }
    for (final folder in data.emptyFolders) {
      await ref.read(sessionProvider.notifier).addEmptyFolder(folder);
    }
    AppLogger.instance.log(
      'QR import complete: ${data.sessions.length} session(s), '
      '${data.emptyFolders.length} folder(s)',
      name: 'App',
    );

    // Toast is best-effort — show when the navigator context is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Toast.show(
          ctx,
          message: S.of(ctx).importedSessionsViaQr(data.sessions.length),
          level: ToastLevel.success,
        );
      }
    });
  }

  Future<void> _showLfsImportDialog(
    BuildContext context,
    String filePath,
  ) async {
    AppLogger.instance.log(
      'LFS import started: ${filePath.split('/').last}',
      name: 'App',
    );
    final result = await LfsImportDialog.show(context, filePath: filePath);
    if (result == null || !context.mounted) return;

    // Show progress while PBKDF2 + decryption runs in isolate
    AppProgressDialog.show(context);

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
          message: S.of(context).importedSessions(importResult.sessions.length),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('LFS import failed: $e', name: 'App', error: e);
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        Toast.show(
          context,
          message: S.of(context).importFailed(e.toString()),
          level: ToastLevel.error,
        );
      }
    }
  }

  ImportService _buildImportService() {
    final store = ref.read(sessionStoreProvider);
    return ImportService(
      addSession: (s) => ref.read(sessionProvider.notifier).add(s),
      deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
      getSessions: () => ref.read(sessionProvider),
      applyConfig: (config) =>
          ref.read(configProvider.notifier).update((_) => config),
      getEmptyFolders: () => store.emptyFolders,
      loadCredentials: (ids) => store.loadCredentials(ids),
      restoreSnapshot: (sessions, folders, creds) =>
          store.restoreSnapshot(sessions, folders, creds),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final bool showMenuButton;
  final bool isTerminalTab;
  final VoidCallback? onDuplicateTab;
  final VoidCallback? onCopyDown;
  final VoidCallback onSettings;
  final bool inSettings;

  const _Toolbar({
    required this.sidebarOpen,
    required this.onToggleSidebar,
    this.showMenuButton = false,
    this.isTerminalTab = false,
    this.onDuplicateTab,
    this.onCopyDown,
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
        const Spacer(),
        if (isTerminalTab) ...[
          AppIconButton(
            icon: Icons.content_copy,
            onTap: onDuplicateTab,
            tooltip: S.of(context).duplicateTabShortcut,
          ),
          AppIconButton(
            icon: Icons.horizontal_split,
            onTap: onCopyDown,
            tooltip: S.of(context).copyDownShortcut,
          ),
          _Divider(),
        ] else
          _Divider(),
        AppIconButton(
          icon: inSettings ? Icons.arrow_back : Icons.settings,
          onTap: onSettings,
          tooltip: inSettings ? S.of(context).back : S.of(context).settings,
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
