part of 'session_panel.dart';

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAddSession;
  final VoidCallback onAddFolder;
  const _PanelHeader({required this.onAddSession, required this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On mobile the shared AppIconButton already enlarges itself to a 40 px
    // touch target — we just add a filled background/rounded corners so the
    // two actions read as buttons, and give the header a bit more vertical
    // breathing room.
    final mobile = isMobilePlatform;
    final buttonBg = mobile ? AppTheme.bg3 : null;
    return Semantics(
      header: true,
      label: S.of(context).sessionsHeader,
      child: Container(
        height: mobile ? 52.0 : AppTheme.barHeightSm,
        padding: EdgeInsets.only(
          left: 12,
          right: mobile ? 8 : 2,
          top: mobile ? 6 : 0,
          bottom: mobile ? 6 : 0,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                S.of(context).sessionsHeader,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.sm,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.create_new_folder,
              onTap: onAddFolder,
              tooltip: S.of(context).newFolder,
              backgroundColor: buttonBg,
              borderRadius: AppTheme.radiusSm,
            ),
            if (mobile) const SizedBox(width: 8),
            AppIconButton(
              icon: Icons.add,
              onTap: onAddSession,
              tooltip: S.of(context).newConnection,
              backgroundColor: buttonBg,
              borderRadius: AppTheme.radiusSm,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AppBorderedBox(
        height: AppTheme.controlHeightSm,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: AppTheme.bg3,
        child: Row(
          children: [
            Icon(Icons.search, size: 12, color: AppTheme.fgFaint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: S.of(context).filter,
                  hintStyle: AppFonts.mono(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fgFaint,
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
                onChanged: onChanged,
              ),
            ),
            if (value.isNotEmpty)
              GestureDetector(
                onTap: () => onChanged(''),
                child: Icon(Icons.close, size: 12, color: AppTheme.fgFaint),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 40,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            S.of(context).noSavedSessions,
            style: TextStyle(
              fontSize: AppFonts.md,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          // `SelectionContainer.disabled` keeps the ambient MainScreen
          // `SelectionArea` from registering the button's label as
          // selectable — without it drag-select caught "+ Add Session"
          // as if it were body text, and Ctrl+C copied the label.
          SelectionContainer.disabled(
            child: AppButton(
              label: S.of(context).addSession,
              icon: Icons.add,
              onTap: onAdd,
              dense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Properties panel shown below the session tree on desktop.
/// Displays details of the selected session or folder.
class _SessionDetailsPanel extends StatelessWidget {
  final Session? session;
  final String? folderPath;
  final int folderItemCount;

  const _SessionDetailsPanel({
    this.session,
    this.folderPath,
    this.folderItemCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);

    final List<(String, String)> rows;
    if (session != null) {
      final s = session!;
      rows = [
        (l10n.name, s.label.isNotEmpty ? s.label : s.displayName),
        (l10n.host, s.host),
        (l10n.login, s.user),
        (l10n.protocol, 'SSH'),
        (l10n.port, s.port.toString()),
      ];
    } else if (folderPath != null && folderPath!.isNotEmpty) {
      final folderName = folderPath!.split('/').last;
      rows = [
        (l10n.name, folderName),
        (l10n.typeLabel, l10n.folder),
        (l10n.subitems, l10n.nSubitems(folderItemCount)),
      ];
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      constraints: const BoxConstraints(maxHeight: 160),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        shrinkWrap: true,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (label, value) = rows[index];
          return _DetailRow(label: label, value: value);
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showCopyMenu(context, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                label,
                style: TextStyle(fontSize: AppFonts.sm, color: dimColor),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(fontSize: AppFonts.sm),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopyMenu(BuildContext context, Offset position) {
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: S.of(context).copy,
          icon: Icons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ],
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedCount = ref.watch(sessionProvider).length;
    final summary = ref.watch(connectionSummaryProvider);
    final connectedCount = summary.connectedTotal;
    final connectingCount = summary.connectingTotal;
    final activeCount = summary.activeTotal;
    final ws = ref.watch(workspaceProvider);
    final tabCount = collectAllTabs(ws.root).length;

    final theme = Theme.of(context);
    final Color? connectionIconColor;
    if (connectedCount > 0) {
      connectionIconColor = AppTheme.connected;
    } else if (connectingCount > 0) {
      connectionIconColor = AppTheme.connecting;
    } else {
      connectionIconColor = null;
    }

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          StatusIndicator(
            icon: Icons.dns_outlined,
            count: savedCount,
            tooltip: S.of(context).savedSessions,
          ),
          const Spacer(),
          StatusIndicator(
            icon: Icons.wifi,
            count: activeCount,
            tooltip: S.of(context).activeConnections,
            iconColor: connectionIconColor,
          ),
          const SizedBox(width: 10),
          StatusIndicator(
            icon: Icons.tab_outlined,
            count: tabCount,
            tooltip: S.of(context).openTabs,
          ),
        ],
      ),
    );
  }
}
