import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../session_manager/session_connect.dart';
import '../session_manager/session_panel.dart';
import '../../widgets/app_icon_button.dart';
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

    // Force rebuild when theme changes — static AppTheme colors update via
    // setBrightness() in the app root, but this widget must re-run build()
    // to pick up the new values.
    ref.watch(themeModeProvider);

    _autoSwitchToSessionsIfNeeded(tabState);

    final hasActiveTabs = tabState.tabs.isNotEmpty;

    return PopScope(
      canPop: !hasActiveTabs && _navIndex == 0,
      onPopInvokedWithResult: (didPop, _) => _handlePopScope(didPop, context),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(child: _buildPageContent(tabState, context)),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(tabState),
      ),
    );
  }

  void _autoSwitchToSessionsIfNeeded(TabState tabState) {
    if (_navIndex == 1 && _terminalTabCount(tabState) == 0 ||
        _navIndex == 2 && _sftpTabCount(tabState) == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _navIndex = 0);
      });
    }
  }

  void _handlePopScope(bool didPop, BuildContext context) {
    if (didPop) return;
    if (_navIndex != 0) {
      setState(() => _navIndex = 0);
      return;
    }
    _confirmExit(context);
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      height: 44,
      color: AppTheme.bg1,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: AppTheme.radiusLg,
            ),
            child: Icon(Icons.terminal, size: 14, color: AppTheme.onAccent),
          ),
          const SizedBox(width: 8),
          Text(
            'LetsFLUTssh',
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fgBright,
            ),
          ),
          const SizedBox(width: 8),
          Builder(builder: (_) {
            final activeCount = (ref.watch(connectionsProvider).value ?? []).where((c) => c.isConnected).length;
            final savedCount = ref.watch(sessionProvider).length;
            return Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$activeCount active',
                  style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.green),
                ),
                TextSpan(
                  text: ' · $savedCount saved',
                  style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
                ),
              ]),
            );
          }),
          const Spacer(),
          AppIconButton(
            icon: Icons.settings,
            size: 15,
            boxSize: 32,
            backgroundColor: AppTheme.bg3,
            borderRadius: AppTheme.radiusLg,
            onTap: () => SettingsScreen.show(context),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(TabState tabState, BuildContext context) {
    return IndexedStack(
      index: _navIndex,
      children: [
        _MobileSessionsPage(
          onConnect: (session) => _connectSession(context, ref, session),
          onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
          onQuickConnect: (config) {
            SessionConnect.connectConfig(context, ref, config);
            setState(() => _navIndex = 1);
          },
        ),
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
    );
  }

  Widget _buildBottomNav(TabState tabState) {
    final termCount = _terminalTabCount(tabState);
    final sftpCount = _sftpTabCount(tabState);
    return Container(
      height: 56,
      color: AppTheme.bg1,
      child: Row(
        children: [
          _buildNavItem(
            index: 0,
            icon: Icons.dns_outlined,
            activeIcon: Icons.dns,
            label: 'Sessions',
          ),
          _buildNavItem(
            index: 1,
            icon: Icons.terminal_outlined,
            activeIcon: Icons.terminal,
            label: 'Terminal',
            badgeCount: termCount,
          ),
          _buildNavItem(
            index: 2,
            icon: Icons.folder_outlined,
            activeIcon: Icons.folder,
            label: 'Files',
            badgeCount: sftpCount,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = _navIndex == index;
    final isDisabled = badgeCount != null && badgeCount == 0;
    final opacity = isDisabled ? 0.4 : 1.0;
    final labelColor = isSelected
        ? AppTheme.fg
        : isDisabled
            ? AppTheme.fgFaint
            : AppTheme.fgDim;

    Widget iconWidget = Icon(
      isSelected ? activeIcon : icon,
      size: 24,
      color: labelColor,
    );
    if (badgeCount != null && badgeCount > 0) {
      iconWidget = Badge(
        label: Text('$badgeCount'),
        child: iconWidget,
      );
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled
            ? null
            : () => setState(() => _navIndex = index),
        child: Opacity(
          opacity: opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.xs,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ],
          ),
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
    return SizedBox(
      height: 32,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: widget.filteredTabs.length,
        itemBuilder: (context, index) =>
            _buildTabChip(widget.filteredTabs[index]),
      ),
    );
  }

  Widget _buildTabChip(TabEntry tab) {
    final isActive = tab.id == widget.activeTab.id;
    final isConnected = tab.connection.isConnected;
    final isTerminal = tab.kind == TabKind.terminal;
    final iconColor = _tabIconColor(isActive: isActive, isTerminal: isTerminal);
    Widget chip = GestureDetector(
      onTap: () {
        final globalIdx = widget.tabState.tabs.indexOf(tab);
        ref.read(tabProvider.notifier).selectTab(globalIdx);
      },
      child: SizedBox(
        height: 32,
        child: Stack(
          children: [
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: isActive ? AppTheme.bg2 : Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? AppTheme.green : AppTheme.fgFaint,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isTerminal ? Icons.terminal : Icons.folder,
                    size: 12,
                    color: iconColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tab.label,
                    style: AppFonts.inter(
                      fontSize: AppFonts.sm,
                      color: isActive ? AppTheme.fg : AppTheme.fgDim,
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => ref.read(tabProvider.notifier).closeTab(tab.id),
                      child: Icon(Icons.close, size: 12, color: AppTheme.fgDim),
                    ),
                  ],
                ],
              ),
            ),
            if (isActive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(height: 2, child: ColoredBox(color: AppTheme.accent)),
              ),
          ],
        ),
      ),
    );
    if (!isActive) {
      chip = Opacity(opacity: 0.5, child: chip);
    }
    return chip;
  }

  static Color _tabIconColor({required bool isActive, required bool isTerminal}) {
    if (!isActive) return AppTheme.fgFaint;
    return isTerminal ? AppTheme.blue : AppTheme.yellow;
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
                borderRadius: AppTheme.radiusLg,
              ),
              child: Icon(Icons.terminal, size: 22, color: AppTheme.fgFaint),
            ),
            const SizedBox(height: 12),
            Text('No active terminals', style: AppFonts.inter(fontSize: AppFonts.lg, color: AppTheme.fgDim)),
            const SizedBox(height: 4),
            Text('Connect from Sessions tab', style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint)),
          ],
        ),
      );
    }

    final activeTermTab = termTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : termTabs.last;

    return Column(
      children: [
        Container(
          color: AppTheme.bg1,
          child: Row(
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
                  padding: const EdgeInsets.only(right: 8),
                  child: _MobileCompanionButton(
                    label: 'Files',
                    icon: Icons.folder_open,
                    color: AppTheme.yellow,
                    tooltip: 'Open SFTP Browser',
                    onTap: onOpenSftp!,
                  ),
                ),
            ],
          ),
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
                borderRadius: AppTheme.radiusLg,
              ),
              child: Icon(Icons.folder, size: 22, color: AppTheme.fgFaint),
            ),
            const SizedBox(height: 12),
            Text('No active file browsers', style: AppFonts.inter(fontSize: AppFonts.lg, color: AppTheme.fgDim)),
            const SizedBox(height: 4),
            Text('Use "SFTP" from Sessions', style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint)),
          ],
        ),
      );
    }

    final activeSftpTab = sftpTabs.contains(tabState.activeTab)
        ? tabState.activeTab!
        : sftpTabs.last;

    return Column(
      children: [
        Container(
          color: AppTheme.bg1,
          child: Row(
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
                  padding: const EdgeInsets.only(right: 8),
                  child: _MobileCompanionButton(
                    label: 'Terminal',
                    icon: Icons.terminal,
                    color: AppTheme.blue,
                    tooltip: 'Open SSH Terminal',
                    onTap: onOpenSsh!,
                  ),
                ),
            ],
          ),
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

/// Styled companion button matching desktop's Terminal/Files button.
class _MobileCompanionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _MobileCompanionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  State<_MobileCompanionButton> createState() => _MobileCompanionButtonState();
}

class _MobileCompanionButtonState extends State<_MobileCompanionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final alpha = _pressed ? 0x30 / 255.0 : 0x18 / 255.0;
    final borderAlpha = _pressed ? 0x60 / 255.0 : 0x40 / 255.0;
    Widget button = GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: alpha),
          borderRadius: AppTheme.radiusMd,
          border: Border.all(
            color: widget.color.withValues(alpha: borderAlpha),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 13, color: widget.color),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w500,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
