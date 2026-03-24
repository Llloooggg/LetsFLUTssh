import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session/session.dart';
import 'core/ssh/errors.dart';
import 'features/session_manager/quick_connect_dialog.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_bar.dart';
import 'features/tabs/tab_controller.dart';
import 'features/tabs/welcome_screen.dart';
import 'features/terminal/terminal_tab.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/split_view.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'LetsFLUTssh',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              // Toolbar
              _Toolbar(onQuickConnect: () => _quickConnect(context, ref)),
              // Tab bar
              const AppTabBar(),
              if (tabState.tabs.isNotEmpty) const Divider(height: 1),
              // Split: sidebar | content
              Expanded(
                child: SplitView(
                  left: SessionPanel(
                    onConnect: (session) => _connectSession(context, ref, session),
                  ),
                  right: tabState.activeTab != null
                      ? _buildTabContent(tabState)
                      : WelcomeScreen(
                          onQuickConnect: () => _quickConnect(context, ref),
                        ),
                ),
              ),
              // Status bar
              _StatusBar(tabState: tabState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(TabState tabState) {
    return IndexedStack(
      index: tabState.activeIndex,
      children: tabState.tabs.map((tab) {
        return TerminalTab(
          key: ValueKey(tab.id),
          connection: tab.connection,
        );
      }).toList(),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onQuickConnect;

  const _Toolbar({required this.onQuickConnect});

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
          const Text(
            'LetsFLUTssh',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: onQuickConnect,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Quick Connect (Ctrl+N)',
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final TabState tabState;

  const _StatusBar({required this.tabState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = tabState.activeTab;
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
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              active.connection.isConnected
                  ? 'Connected: ${active.connection.label}'
                  : 'Disconnected',
              style: const TextStyle(fontSize: 11),
            ),
          ] else
            const Text(
              'No active connection',
              style: TextStyle(fontSize: 11),
            ),
          const Spacer(),
          Text(
            '${tabState.tabs.length} tab(s)',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
