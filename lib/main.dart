import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connection/connection.dart';
import 'core/session/session.dart';
import 'core/ssh/errors.dart';
import 'features/settings/export_import.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/toast.dart';
import 'features/file_browser/file_browser_tab.dart';
import 'features/settings/settings_screen.dart';
import 'features/session_manager/quick_connect_dialog.dart';
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
import 'features/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';
import 'utils/platform.dart' as plat;
import 'widgets/split_view.dart';

/// Global navigator key for showing dialogs from non-UI contexts
/// (e.g., host key verification during SSH handshake).
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LetsFLUTsshApp()));
}

class LetsFLUTsshApp extends ConsumerStatefulWidget {
  const LetsFLUTsshApp({super.key});

  @override
  ConsumerState<LetsFLUTsshApp> createState() => _LetsFLUTsshAppState();
}

class _LetsFLUTsshAppState extends ConsumerState<LetsFLUTsshApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(configProvider.notifier).load();
      ref.read(sessionProvider.notifier).load();
      _setupHostKeyCallbacks();
    });
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
  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar)
    if (plat.isMobilePlatform) {
      return const MobileShell();
    }

    final tabState = ref.watch(tabProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          _quickConnect(context, ref);
        },
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final active = tabState.activeTab;
          if (active != null) {
            ref.read(tabProvider.notifier).closeTab(active.id);
          }
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () {
          if (tabState.tabs.length > 1) {
            final next = (tabState.activeIndex + 1) % tabState.tabs.length;
            ref.read(tabProvider.notifier).selectTab(next);
          }
        },
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () {
          if (tabState.tabs.length > 1) {
            final prev = (tabState.activeIndex - 1 + tabState.tabs.length) % tabState.tabs.length;
            ref.read(tabProvider.notifier).selectTab(prev);
          }
        },
      },
      child: DropTarget(
          onDragDone: (details) {
            final lfsFiles = details.files
                .where((f) => f.path.endsWith('.lfs'))
                .toList();
            if (lfsFiles.isNotEmpty) {
              _showLfsImportDialog(context, lfsFiles.first.path);
            }
          },
          child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            final sessionPanel = SessionPanel(
              onConnect: (session) => _connectSession(context, ref, session),
              onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
            );

            final content = tabState.activeTab != null
                ? _buildTabContent(tabState)
                : WelcomeScreen(
                    onQuickConnect: () => _quickConnect(context, ref),
                  );

            // Right side: toolbar + tabs + content + status bar
            final rightSide = Column(
              children: [
                // Toolbar
                _Toolbar(
                  onQuickConnect: () => _quickConnect(context, ref),
                  onOpenSftp: tabState.activeTab != null &&
                          tabState.activeTab!.connection.isConnected
                      ? () => _openSftp(ref, tabState.activeTab!.connection)
                      : null,
                  showMenuButton: isNarrow,
                ),
                // Tab bar
                const AppTabBar(),
                if (tabState.tabs.isNotEmpty) const Divider(height: 1),
                // Content area
                Expanded(child: content),
                // Status bar
                _StatusBar(tabState: tabState),
              ],
            );

            if (isNarrow) {
              return Scaffold(
                drawer: Drawer(width: 280, child: SafeArea(child: sessionPanel)),
                body: rightSide,
              );
            }

            // Desktop: full-height sidebar | right side
            return Scaffold(
              body: SplitView(
                left: sessionPanel,
                right: rightSide,
              ),
            );
          },
        ),
      ),
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
            );
        }
      }).toList(),
    );
  }

  void _openSftp(WidgetRef ref, Connection connection) {
    ref.read(tabProvider.notifier).addSftpTab(connection);
  }

  Future<void> _connectSessionSftp(BuildContext context, WidgetRef ref, Session session) async {
    final config = session.toSSHConfig();
    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(
        config,
        label: session.label.isNotEmpty ? session.label : session.displayName,
      );
      ref.read(tabProvider.notifier).addSftpTab(conn);
    } on AuthError catch (e) {
      if (context.mounted) _showError(context, 'Authentication failed: ${e.message}');
    } on ConnectError catch (e) {
      if (context.mounted) _showError(context, 'Connection failed: ${e.message}');
    } catch (e) {
      if (context.mounted) _showError(context, 'Error: $e');
    }
  }

  Future<void> _connectSession(BuildContext context, WidgetRef ref, Session session) async {
    final config = session.toSSHConfig();
    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(
        config,
        label: session.label.isNotEmpty ? session.label : session.displayName,
      );
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    } on AuthError catch (e) {
      if (context.mounted) _showError(context, 'Authentication failed: ${e.message}');
    } on ConnectError catch (e) {
      if (context.mounted) _showError(context, 'Connection failed: ${e.message}');
    } catch (e) {
      if (context.mounted) _showError(context, 'Error: $e');
    }
  }

  Future<void> _quickConnect(BuildContext context, WidgetRef ref) async {
    final config = await QuickConnectDialog.show(context);
    if (config == null) return;
    if (!context.mounted) return;

    try {
      final manager = ref.read(connectionManagerProvider);
      final conn = await manager.connect(config);
      ref.read(tabProvider.notifier).addTerminalTab(conn);
    } on AuthError catch (e) {
      if (context.mounted) _showError(context, 'Authentication failed: ${e.message}');
    } on ConnectError catch (e) {
      if (context.mounted) _showError(context, 'Connection failed: ${e.message}');
    } catch (e) {
      if (context.mounted) _showError(context, 'Error: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    Toast.show(context, message: message, level: ToastLevel.error);
  }

  Future<void> _showLfsImportDialog(BuildContext context, String filePath) async {
    final passwordCtrl = TextEditingController();

    final result = await showDialog<({String password, ImportMode mode})>(
      context: context,
      builder: (ctx) {
        var mode = ImportMode.merge;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Import Data'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  File(filePath).uri.pathSegments.last,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Master Password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    if (v.isNotEmpty) {
                      Navigator.pop(ctx, (password: v, mode: mode));
                    }
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<ImportMode>(
                  segments: const [
                    ButtonSegment(
                      value: ImportMode.merge,
                      label: Text('Merge'),
                      icon: Icon(Icons.merge, size: 16),
                    ),
                    ButtonSegment(
                      value: ImportMode.replace,
                      label: Text('Replace'),
                      icon: Icon(Icons.swap_horiz, size: 16),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 4),
                Text(
                  mode == ImportMode.merge
                      ? 'Add new sessions, keep existing'
                      : 'Replace all sessions with imported',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (passwordCtrl.text.isEmpty) return;
                  Navigator.pop(ctx, (password: passwordCtrl.text, mode: mode));
                },
                child: const Text('Import'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null || !context.mounted) return;

    try {
      final importResult = await ExportImport.import_(
        filePath: filePath,
        masterPassword: result.password,
        mode: result.mode,
        importConfig: true,
        importKnownHosts: true,
      );

      final sessionNotifier = ref.read(sessionProvider.notifier);
      if (importResult.mode == ImportMode.replace) {
        final existing = ref.read(sessionProvider);
        for (final s in existing) {
          await sessionNotifier.delete(s.id);
        }
      }
      for (final s in importResult.sessions) {
        try {
          await sessionNotifier.add(s);
        } catch (e) {
          if (importResult.mode == ImportMode.replace) rethrow;
          debugPrint('Import: skipped session ${s.label}: $e');
        }
      }

      if (importResult.config != null) {
        ref.read(configProvider.notifier).update((_) => importResult.config!);
      }

      if (context.mounted) {
        Toast.show(
          context,
          message: 'Imported ${importResult.sessions.length} session(s)',
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, message: 'Import failed: $e', level: ToastLevel.error);
      }
    }
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onQuickConnect;
  final VoidCallback? onOpenSftp;
  final bool showMenuButton;

  const _Toolbar({
    required this.onQuickConnect,
    this.onOpenSftp,
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
            onPressed: onQuickConnect,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Quick Connect (Ctrl+N)',
            visualDensity: VisualDensity.compact,
          ),
          if (onOpenSftp != null)
            IconButton(
              onPressed: onOpenSftp,
              icon: const Icon(Icons.folder_open, size: 18),
              tooltip: 'Open SFTP Browser',
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
    final transferStatus = ref.watch(transferStatusProvider).valueOrNull;

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
