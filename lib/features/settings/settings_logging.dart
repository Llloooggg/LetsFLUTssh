part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Logging section — enable toggle, live log viewer, export/clear
// ═══════════════════════════════════════════════════════════════════

class _LoggingSection extends ConsumerWidget {
  const _LoggingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(configProvider.select((c) => c.logLevel));
    final enabled = level != null;
    final logPath = AppLogger.instance.logPath;

    return Column(
      children: [
        _LogLevelSelector(
          selected: level,
          onChanged: (next) => ref
              .read(configProvider.notifier)
              .update(
                (c) =>
                    c.copyWith(behavior: c.behavior.copyWith(logLevel: next)),
              ),
        ),
        // Show the viewer when logging is active OR when a previous session
        // left log content on disk — disabling stops new writes but
        // captured entries need to stay reachable (read / export / clear).
        // If the level is off AND the file is empty, hide the viewer to
        // keep the settings screen short.
        if (logPath != null)
          _LogViewerHost(
            enabled: enabled,
            onExport: () => _exportLog(context),
            onClear: () => _clearLogs(context),
          ),
      ],
    );
  }

  Future<void> _exportLog(BuildContext context) async {
    try {
      final content = await AppLogger.instance.readLog();
      if (!context.mounted) return;
      if (content.isEmpty) {
        Toast.show(
          context,
          message: S.of(context).logIsEmpty,
          level: ToastLevel.info,
        );
        return;
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final defaultName = 'letsflutssh_log_$timestamp.txt';

      final saveTitle = S.of(context).saveLogAs;
      final chooseTitle = S.of(context).chooseSaveLocation;
      final initDir = await _defaultDirectory();

      String? outputPath;
      if (plat.isDesktopPlatform) {
        outputPath = await FilePicker.saveFile(
          dialogTitle: saveTitle,
          fileName: defaultName,
          initialDirectory: initDir,
          type: FileType.custom,
          allowedExtensions: ['txt', 'log'],
        );
      } else {
        final dir = await FilePicker.getDirectoryPath(
          dialogTitle: chooseTitle,
          initialDirectory: initDir,
        );
        if (dir != null) outputPath = p.join(dir, defaultName);
      }

      if (outputPath == null || !context.mounted) return;

      await rust_logger.loggerExportTo(targetPath: outputPath);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).logExportedTo(outputPath),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'Log export failed: $e',
        name: 'Settings',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: S
              .of(context)
              .logExportFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    }
  }

  Future<void> _clearLogs(BuildContext context) async {
    await AppLogger.instance.clearLogs();
    if (!context.mounted) return;
    Toast.show(
      context,
      message: S.of(context).logsCleared,
      level: ToastLevel.info,
    );
  }
}

/// Wrapper that resolves whether the viewer has anything to show:
///   * Logging ON → mount as Live Log.
///   * Logging OFF + archive on disk → mount as Archived Log (read /
///     export / clear stay reachable, no live writes happen because
///     the sink is closed).
///   * Logging OFF + archive empty → render nothing so the settings
///     screen stays compact.
///
/// Probe is a sync `File.lengthSync()` check on the log path. Async
/// `readLog()` would deadlock against the inner viewer's listener
/// pump in widget tests that pump discrete frames.
class _LogViewerHost extends StatelessWidget {
  final bool enabled;
  final VoidCallback onExport;
  final VoidCallback onClear;

  const _LogViewerHost({
    required this.enabled,
    required this.onExport,
    required this.onClear,
  });

  bool _logFileHasContent() {
    return rust_logger.loggerLogFileHasContent();
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled && !_logFileHasContent()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _LiveLogViewer(
        onExport: onExport,
        onClear: onClear,
        active: enabled,
      ),
    );
  }
}

/// Inline live log viewer. Rendered as a `ListView.builder` of
/// styled rows wrapped in a `SelectionArea` — drag-select crosses
/// row boundaries natively, the right-click context menu is
/// Flutter's adaptive Copy / Select All toolbar, and each row
/// carries a level-tinted left border + tag chip without any ANSI
/// hackery. Data flows through the app-level [LogStore] singleton
/// which is seeded at boot and updated live by `AppLogger.liveEntries`,
/// so opening the tab is instant.
class _LiveLogViewer extends ConsumerStatefulWidget {
  final VoidCallback onExport;
  final VoidCallback onClear;

