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
import 'widgets/toast.dart';
import 'features/file_browser/file_browser_tab.dart';
import 'features/settings/settings_screen.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_bar.dart';
import 'features/tabs/tab_controller.dart';
import 'features/tabs/tab_model.dart';
import 'features/tabs/welcome_screen.dart';
import 'features/terminal/terminal_tab.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/transfer_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/update/update_service.dart';
import 'providers/update_provider.dart';
import 'providers/version_provider.dart';
import 'features/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;
import 'widgets/split_view.dart';

/// Global navigator key for showing dialogs from non-UI contexts
/// (e.g., host key verification during SSH handshake).
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFonts.loadFonts();
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

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'LetsFLUTssh',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const MainScreen(),
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
  final _crossMarquee = CrossMarqueeController();
  bool _updateDialogShown = false;

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
              child: Text(info.changelog!, style: const TextStyle(fontSize: 13)),
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

  Widget _buildDesktopLayout(
      BuildContext context, BoxConstraints constraints, TabState tabState) {
    final isNarrow = constraints.maxWidth < 600;
    final sessionPanel = SessionPanel(
      onConnect: (session) => _connectSession(context, ref, session),
      onQuickConnect: (config) => SessionConnect.connectConfig(context, ref, config),
      onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
      crossMarquee: _crossMarquee,
    );

    final content = tabState.activeTab != null
        ? _buildTabContent(tabState)
        : WelcomeScreen(
            onNewSession: () => _newSession(context, ref),
          );

    final rightSide = _buildRightSide(tabState, content, isNarrow);

    if (isNarrow) {
      return Scaffold(
        drawer: Drawer(width: 280, child: SafeArea(child: sessionPanel)),
        body: rightSide,
      );
    }

    return Scaffold(
      body: SplitView(
        left: sessionPanel,
        right: rightSide,
      ),
    );
  }

  Widget _buildRightSide(TabState tabState, Widget content, bool isNarrow) {
    final activeTab = tabState.activeTab;
    final connected = activeTab?.connection.isConnected ?? false;
    return Column(
      children: [
        _Toolbar(
          onNewSession: () => _newSession(context, ref),
          onOpenSftp: (activeTab?.kind == TabKind.terminal && connected)
              ? () => _openSftp(ref, activeTab!.connection)
              : null,
          onOpenSsh: (activeTab?.kind == TabKind.sftp && connected)
              ? () => _openSsh(ref, activeTab!.connection)
              : null,
          showMenuButton: isNarrow,
        ),
        const AppTabBar(),
        if (tabState.tabs.isNotEmpty) const Divider(height: 1),
        Expanded(child: content),
        _StatusBar(tabState: tabState),
      ],
    );
  }

  Widget _buildTabContent(TabState tabState) {
    return IndexedStack(
      index: tabState.activeIndex,
      children: tabState.tabs.map((tab) {
        switch (tab.kind) {
          case TabKind.terminal:
            return TerminalTab(
              key: ValueKey(tab.id),
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
  final VoidCallback onNewSession;
  final VoidCallback? onOpenSftp;
  final VoidCallback? onOpenSsh;
  final bool showMenuButton;

  const _Toolbar({
    required this.onNewSession,
    this.onOpenSftp,
    this.onOpenSsh,
    this.showMenuButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (showMenuButton)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu, size: 18),
              tooltip: 'Sessions',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onNewSession,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'New Session (Ctrl+N)',
            visualDensity: VisualDensity.compact,
          ),
          if (onOpenSftp != null)
            IconButton(
              onPressed: onOpenSftp,
              icon: const Icon(Icons.folder_open, size: 18),
              tooltip: 'Open SFTP Browser',
              visualDensity: VisualDensity.compact,
            ),
          if (onOpenSsh != null)
            IconButton(
              onPressed: onOpenSsh,
              icon: const Icon(Icons.terminal, size: 18),
              tooltip: 'Open SSH Terminal',
              visualDensity: VisualDensity.compact,
            ),
          const Spacer(),
          IconButton(
            onPressed: () => SettingsScreen.show(context),
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  final TabState tabState;

  const _StatusBar({required this.tabState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = tabState.activeTab;
    final transferStatus = ref.watch(transferStatusProvider).value;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (active != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active.connection.isConnected
                    ? AppTheme.connectedColor(theme.brightness)
                    : AppTheme.disconnectedColor(theme.brightness),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                active.connection.isConnected
                    ? 'Connected: ${active.connection.label}'
                    : 'Disconnected',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Text(
              'No active connection',
              style: TextStyle(fontSize: 11),
            ),
          const Spacer(),
          if (transferStatus != null && transferStatus.hasActive) ...[
            Icon(Icons.swap_vert, size: 12, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              transferStatus.currentInfo ?? '${transferStatus.running} active',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            '${tabState.tabs.length} tab(s)',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
