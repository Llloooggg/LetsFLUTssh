import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../session_manager/session_connect.dart';
import '../session_manager/session_panel.dart';
import '../settings/settings_screen.dart';
import '../tabs/tab_controller.dart';
import '../tabs/tab_model.dart';
import 'mobile_file_browser.dart';
import 'mobile_terminal_view.dart';

/// Mobile navigation shell — bottom navigation with 3 destinations.
///
/// Sessions (list) | Terminal (active) | SFTP (active)
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _navIndex = 0; // 0 = sessions, 1 = terminal, 2 = sftp

  @override
  Widget build(BuildContext context) {
    final tabState = ref.watch(tabProvider);

    // Watch connection state changes so SFTP button updates when connect finishes
    ref.watch(connectionsProvider);
    final hasActiveTabs = tabState.tabs.isNotEmpty;

    return PopScope(
      canPop: !hasActiveTabs && _navIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // If not on sessions tab, go back to sessions
        if (_navIndex != 0) {
          setState(() => _navIndex = 0);
          return;
        }
        // On sessions tab with active tabs — confirm exit
        _confirmExit(context);
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Global app bar visible on all tabs
            Container(
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.bg1,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.terminal, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LetsFLUTssh',
                    style: AppFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.fgBright,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Builder(builder: (_) {
                    final activeCount = (ref.watch(connectionsProvider).value ?? []).length;
                    final savedCount = ref.watch(sessionProvider).length;
                    return Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '$activeCount active',
                          style: AppFonts.inter(fontSize: 10, color: AppTheme.green),
                        ),
                        TextSpan(
                          text: ' · $savedCount saved',
                          style: AppFonts.inter(fontSize: 10, color: AppTheme.fgFaint),
                        ),
                      ]),
                    );
                  }),
                  const Spacer(),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      onPressed: () => SettingsScreen.show(context),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.bg3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.settings, size: 15, color: AppTheme.fgDim),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _navIndex,
                children: [
                  // Sessions page
                  _MobileSessionsPage(
                    onConnect: (session) => _connectSession(context, ref, session),
                    onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
                    onQuickConnect: (config) {
                      SessionConnect.connectConfig(context, ref, config);
                      setState(() => _navIndex = 1);
                    },
                  ),
                  // Terminal page
                  _MobileTerminalPage(
                    tabState: tabState,
                    onOpenSftp: _activeTerminalConnection(tabState)?.isConnected == true
                        ? () {
                            final conn = _activeTerminalConnection(tabState)!;
                            ref.read(tabProvider.notifier).addSftpTab(conn);
                            setState(() => _navIndex = 2);
                          }
                        : null,
                  ),
                  // SFTP page
                  _MobileSftpPage(
                    tabState: tabState,
                    onOpenSsh: _activeSftpConnection(tabState)?.isConnected == true
                        ? () {
                            final conn = _activeSftpConnection(tabState)!;
                            ref.read(tabProvider.notifier).addTerminalTab(conn);
                            setState(() => _navIndex = 1);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 56,
        backgroundColor: AppTheme.bg1,
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _terminalTabCount(tabState) > 0,
              label: Text('${_terminalTabCount(tabState)}'),
              child: const Icon(Icons.terminal_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _terminalTabCount(tabState) > 0,
              label: Text('${_terminalTabCount(tabState)}'),
              child: const Icon(Icons.terminal),
            ),
            label: 'Terminal',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _sftpTabCount(tabState) > 0,
              label: Text('${_sftpTabCount(tabState)}'),
              child: const Icon(Icons.folder_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _sftpTabCount(tabState) > 0,
              label: Text('${_sftpTabCount(tabState)}'),
              child: const Icon(Icons.folder),
            ),
            label: 'Files',
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit'),
        content: const Text('Active sessions will be disconnected. Exit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Connection? _activeTerminalConnection(TabState s) {
    final termTabs = s.tabs.where((t) => t.kind == TabKind.terminal).toList();
    if (termTabs.isEmpty) return null;
    final active = termTabs.contains(s.activeTab) ? s.activeTab! : termTabs.last;
    return active.connection;
  }

  Connection? _activeSftpConnection(TabState s) {
    final sftpTabs = s.tabs.where((t) => t.kind == TabKind.sftp).toList();
    if (sftpTabs.isEmpty) return null;
    final active = sftpTabs.contains(s.activeTab) ? s.activeTab! : sftpTabs.last;
    return active.connection;
  }

  int _terminalTabCount(TabState s) =>
      s.tabs.where((t) => t.kind == TabKind.terminal).length;

  int _sftpTabCount(TabState s) =>
      s.tabs.where((t) => t.kind == TabKind.sftp).length;

  void _connectSession(BuildContext ctx, WidgetRef ref, Session session) {
    final ok = SessionConnect.connectTerminal(ctx, ref, session);
    if (ok) setState(() => _navIndex = 1);
  }

  void _connectSessionSftp(BuildContext ctx, WidgetRef ref, Session session) {
    final ok = SessionConnect.connectSftp(ctx, ref, session);
    if (ok) setState(() => _navIndex = 2);
  }

}

/// Sessions page — full screen session list with settings access.
class _MobileSessionsPage extends ConsumerWidget {
  final void Function(Session) onConnect;
  final void Function(Session) onSftpConnect;
  final void Function(SSHConfig config) onQuickConnect;
  const _MobileSessionsPage({
    required this.onConnect,
    required this.onSftpConnect,
    required this.onQuickConnect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Header moved to MobileShell — visible on all tabs
    return SessionPanel(
      onConnect: onConnect,
      onSftpConnect: onSftpConnect,
      onQuickConnect: onQuickConnect,
    );
  }
}

/// Horizontal chip-based tab selector shared by terminal and SFTP pages.
class _MobileTabChipBar extends ConsumerStatefulWidget {
  final TabState tabState;
  final List<TabEntry> filteredTabs;
  final TabEntry activeTab;

  const _MobileTabChipBar({
    required this.tabState,
    required this.filteredTabs,
    required this.activeTab,
  });

  @override
  ConsumerState<_MobileTabChipBar> createState() => _MobileTabChipBarState();
}

class _MobileTabChipBarState extends ConsumerState<_MobileTabChipBar> {
  final _scrollController = ScrollController();
  int _previousTabCount = 0;

  @override
  void initState() {
    super.initState();
    _previousTabCount = widget.filteredTabs.length;
  }

  @override
  void didUpdateWidget(_MobileTabChipBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to end when a new tab is added
    if (widget.filteredTabs.length > _previousTabCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
    _previousTabCount = widget.filteredTabs.length;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg1,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      height: 36,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        itemCount: widget.filteredTabs.length,
        itemBuilder: (context, index) {
          final tab = widget.filteredTabs[index];
          final isActive = tab.id == widget.activeTab.id;
          final isConnected = tab.connection.isConnected;
          final isTerminal = tab.kind == TabKind.terminal;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                final globalIdx = widget.tabState.tabs.indexOf(tab);
                ref.read(tabProvider.notifier).selectTab(globalIdx);
              },
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.selection : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(13),
                  border: isActive
                      ? Border.all(color: AppTheme.accent.withValues(alpha: 0x30 / 255))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? AppTheme.green : AppTheme.fgFaint,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      isTerminal ? Icons.terminal : Icons.folder,
                      size: 10,
                      color: isActive ? AppTheme.accent : AppTheme.fgFaint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tab.label,
                      style: AppFonts.inter(
                        fontSize: 10,
                        color: isActive ? AppTheme.fg : AppTheme.fgDim,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => ref.read(tabProvider.notifier).closeTab(tab.id),
                        child: const Icon(Icons.close, size: 12, color: AppTheme.fgDim),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Terminal page — shows active terminal tab or empty state.
class _MobileTerminalPage extends ConsumerWidget {
  final TabState tabState;
  final VoidCallback? onOpenSftp;

  const _MobileTerminalPage({
    required this.tabState,
    this.onOpenSftp,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termTabs = tabState.tabs.where((t) => t.kind == TabKind.terminal).toList();
    if (termTabs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.terminal, size: 22, color: AppTheme.fgFaint),
            ),
            const SizedBox(height: 12),
            Text('No active terminals', style: AppFonts.inter(fontSize: 13, color: AppTheme.fgDim)),
            const SizedBox(height: 4),
            Text('Connect from Sessions tab', style: AppFonts.inter(fontSize: 11, color: AppTheme.fgFaint)),
          ],
        ),
      );
    }

    final activeTermTab = termTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : termTabs.last;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MobileTabChipBar(
                tabState: tabState,
                filteredTabs: termTabs,
                activeTab: activeTermTab,
              ),
            ),
            if (onOpenSftp != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  onPressed: onOpenSftp,
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: 'Open SFTP Browser',
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        Expanded(
          child: MobileTerminalView(
            key: ValueKey(activeTermTab.id),
            connection: activeTermTab.connection,
          ),
        ),
      ],
    );
  }
}

/// SFTP page — shows active SFTP tab or empty state.
class _MobileSftpPage extends ConsumerWidget {
  final TabState tabState;
  final VoidCallback? onOpenSsh;

  const _MobileSftpPage({required this.tabState, this.onOpenSsh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sftpTabs = tabState.tabs.where((t) => t.kind == TabKind.sftp).toList();
    if (sftpTabs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.bg3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.folder, size: 22, color: AppTheme.fgFaint),
            ),
            const SizedBox(height: 12),
            Text('No active file browsers', style: AppFonts.inter(fontSize: 13, color: AppTheme.fgDim)),
            const SizedBox(height: 4),
            Text('Use "SFTP" from Sessions', style: AppFonts.inter(fontSize: 11, color: AppTheme.fgFaint)),
          ],
        ),
      );
    }

    final activeSftpTab = sftpTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : sftpTabs.last;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MobileTabChipBar(
                tabState: tabState,
                filteredTabs: sftpTabs,
                activeTab: activeSftpTab,
              ),
            ),
            if (onOpenSsh != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  onPressed: onOpenSsh,
                  icon: const Icon(Icons.terminal, size: 20),
                  tooltip: 'Open SSH Terminal',
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        Expanded(
          child: MobileFileBrowser(
            key: ValueKey(activeSftpTab.id),
            connection: activeSftpTab.connection,
          ),
        ),
      ],
    );
  }
}