  /// Whether the user currently has a logging threshold set — drives
  /// the toolbar label + indicator dot colour. When `false` the viewer
  /// still renders (so archived entries from a previous session stay
  /// reachable for read / export / clear) but reads as "Archived log"
  /// / dim dot rather than "Live Log" / green dot, to avoid suggesting
  /// writes are still happening.
  final bool active;

  const _LiveLogViewer({
    required this.onExport,
    required this.onClear,
    required this.active,
  });

  @override
  ConsumerState<_LiveLogViewer> createState() => _LiveLogViewerState();
}

class _LiveLogViewerState extends ConsumerState<_LiveLogViewer> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late final LogStore _store;

  /// Auto-scroll to the bottom on new entries while the user has not
  /// manually scrolled up. Flips off when the scroll position drifts
  /// from the bottom; flips back on when the user scrolls to the
  /// bottom again.
  bool _follow = true;

  /// Which severity levels render in the viewer. All three start on;
  /// users can hide info noise to focus on warnings + errors during a
  /// support session.
  final Set<LogLevel> _visibleLevels = {...LogLevel.values};

  /// Case-insensitive substring filter on the message body. Applied
  /// after the level filter (AND).
  String _query = '';

  @override
  void initState() {
    super.initState();
    _store = ref.read(logStoreProvider);
    _store.addListener(_onStoreChanged);
    _scrollController.addListener(_onScroll);
    // Idempotent — `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners`
    // already kicked the seed at boot. This just reads the
    // already-primed singleton; if the seed is still running the
    // live stream will populate the store as entries arrive.
    unawaited(_store.ensureSeeded());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 8;
    if (atBottom != _follow) setState(() => _follow = atBottom);
  }

  void _pushFilter() {
    _store.applyFilter(visibleLevels: _visibleLevels, query: _query);
    // The store rebuilds the filtered list and notifies; force a
    // re-snap to bottom so the viewer doesn't sit at a now-invalid
    // scroll offset.
    _follow = true;
  }

  @override
  Widget build(BuildContext context) {
    final mobile = plat.isMobilePlatform;
    final buttonBg = mobile ? AppTheme.bg3 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(context, mobile, buttonBg),
        const SizedBox(height: AppSpacing.xxs),
        // Box height = viewport - 280 px chrome budget, floored at 200,
        // so the viewer fills the dialog on tall windows but still
        // leaves a usable strip on short ones.
        LayoutBuilder(
          builder: (context, _) {
            final viewportHeight = MediaQuery.of(context).size.height;
            final maxHeight = (viewportHeight - 280).clamp(
              200.0,
              double.infinity,
            );
            return _buildLogBox(maxHeight);
          },
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, bool mobile, Color? buttonBg) {
    final theme = Theme.of(context);
    final indicatorColor = widget.active
        ? AppTheme.green
        : theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final titleText = widget.active ? S.of(context).liveLog : 'Archived log';
    // Title sits in `Expanded` (tight flex) so it takes all remaining
    // width between the indicator dot and the buttons, ellipsising
    // when too narrow. Without `Expanded` the buttons are visually
    // pulled left of the right edge — `Flexible(loose) + Spacer(tight)`
    // splits the remaining space 50/50 and parks the unused half of
    // the title slot between title content and the buttons.
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: indicatorColor),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            titleText,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFonts.md,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        AppIconButton(
          icon: Icons.copy,
          onTap: () => _copyLogToClipboard(context),
          tooltip: S.of(context).copyLog,
          backgroundColor: buttonBg,
          borderRadius: AppTheme.radiusSm,
        ),
        if (mobile) const SizedBox(width: AppSpacing.sm),
        AppIconButton(
          icon: Icons.save_alt,
          onTap: widget.onExport,
          tooltip: S.of(context).exportLog,
          backgroundColor: buttonBg,
          borderRadius: AppTheme.radiusSm,
        ),
        if (mobile) const SizedBox(width: AppSpacing.sm),
        AppIconButton(
          icon: Icons.delete_outline,
          onTap: _clearAndRefresh,
          tooltip: S.of(context).clearLogs,
          backgroundColor: buttonBg,
          borderRadius: AppTheme.radiusSm,
        ),
      ],
    );
  }

  /// Copy semantics: serialise every entry currently in the store's
  /// `allEntries` list (filter-independent — a "Copy log" button means
  /// "everything captured", not "what is shown after my level filter").
  /// Falls back to a "log is empty" toast when nothing has been
  /// logged yet. The right-click context menu inside the viewer
  /// handles selection-aware copy via `SelectionArea`.
  void _copyLogToClipboard(BuildContext context) {
    final entries = _store.allEntries;
    final buf = StringBuffer();
    for (final e in entries) {
      if (e.isHeader) {
        buf.writeln(e.message);
        continue;
      }
      buf.writeln(
        '${e.timestamp ?? ''} ${e.level == null ? '' : _levelMarker(e.level!)} '
        '[${e.tag ?? 'App'}] ${e.message}',
      );
      for (final c in e.continuations) {
        buf.writeln(c);
      }
    }
    final text = buf.toString();
    Clipboard.setData(ClipboardData(text: text));
    Toast.show(
      context,
      message: text.isEmpty
          ? S.of(context).logIsEmpty
          : S.of(context).copiedToClipboard,
      level: ToastLevel.info,
    );
  }

  static String _levelMarker(LogLevel l) => switch (l) {
    LogLevel.info => 'I',
    LogLevel.warn => 'W',
    LogLevel.error => 'E',
  };

  Future<void> _clearAndRefresh() async {
    widget.onClear();
    // The on-disk wipe is async (file delete); the in-memory store
    // is wiped synchronously here so the viewer empties even if the
    // file delete is still pending.
    _store.clearAll();
  }

  Widget _buildLogBox(double maxHeight) {
    return Container(
      width: double.infinity,
      height: maxHeight,
      decoration: BoxDecoration(
        color: AppTheme.bg0,
        border: Border.all(color: AppTheme.borderLight, width: 1),
        borderRadius: AppTheme.radiusSm,
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LogFilterBar(
            visibleLevels: _visibleLevels,
            query: _query,
            searchController: _searchController,
            onLevelToggle: _toggleLevel,
            onQueryChanged: (q) {
              setState(() => _query = q);
              _pushFilter();
            },
          ),
          const SizedBox(height: AppSpacing.xxs),
          Expanded(child: _buildLogBody()),
        ],
      ),
    );
  }

  void _toggleLevel(LogLevel level) {
    setState(() {
      if (_visibleLevels.contains(level)) {
        _visibleLevels.remove(level);
      } else {
        _visibleLevels.add(level);
      }
    });
    _pushFilter();
  }

  Widget _buildLogBody() {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final entries = _store.filteredEntries;
        if (entries.isEmpty) {
          return Center(
            child: Text(
              S.of(context).logIsEmpty,
              style: TextStyle(
                fontSize: AppFonts.sm,
                color: AppTheme.fgDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Scrollbar(
          controller: _scrollController,
          child: SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: entries.length,
              itemBuilder: (context, i) => _LogRow(entry: entries[i]),
            ),
          ),
        );
      },
    );
  }
}

