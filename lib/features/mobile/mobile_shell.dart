import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/session_provider.dart';
import '../session_manager/session_connect.dart';
import '../session_manager/session_edit_dialog.dart';
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

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 300 && _navIndex > 0) {
              setState(() => _navIndex--);
            } else if (velocity < -300 && _navIndex < 2) {
              setState(() => _navIndex++);
            }
          },
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
              _MobileTerminalPage(tabState: tabState),
              // SFTP page
              _MobileSftpPage(tabState: tabState),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 60,
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
      floatingActionButton: _navIndex == 0
          ? FloatingActionButton(
              onPressed: () => _newSession(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  int _terminalTabCount(TabState s) =>
      s.tabs.where((t) => t.kind == TabKind.terminal).length;

  int _sftpTabCount(TabState s) =>
      s.tabs.where((t) => t.kind == TabKind.sftp).length;

  void _connectSession(BuildContext ctx, WidgetRef ref, Session session) {
    SessionConnect.connectTerminal(ctx, ref, session);
    setState(() => _navIndex = 1);
  }

  void _connectSessionSftp(BuildContext ctx, WidgetRef ref, Session session) {
    SessionConnect.connectSftp(ctx, ref, session);
    setState(() => _navIndex = 2);
  }

  Future<void> _newSession(BuildContext ctx, WidgetRef ref) async {
    final result = await SessionEditDialog.show(ctx);
    if (result == null || !ctx.mounted) return;
    switch (result) {
      case ConnectOnlyResult(:final config):
        SessionConnect.connectConfig(ctx, ref, config);
        setState(() => _navIndex = 1);
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect && ctx.mounted) {
          SessionConnect.connectTerminal(ctx, ref, session);
          setState(() => _navIndex = 1);
        }
    }
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
    return Column(
      children: [
        // App bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text(
                'LetsFLUTssh',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => SettingsScreen.show(context),
                icon: const Icon(Icons.settings, size: 22),
              ),
            ],
          ),
        ),
        // Session panel (reuses existing widget)
        Expanded(
          child: SessionPanel(
            onConnect: onConnect,
            onSftpConnect: onSftpConnect,
            onQuickConnect: onQuickConnect,
          ),
        ),
      ],
    );
  }
}

/// Horizontal chip-based tab selector shared by terminal and SFTP pages.
class _MobileTabChipBar extends ConsumerWidget {
  final TabState tabState;
  final List<TabEntry> filteredTabs;
  final TabEntry activeTab;

  const _MobileTabChipBar({
    required this.tabState,
    required this.filteredTabs,
    required this.activeTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: filteredTabs.length,
        itemBuilder: (context, index) {
          final tab = filteredTabs[index];
          final isActive = tab.id == activeTab.id;
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: InputChip(
              label: Text(tab.label, style: const TextStyle(fontSize: 13)),
              selected: isActive,
              onPressed: () {
                final globalIdx = tabState.tabs.indexOf(tab);
                ref.read(tabProvider.notifier).selectTab(globalIdx);
              },
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => ref.read(tabProvider.notifier).closeTab(tab.id),
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

  const _MobileTerminalPage({required this.tabState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termTabs = tabState.tabs.where((t) => t.kind == TabKind.terminal).toList();
    if (termTabs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 64, color: Colors.white24),
            SizedBox(height: 12),
            Text('No active terminals', style: TextStyle(fontSize: 14)),
            SizedBox(height: 4),
            Text('Connect from Sessions tab', style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      );
    }

    final activeTermTab = termTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : termTabs.last;

    return Column(
      children: [
        _MobileTabChipBar(
          tabState: tabState,
          filteredTabs: termTabs,
          activeTab: activeTermTab,
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

  const _MobileSftpPage({required this.tabState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sftpTabs = tabState.tabs.where((t) => t.kind == TabKind.sftp).toList();
    if (sftpTabs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder, size: 64, color: Colors.white24),
            SizedBox(height: 12),
            Text('No active file browsers', style: TextStyle(fontSize: 14)),
            SizedBox(height: 4),
            Text('Use "SFTP" from Sessions', style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      );
    }

    final activeSftpTab = sftpTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : sftpTabs.last;

    return Column(
      children: [
        _MobileTabChipBar(
          tabState: tabState,
          filteredTabs: sftpTabs,
          activeTab: activeSftpTab,
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
