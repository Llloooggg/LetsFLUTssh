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

/// Inline live log viewer. Renders an ANSI-formatted log stream through the
/// Rust terminal engine ([ReplayTerminalController] + grid view): each entry
/// is formatted with a level-tinted vertical stripe + bold tag chip, the
/// engine owns scrollback, and the grid view paints it. Data flows through the
/// app-level [LogStore] singleton which is seeded at boot and updated live by
/// `AppLogger.liveEntries`, so opening the tab is instant.
///
/// The replay engine (over a plain monospace list) is chosen because log
/// lines carry ANSI SGR color — per-level stripes + tinted tags — so a plain
/// `SelectableText` would render escape sequences as literal text.
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
  late final LogStore _store;

  /// Backing Rust terminal engine. Holds the ANSI-formatted stream that
  /// renders into [TerminalView]. Scrollback sized for the
  /// LogStore's entry cap × ~2 visual lines per entry (with continuations).
  late final ReplayTerminalController _controller;

  /// Wrap width (columns) the entries were last formatted against. The grid
  /// view reports the laid-out cell count back through the controller's
  /// resize; when it changes, the wrap points are stale and the next sync
  /// forces a full rewrite (see [_syncTerminal]).
  int _lastFormatCols = 0;

  /// Last batch of filteredEntries fed into the engine. Used by
  /// [_syncTerminal] to choose between appending a tail-only diff
  /// vs. tearing down and re-streaming the whole filtered set.
  List<LogEntry>? _lastWrittenSnapshot;

  /// Subscription to [LogStore.changes] — re-syncs the terminal on
  /// every buffer mutation. Cancelled in [dispose].
  StreamSubscription<void>? _changesSub;

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
    // The grid view reports the laid-out cell count back through
    // `reportResize`, so the engine's `cols` tracks the actual viewport
    // width and `_syncTerminal` wraps entries to fit. A width change forces
    // one full rewrite (the wrap points moved); steady-state appends do not.
    _controller = ReplayTerminalController(cols: 80, rows: 200);
    _lastFormatCols = _controller.cols;
    _controller.addListener(_onControllerChanged);
    _changesSub = _store.changes.listen((_) => _syncTerminal());
    _syncTerminal();
    // Idempotent — `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners`
    // already kicked the seed at boot. This just reads the
    // already-primed singleton; if the seed is still running the
    // live stream will populate the store as entries arrive.
    unawaited(_store.ensureSeeded());
  }

  @override
  void dispose() {
    unawaited(_changesSub?.cancel());
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// React to the controller resizing (the grid view reported a new cell
  /// count): if the wrap width changed, re-sync so entries re-wrap to the new
  /// column count. The controller also notifies on feed, but `_syncTerminal`
  /// is what feeds, so a re-sync there is driven by [LogStore.changes], not
  /// this listener — this only catches the resize-width branch.
  void _onControllerChanged() {
    if (_controller.cols != _lastFormatCols) _syncTerminal();
  }

  void _pushFilter() {
    _store.applyFilter(visibleLevels: _visibleLevels, query: _query);
  }

  /// Reconcile the engine with [`LogStore.filteredEntries`]. Two
  /// shapes:
  ///   * **Append**: the new list is a strict extension of the
  ///     last snapshot (same references at every prior index, just
  ///     more entries at the tail). Stream only the new tail
  ///     through `terminal.write`; the cursor follows the writes so
  ///     the viewer scrolls to the bottom automatically.
  ///   * **Full rewrite**: filter changed, store was wiped, or the
  ///     LogStore's `_maxEntries` cap trimmed older entries. Wipe
  ///     the terminal and re-stream the entire filtered set.
  ///
  /// `identical` is the right comparison: [LogStore] hands out the
  /// same `LogEntry` instance every time, only replacing the outer
  /// `List` on change. The append-vs-rewrite check is therefore a
  /// cheap reference walk, not a structural compare.
  void _syncTerminal() {
    // Latch the wrap width up front so the controller's per-feed notify
    // (which fires `_onControllerChanged`) sees an already-current
    // `_lastFormatCols` and does not re-enter this sync.
    final cols = _controller.cols;
    final colsChanged = cols != _lastFormatCols;
    _lastFormatCols = cols;

    final current = _store.filteredEntries;
    final lastSnap = _lastWrittenSnapshot;
    final buf = StringBuffer();
    if (colsChanged ||
        lastSnap == null ||
        current.length < lastSnap.length ||
        !_startsWith(current, lastSnap)) {
      // CSI H = home cursor; CSI 2J = erase visible viewport;
      // CSI 3J = erase scrollback. The 2J alone wipes only the
      // visible area — scrollback is preserved unless 3J asks
      // otherwise. Without 3J the previously-written banner +
      // entries linger above the freshly-rewritten ones (visible
      // on scroll-up as a duplicate session) every time a resize
      // or filter change forces a full rewrite.
      buf.write('\x1B[H\x1B[2J\x1B[3J');
      for (final entry in current) {
        buf.write(_formatEntry(entry));
      }
    } else if (current.length > lastSnap.length) {
      for (var i = lastSnap.length; i < current.length; i++) {
        buf.write(_formatEntry(current[i]));
      }
    }
    if (buf.isNotEmpty) _controller.feed(utf8.encode(buf.toString()));
    _lastWrittenSnapshot = current;
  }

  bool _startsWith(List<LogEntry> longer, List<LogEntry> shorter) {
    if (longer.length < shorter.length) return false;
    for (var i = 0; i < shorter.length; i++) {
      if (!identical(longer[i], shorter[i])) return false;
    }
    return true;
  }

  /// ANSI-format a single [LogEntry] for the terminal stream.
  ///
  /// Routine entries: `▎ HH:MM:SS [TAG] message` where:
  ///   * `▎` (U+258E LEFT ONE QUARTER BLOCK) is a per-level
  ///     vertical stripe (info/warn/error → blue / yellow / red).
  ///     A terminal grid has no per-cell border, so a coloured glyph
  ///     in column 0 is the closest visual analog to a left accent bar.
  ///   * The tag is bold-tinted in the level colour. No padding —
  ///     padding to a fixed column read as a "weird gap" after
  ///     `]` since short tags left big trailing whitespace.
  ///   * Long lines are **manually wrapped** to the engine's
  ///     current column count (`_controller.cols`), with the stripe
  ///     re-emitted on every visual row so the level marker stays
  ///     continuous on wraps. The terminal's built-in wrap drops to
  ///     column 0 on each wrap → the stripe would disappear from the
  ///     tail of a wrapped entry. A column-count change forces a full
  ///     rewrite in [_syncTerminal] so wrap points stay in sync.
  ///   * Continuation lines repeat the stripe (and the message-
  ///     start indent) so the row remains visually contiguous,
  ///     and dim the body.
  ///
  /// Session-banner headers (`--- Log started ...`) get a hairline
  /// divider above (`────────` across the viewport) so multi-
  /// session logs stay scannable at a glance. The `--- ` / ` ---`
  /// framing the parser emits is stripped from the visible text —
  /// the divider already signals "new session" loudly enough.
  /// Other headers (`Platform: ...`, `Dart: ...`) just render as
  /// dim text with no decoration.
  ///
  /// `\r\n` line breaks throughout so the terminal state machine
  /// treats each line as its own row — a bare `\n` would scroll
  /// without carriage return and the next entry would start at the
  /// previous column.
  String _formatEntry(LogEntry entry) {
    if (entry.isHeader) {
      if (entry.message.startsWith('--- ')) {
        final dividerWidth = _controller.cols.clamp(20, 200);
        final divider = '\x1B[2m${'─' * dividerWidth}\x1B[0m';
        final cleaned = entry.message.replaceAll(
          RegExp(r'^---\s+|\s+---$'),
          '',
        );
        return '$divider\r\n\x1B[2m  $cleaned\x1B[0m\r\n';
      }
      return '\x1B[2m  ${entry.message}\x1B[0m\r\n';
    }
    final code = _levelAnsiCode(entry.level);
    final stripeAnsi = '\x1B[${code}m▎\x1B[0m ';
    const stripeColumns = 2; // `▎` + space
    final tsRaw = entry.timestamp != null ? '${entry.timestamp} ' : '';
    final tagRaw = '[${entry.tag ?? 'App'}] ';
    final headerColumns = tsRaw.length + tagRaw.length;
    final tsAnsi = entry.timestamp != null
        ? '\x1B[2m${entry.timestamp}\x1B[0m '
        : '';
    final tagAnsi = '\x1B[1;${code}m${tagRaw.trimRight()}\x1B[0m ';

    final viewWidth = _controller.cols;
    final availRest = (viewWidth - stripeColumns).clamp(8, viewWidth);
    final availFirst = (availRest - headerColumns).clamp(8, availRest);

    final buf = StringBuffer();

    // First visual row: stripe + timestamp + tag + first chunk of
    // message. Subsequent wrap rows: stripe + chunk only.
    final wrapped = _wrapText(entry.message, availFirst, availRest);
    buf.write('$stripeAnsi$tsAnsi$tagAnsi${wrapped.first}\r\n');
    for (var i = 1; i < wrapped.length; i++) {
      buf.write('$stripeAnsi${wrapped[i]}\r\n');
    }

    for (final cont in entry.continuations) {
      // Continuations carry no header — wrap against the same
      // available-rest width on all visual rows.
      final contWrapped = _wrapText(cont, availRest, availRest);
      for (final line in contWrapped) {
        buf.write('$stripeAnsi\x1B[2m$line\x1B[0m\r\n');
      }
    }

    return buf.toString();
  }

  /// Word-wrap [text] so the FIRST visual chunk fits in [firstWidth]
  /// columns and SUBSEQUENT chunks fit in [restWidth]. Splits at the
  /// last whitespace within the width budget where possible; falls
  /// back to a hard split mid-word when no space fits. Returns the
  /// original string in a single-element list when it already fits
  /// in [firstWidth].
  ///
  /// Width inputs MUST exclude any ANSI escape sequences — the
  /// caller applies ANSI to each chunk after wrapping.
  List<String> _wrapText(String text, int firstWidth, int restWidth) {
    if (text.length <= firstWidth) return [text];
    final chunks = <String>[];
    var remaining = text;
    var budget = firstWidth;
    while (remaining.length > budget) {
      var splitAt = remaining.lastIndexOf(' ', budget);
      if (splitAt <= 0) splitAt = budget; // hard split — no whitespace fits
      chunks.add(remaining.substring(0, splitAt).trimRight());
      remaining = remaining.substring(splitAt).trimLeft();
      budget = restWidth;
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  /// ANSI SGR colour parameter for a level's tint. Matches the
  /// per-row tint the previous `_LogRow` renderer used (info →
  /// `AppTheme.blue`, warn → `AppTheme.yellow`, error → `AppTheme.red`).
  /// Headers fall through to `0` (default fg, dimmed by the caller).
  String _levelAnsiCode(LogLevel? level) => switch (level) {
    LogLevel.info => '34',
    LogLevel.warn => '33',
    LogLevel.error => '31',
    _ => '0',
  };

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
    final titleText = widget.active
        ? S.of(context).liveLog
        : S.of(context).archivedLog;
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
  /// Falls back to a "log is empty" toast when nothing has been logged yet.
  /// This is the only copy path — the read-only grid view does not support
  /// in-viewer text selection.
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
    final entries = ref.watch(logStoreProvider);
    if (entries.allEntries.isEmpty) {
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
    // `ClipRect` so the last partial row (when the container's pixel
    // height isn't an integer multiple of the row height) is clipped at
    // the bottom border instead of bleeding past it.
    return ClipRect(
      child: TerminalView(
        controller: _controller,
        config: const TerminalViewConfig.readOnly(),
        fontSize: AppFonts.sm,
        reportResize: true,
      ),
    );
  }
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
                hintText: S.of(context).filter,
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
    return HoverRegion(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      builder: (_) => Container(
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
    final l10n = S.of(context);
    return _SettingsRow(
      label: l10n.loggingLevel,
      subtitle: _subtitleFor(l10n, selected),
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

  // Log-level *labels* (Info / Warn / Error / Off) stay English by
  // design — they are protocol-level terms every dev tool (Logcat,
  // IDE consoles, Slack admin) ships untranslated. AGENTS.md's
  // `Watchlist` keeps log-related terms in their native IT form.
  // The *subtitles* describing what each level prints ARE prose, so
  // those route through ARB.
  String _subtitleFor(S l10n, LogLevel? level) => switch (level) {
    LogLevel.info => l10n.loggingLevelSubtitleInfo,
    LogLevel.warn => l10n.loggingLevelSubtitleWarn,
    LogLevel.error => l10n.loggingLevelSubtitleError,
    null => l10n.loggingLevelSubtitleOff,
  };
}