/// One styled row in the log list. Every entry — routine OR header
/// (`--- Log started ... ---`, `Platform: ...`, `Dart: ...`) — is
/// rendered through the SAME `Container + Text.rich` shape; only the
/// border decoration and the inline span sequence change per type.
/// Each row is exactly ONE `Selectable` (one `Text.rich`, no
/// `WidgetSpan`-driven satellites, no per-type wrapper widgets), so
/// drag-select inside the surrounding `SelectionArea` walks rows in
/// paint order without fragmenting.
///
/// Variants:
///   * Routine: 2 px left border in the level colour. Spans:
///     `[timestamp dim] [TAG] [message] [\n + continuation lines, dim]`.
///     Tag is inline text — no chip widget — keeping the row a
///     single `Selectable`.
///   * Header (anything `parseLogEntries` flagged `isHeader: true`):
///     no border, one dim mono span carrying the line verbatim. The
///     per-process `--- Log started <ts> | <platform> | <ver> ---`
///     marker rides this same path — the `---` framing is enough
///     visual signal; bespoke hairlines / segment splitting only
///     introduced non-uniform geometry that broke the SelectionArea
///     run.
///
/// Rows are physically contiguous (no vertical margins on the
/// `Container`, `height: 1.55` on the `TextStyle`) — the `Text.rich`
/// fills the row vertically, so drag-select doesn't drop on inter-row
/// gaps or in-row padding zones.
class _LogRow extends StatelessWidget {
  final LogEntry entry;

  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: AppFonts.sm,
      fontFamily: AppFonts.monoFamily,
      fontFamilyFallback: AppFonts.monoFallback,
      color: AppTheme.fg,
      height: 1.55,
    );

    final BoxBorder? border;
    final List<InlineSpan> spans;

    if (entry.isHeader) {
      // The `--- Log started ... ---` session-start row gets a green
      // left stripe so the run-boundary catches the eye while keeping
      // the same Container + Text.rich shape (one Selectable, no
      // bespoke widgets, drag-select stays uninterrupted). Other
      // header rows (`Platform: ...`, `Dart: ...` from rotated legacy
      // files) stay unstriped — they're not session boundaries.
      final isBanner = entry.message.startsWith('--- ');
      border = isBanner
          ? Border(left: BorderSide(color: AppTheme.green, width: 2))
          : null;
      spans = [TextSpan(text: '  ${entry.message}', style: _dim(baseStyle))];
    } else {
      final color = _levelColor(entry.level);
      border = Border(left: BorderSide(color: color, width: 2));
      spans = _routineSpans(entry, color, baseStyle);
    }

    return Container(
      decoration: border == null ? null : BoxDecoration(border: border),
      // No `Container.padding` on purpose — paddings sit OUTSIDE the
      // child `Text.rich` and are not part of any `Selectable`, so
      // clicks landing on them dropped the active selection. The
      // 2-space leading TextSpan in `spans` carries the visual indent
      // INSIDE the row's single Selectable, and `textWidthBasis:
      // parent` stretches that Selectable to the full row width so
      // the right-side empty area also belongs to it.
      child: Text.rich(
        TextSpan(children: spans),
        softWrap: true,
        textWidthBasis: TextWidthBasis.parent,
      ),
    );
  }

  /// Spans for a routine entry: timestamp + `[TAG]` + message + any
  /// continuation lines below. Tag is inline text, NOT a
  /// `WidgetSpan` — keeps the row a single `Selectable`.
  static List<InlineSpan> _routineSpans(
    LogEntry entry,
    Color levelColor,
    TextStyle base,
  ) {
    final dim = _dim(base);
    final tag = TextStyle(
      fontSize: base.fontSize,
      fontFamily: base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
      color: levelColor,
      fontWeight: FontWeight.w600,
      height: base.height,
    );
    return <InlineSpan>[
      // Leading 2-space indent — inside the row's Selectable so a
      // click on the leftmost column starts selection on this row
      // instead of dropping any existing selection.
      TextSpan(text: '  ', style: dim),
      if (entry.timestamp != null)
        TextSpan(text: '${entry.timestamp!} ', style: dim),
      TextSpan(text: '[${entry.tag ?? 'App'}] ', style: tag),
      TextSpan(text: entry.message, style: base),
      for (final cont in entry.continuations)
        TextSpan(text: '\n  $cont', style: dim),
    ];
  }

  static TextStyle _dim(TextStyle base) => base.copyWith(color: AppTheme.fgDim);

  static Color _levelColor(LogLevel? level) => switch (level) {
    LogLevel.error => AppTheme.red,
    LogLevel.warn => AppTheme.yellow,
    LogLevel.info => AppTheme.blue,
    null => AppTheme.fgDim,
  };
}

