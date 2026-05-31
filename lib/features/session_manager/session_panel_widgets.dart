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
                  fontFamily: AppFonts.interFamily,
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
            if (mobile) const SizedBox(width: AppSpacing.sm),
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
            const SizedBox(width: AppSpacing.sm),
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
      child: Padding(
        // Gutter on every side so the centred column stops short of
        // the sidebar edge — matches the rhythm of [AppEmptyState]
        // used in the collection dialogs and keeps the primary
        // action button surrounded by visible breathing room.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
            const SizedBox(height: AppSpacing.sm),
            Text(
              S.of(context).noSavedSessions,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFonts.md,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // The only action this state offers — render at the
            // primary accent weight so the user reads it as the
            // expected next move. `SelectionContainer.disabled`
            // keeps the ambient MainScreen `SelectionArea` from
            // registering the button's label as drag-selectable
            // body text.
            SelectionContainer.disabled(
              child: AppButton.primary(
                label: S.of(context).addSession,
                icon: Icons.add,
                onTap: onAdd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Properties panel shown below the session tree on desktop.
/// Displays details of the selected session or folder.
///
/// SSH details (host / login / port) sit on the in-memory [Session]
/// row, so they render synchronously. WebDAV and S3 keep their
/// transport tuple on a join table — this widget fetches it async via
/// FRB ([rust_db.dbWebdavSessionDetailsGet] /
/// [rust_db.dbS3SessionDetailsGet]) keyed on the focused session id,
/// re-fetching when focus moves (a new id / kind) or when a
/// [BusEvent.sessionsChanged] lands (the edit dialog saved new
/// transport details for the same focused session). The fetched
/// details are never cached past the current focus — Rust stays the
/// source of truth, and a stale focus token / unmount drops late
/// results.
class _SessionDetailsPanel extends StatefulWidget {
  final Session? session;
  final String? folderPath;
  final int folderItemCount;

  const _SessionDetailsPanel({
    this.session,
    this.folderPath,
    this.folderItemCount = 0,
  });

  @override
  State<_SessionDetailsPanel> createState() => _SessionDetailsPanelState();
}

class _SessionDetailsPanelState extends State<_SessionDetailsPanel> {
  rust_db.DbWebDavSessionDetails? _webdav;
  rust_db.DbS3SessionDetails? _s3;

  /// Monotonic guard so a slow fetch for a session that lost focus
  /// before its FRB call returned can't overwrite the current one.
  int _fetchToken = 0;

  StreamSubscription<BusEvent>? _busSub;

  @override
  void initState() {
    super.initState();
    // `BusTopic.sessions` carries only `SessionsChanged`, so any event
    // on it means session/detail state moved — re-fetch the focused
    // session's transport tuple in case the edit dialog just saved it.
    _busSub = AppBus.instance
        .subscribe(BusTopic.sessions)
        .listen((_) => _fetchDetails());
    _fetchDetails();
  }

  @override
  void didUpdateWidget(covariant _SessionDetailsPanel old) {
    super.didUpdateWidget(old);
    final oldSession = old.session;
    final newSession = widget.session;
    if (oldSession?.id != newSession?.id ||
        oldSession?.kind != newSession?.kind) {
      // Focus moved — drop the previous session's details so its rows
      // never flash under the new session's name, then load afresh.
      _webdav = null;
      _s3 = null;
      _fetchDetails();
    }
  }

  /// Load the async transport tuple for the focused WebDAV / S3
  /// session. SSH and folders carry everything they need synchronously
  /// so they no-op here. A pre-FRB callsite (cold start) or a missing
  /// row throws / returns null — caught and logged, leaving the panel
  /// on name + protocol.
  Future<void> _fetchDetails() async {
    final s = widget.session;
    final token = ++_fetchToken;
    if (s == null) return;
    try {
      switch (s.kind) {
        case SessionKind.webdav:
          final d = await rust_db.dbWebdavSessionDetailsGet(sessionId: s.id);
          if (!mounted || token != _fetchToken) return;
          setState(() => _webdav = d);
        case SessionKind.s3:
          final d = await rust_db.dbS3SessionDetailsGet(sessionId: s.id);
          if (!mounted || token != _fetchToken) return;
          setState(() => _s3 = d);
        case SessionKind.ssh:
          return;
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'Session details panel fetch failed',
        name: 'SessionPanel',
        error: e,
        stackTrace: st,
        level: LogLevel.warn,
      );
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);

    final List<(String, String)> rows;
    if (widget.session != null) {
      rows = sessionDetailRows(
        session: widget.session!,
        l10n: l10n,
        webdav: _webdav,
        s3: _s3,
      );
    } else if (widget.folderPath != null && widget.folderPath!.isNotEmpty) {
      final folderName = widget.folderPath!.split('/').last;
      rows = [
        (l10n.name, folderName),
        (l10n.typeLabel, l10n.folder),
        (l10n.subitems, l10n.nSubitems(widget.folderItemCount)),
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
        StandardMenuAction.copy.item(
          context,
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
    // `.select` so the footer rebuilds only when the count changes,
    // not on every per-session field edit (label rename, folder
    // move, etc.) that the full list rebuild would otherwise
    // trigger.
    final savedCount = ref.watch(sessionProvider.select((s) => s.length));
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
      padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
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