/// Filter toolbar mounted above the log list.
///
/// Three severity toggle chips + a monospace search input. Toggling a
/// chip / typing in the box pushes the new filter into the [LogStore]
/// which recomputes the filtered subset and notifies the [ListView].
class _LogFilterBar extends StatelessWidget {
  final Set<LogLevel> visibleLevels;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<LogLevel> onLevelToggle;
  final ValueChanged<String> onQueryChanged;

  const _LogFilterBar({
    required this.visibleLevels,
    required this.query,
    required this.searchController,
    required this.onLevelToggle,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LevelChip(
          level: LogLevel.info,
          label: 'I',
          color: AppTheme.blue,
          active: visibleLevels.contains(LogLevel.info),
          onTap: () => onLevelToggle(LogLevel.info),
        ),
        const SizedBox(width: AppSpacing.xs),
        _LevelChip(
          level: LogLevel.warn,
          label: 'W',
          color: AppTheme.yellow,
          active: visibleLevels.contains(LogLevel.warn),
          onTap: () => onLevelToggle(LogLevel.warn),
        ),
        const SizedBox(width: AppSpacing.xs),
        _LevelChip(
          level: LogLevel.error,
          label: 'E',
          color: AppTheme.red,
          active: visibleLevels.contains(LogLevel.error),
          onTap: () => onLevelToggle(LogLevel.error),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: searchController,
              onChanged: onQueryChanged,
              style: TextStyle(
                fontSize: AppFonts.sm,
                fontFamily: AppFonts.monoFamily,
                fontFamilyFallback: AppFonts.monoFallback,
                color: AppTheme.fg,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Filter…',
                hintStyle: TextStyle(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg.withValues(alpha: 0.4),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: AppTheme.fg.withValues(alpha: 0.5),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.blue, width: 1.2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  final LogLevel level;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _LevelChip({
    required this.level,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusSm,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: active ? color : AppTheme.fg.withValues(alpha: 0.2),
            width: 1,
          ),
          borderRadius: AppTheme.radiusSm,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFonts.sm,
            fontFamily: AppFonts.monoFamily,
            fontFamilyFallback: AppFonts.monoFallback,
            fontWeight: FontWeight.w700,
            color: active ? color : AppTheme.fg.withValues(alpha: 0.4),
            decoration: active ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

/// Level-threshold picker for the logging section.
///
/// Replaces the old enable/disable toggle — user picks a minimum
/// severity (or "Off"). The choice maps straight to
/// `config.behavior.logLevel`, which `ConfigNotifier` fans out to
/// `AppLogger.setThreshold`. No intermediate bool flag.
/// Options shown in the logging level picker. Ordered from noisiest
/// (Info) to silent (Off) so the menu matches Logcat / IDE log
/// viewers where verbose sits at the top.
const _logLevelOptions = <AppPopupSelectOption<LogLevel?>>[
  AppPopupSelectOption(value: LogLevel.info, label: 'Info'),
  AppPopupSelectOption(value: LogLevel.warn, label: 'Warn'),
  AppPopupSelectOption(value: LogLevel.error, label: 'Error'),
  AppPopupSelectOption(value: null, label: 'Off'),
];

class _LogLevelSelector extends StatelessWidget {
  final LogLevel? selected;
  final ValueChanged<LogLevel?> onChanged;

  const _LogLevelSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: 'Logging level',
      subtitle: _subtitleFor(selected),
      icon: Icons.article_outlined,
      child: AppPopupSelect<LogLevel?>(
        value: selected,
        options: _logLevelOptions,
        onChanged: onChanged,
        leadingIcon: Icons.article_outlined,
        menuMinWidth: 160,
      ),
    );
  }

  String _subtitleFor(LogLevel? level) => switch (level) {
    LogLevel.info => 'Routine entries + warnings + errors',
    LogLevel.warn => 'Degraded paths + errors only',
    LogLevel.error => 'Failures only',
    null => 'No routine logs written',
  };
}
