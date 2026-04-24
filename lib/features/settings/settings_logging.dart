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

      await File(outputPath).writeAsString(content);
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

/// Wrapper that resolves whether there's anything worth showing: if logging
/// is disabled and the log file is empty, render nothing so the settings
/// screen stays compact; otherwise mount the live viewer.
///
/// Probe is a sync `File.lengthSync()` check on the log path. Async
/// `readLog()` would deadlock against the inner viewer's 1s polling timer
/// in widget tests that pump discrete frames.
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
    final path = AppLogger.instance.logPath;
    if (path == null) return false;
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
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

/// Inline live log viewer — polls the log file every second and displays the
/// content in a dark terminal-style panel with Copy and Clear action buttons.
///
/// Polling is lifecycle-aware: the timer is paused when the app goes to the
/// background (paused/inactive/hidden/detached) so it doesn't keep the CPU
/// awake and drain battery when the user isn't looking. It resumes on
/// AppLifecycleState.resumed.
class _LiveLogViewer extends StatefulWidget {
  final VoidCallback onExport;
  final VoidCallback onClear;

  /// Whether the user currently has a logging threshold set — drives
  /// the viewer's toolbar label + indicator colour. When `false` the
  /// viewer still renders (so archived entries stay reachable) but
  /// reads as "Archived log" / dim dot rather than "Live Log" / green
  /// dot, to avoid suggesting writes are still happening.
  final bool active;

  const _LiveLogViewer({
    required this.onExport,
    required this.onClear,
    required this.active,
  });

  @override
  State<_LiveLogViewer> createState() => _LiveLogViewerState();
}

class _LiveLogViewerState extends State<_LiveLogViewer>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _content = '';
  Timer? _timer;

  /// Which severity levels render in the viewer. All three start on;
  /// users can hide info noise to focus on warnings + errors during a
  /// support session.
  final Set<LogLevel> _visibleLevels = {
    LogLevel.info,
    LogLevel.warn,
    LogLevel.error,
  };

  /// Case-insensitive substring filter on the message body. Applied
  /// after the level filter (AND) so a `search: "keychain" + level: W`
  /// shows only warn rows whose message mentions keychain.
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_timer == null) {
        _refresh();
        _startTimer();
      }
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    final text = await AppLogger.instance.readLog();
    if (!mounted) return;
    final changed = text != _content;
    setState(() => _content = text);
    if (changed && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = AppTheme.bg0;
    final fg = AppTheme.green;
    // Mirror the session-panel header: on mobile we give each AppIconButton
    // a filled background + rounded corners so the three log actions read
    // as buttons (they were 16 px transparent icons before — too small for
    // a thumb and easy to miss).
    final mobile = plat.isMobilePlatform;
    final buttonBg = mobile ? AppTheme.bg3 : null;

    // Toolbar title + status dot reflect whether writes are currently
    // happening. When the user set logging level to Off we still show
    // the viewer (archived entries stay reachable), but the "Live"
    // wording + green dot would misrepresent state — swap in a dim
    // "Archived log" + grey dot.
    final indicatorColor = widget.active
        ? fg
        : theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final titleText = widget.active ? S.of(context).liveLog : 'Archived log';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: indicatorColor),
            const SizedBox(width: 6),
            Text(
              titleText,
              style: TextStyle(
                fontSize: AppFonts.md,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            AppIconButton(
              icon: Icons.copy,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _content));
                Toast.show(
                  context,
                  message: _content.isEmpty
                      ? S.of(context).logIsEmpty
                      : S.of(context).copiedToClipboard,
                  level: ToastLevel.info,
                );
              },
              tooltip: S.of(context).copyLog,
              backgroundColor: buttonBg,
              borderRadius: AppTheme.radiusSm,
            ),
            if (mobile) const SizedBox(width: 8),
            AppIconButton(
              icon: Icons.save_alt,
              onTap: widget.onExport,
              tooltip: S.of(context).exportLog,
              backgroundColor: buttonBg,
              borderRadius: AppTheme.radiusSm,
            ),
            if (mobile) const SizedBox(width: 8),
            AppIconButton(
              icon: Icons.delete_outline,
              onTap: () async {
                widget.onClear();
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await _refresh();
              },
              tooltip: S.of(context).clearLogs,
              backgroundColor: buttonBg,
              borderRadius: AppTheme.radiusSm,
            ),
          ],
        ),
        // Log content — grow into the rest of the viewport. Previously
        // the box was capped at 360 px, leaving a large blank gap under
        // it on tall windows / phones in portrait. Subtracting a
        // generous chrome budget (~280 px for dialog header, section
        // header, toolbar, dialog inset on desktop; for mobile the
        // AppBar + ExpansionTile ancestor is similar) lets the viewer
        // reach the bottom of the viewport without pushing its own
        // toolbar off-screen on small devices. Floor stays at 200 px
        // so a very short window still shows a usable strip.
        LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = MediaQuery.of(context).size.height;
            final maxHeight = (viewportHeight - 280).clamp(
              200.0,
              double.infinity,
            );
            return Container(
              width: double.infinity,
              height: maxHeight,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppTheme.radiusLg,
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LogFilterBar(
                    visibleLevels: _visibleLevels,
                    query: _query,
                    searchController: _searchController,
                    onLevelToggle: (level) => setState(() {
                      if (_visibleLevels.contains(level)) {
                        _visibleLevels.remove(level);
                      } else {
                        _visibleLevels.add(level);
                      }
                    }),
                    onQueryChanged: (q) => setState(() => _query = q),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _content.isEmpty
                        ? Center(
                            child: Text(
                              '(no log entries yet)',
                              style: TextStyle(
                                fontSize: AppFonts.sm,
                                fontFamily: 'monospace',
                                color: fg.withValues(alpha: 0.5),
                              ),
                            ),
                          )
                        : _LogList(
                            entries: _filterEntries(parseLogEntries(_content)),
                            controller: _scrollController,
                            defaultFg: fg,
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Apply the level + search filters to a parsed entry list. Headers
  /// always render so the session banner stays visible even when
  /// every level filter is off. Search matches against the message,
  /// tag, or any continuation line so a query like "keychain" hits
  /// the stack-trace body too.
  List<LogEntry> _filterEntries(List<LogEntry> raw) {
    final lower = _query.toLowerCase();
    return raw
        .where((e) {
          if (e.isHeader) return true;
          if (e.level != null && !_visibleLevels.contains(e.level)) {
            return false;
          }
          if (lower.isEmpty) return true;
          if (e.message.toLowerCase().contains(lower)) return true;
          if (e.tag != null && e.tag!.toLowerCase().contains(lower)) {
            return true;
          }
          for (final c in e.continuations) {
            if (c.toLowerCase().contains(lower)) return true;
          }
          return false;
        })
        .toList(growable: false);
  }
}

/// Filter toolbar mounted above the log list.
///
/// Four severity toggle chips + a monospace search input. All chips
/// default to on except `D`, which users opt into explicitly when
/// chasing a trace.
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
          level: LogLevel.debug,
          label: 'D',
          color: AppTheme.fg.withValues(alpha: 0.5),
          active: visibleLevels.contains(LogLevel.debug),
          onTap: () => onLevelToggle(LogLevel.debug),
        ),
        const SizedBox(width: 4),
        _LevelChip(
          level: LogLevel.info,
          label: 'I',
          color: AppTheme.blue,
          active: visibleLevels.contains(LogLevel.info),
          onTap: () => onLevelToggle(LogLevel.info),
        ),
        const SizedBox(width: 4),
        _LevelChip(
          level: LogLevel.warn,
          label: 'W',
          color: AppTheme.yellow,
          active: visibleLevels.contains(LogLevel.warn),
          onTap: () => onLevelToggle(LogLevel.warn),
        ),
        const SizedBox(width: 4),
        _LevelChip(
          level: LogLevel.error,
          label: 'E',
          color: AppTheme.red,
          active: visibleLevels.contains(LogLevel.error),
          onTap: () => onLevelToggle(LogLevel.error),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: searchController,
              onChanged: onQueryChanged,
              style: TextStyle(
                fontSize: AppFonts.sm,
                fontFamily: 'monospace',
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
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: AppTheme.fg.withValues(alpha: 0.15),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(
                    color: AppTheme.fg.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
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
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : null,
          border: Border.all(
            color: active ? color : AppTheme.fg.withValues(alpha: 0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFonts.sm,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            color: active ? color : AppTheme.fg.withValues(alpha: 0.4),
            decoration: active ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  final List<LogEntry> entries;
  final ScrollController controller;
  final Color defaultFg;

  const _LogList({
    required this.entries,
    required this.controller,
    required this.defaultFg,
  });

  @override
  Widget build(BuildContext context) {
    // SelectionArea lets users drag-select across rows — individual
    // Text widgets stay non-selectable on their own but the area
    // wrapper stitches the selection together. Copy captures plain
    // text, not TextSpan styles, so users pasting into a bug report
    // get clean output.
    return SelectionArea(
      child: ListView.builder(
        controller: controller,
        itemCount: entries.length,
        itemBuilder: (ctx, i) =>
            _LogRow(entry: entries[i], defaultFg: defaultFg),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final Color defaultFg;

  const _LogRow({required this.entry, required this.defaultFg});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: AppFonts.sm,
      fontFamily: 'monospace',
      height: 1.4,
      color: defaultFg,
    );
    if (entry.isHeader) {
      // A session banner — the "--- Log started ..." line + the
      // following `Platform:` / `Dart:` lines — gets a top divider
      // and extra vertical padding so it visually breaks the stream.
      // Other unparseable lines fall back to a compact dim row.
      final isSessionStart = entry.message.startsWith('--- Log started');
      return Container(
        margin: EdgeInsets.only(top: isSessionStart ? 12 : 0, bottom: 0),
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isSessionStart ? 6 : 2,
        ),
        decoration: isSessionStart
            ? BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: defaultFg.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
              )
            : null,
        child: Text(
          entry.message,
          style: style.copyWith(
            color: defaultFg.withValues(alpha: 0.55),
            fontStyle: FontStyle.italic,
            fontWeight: isSessionStart ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
    }

    final level = entry.level ?? LogLevel.info;
    final levelColor = switch (level) {
      LogLevel.error => AppTheme.red,
      LogLevel.warn => AppTheme.yellow,
      LogLevel.info => AppTheme.blue,
      // Debug uses the default fg dimmed — verbose trace rows should
      // visually recede so they do not compete with the higher-
      // severity rows above/below them.
      LogLevel.debug => defaultFg.withValues(alpha: 0.55),
    };
    final hasTint = level == LogLevel.error || level == LogLevel.warn;
    final tintBg = hasTint ? levelColor.withValues(alpha: 0.08) : null;

    // Segmented TextSpans so the viewer can dim the timestamp + accent
    // the tag without losing the monospace alignment. Continuations
    // attach inline after the primary message with a newline so the
    // error / stack trace sits under the tinted row.
    final spans = <InlineSpan>[
      TextSpan(
        text: '${entry.timestamp} ',
        style: style.copyWith(color: defaultFg.withValues(alpha: 0.55)),
      ),
      TextSpan(
        text: '[${entry.tag}] ',
        style: style.copyWith(color: levelColor, fontWeight: FontWeight.w600),
      ),
      TextSpan(text: entry.message, style: style),
      for (final c in entry.continuations)
        TextSpan(
          text: '\n$c',
          style: style.copyWith(color: defaultFg.withValues(alpha: 0.75)),
        ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: tintBg,
        border: Border(
          left: BorderSide(
            color: hasTint ? levelColor : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}

/// Level-threshold picker for the logging section.
///
/// Replaces the old enable/disable toggle — user picks a minimum
/// severity (or "Off"). The choice maps straight to
/// `config.behavior.logLevel`, which `ConfigNotifier` fans out to
/// `AppLogger.setThreshold`. No intermediate bool flag.
class _LogLevelSelector extends StatelessWidget {
  final LogLevel? selected;
  final ValueChanged<LogLevel?> onChanged;

  const _LogLevelSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Options ordered from noisiest to silent — familiar "more
    // verbose = higher in the menu" layout from Logcat / IDE log
    // viewers.
    const options = <({LogLevel? level, String label, String subtitle})>[
      (
        level: LogLevel.debug,
        label: 'Debug',
        subtitle: 'Everything including verbose trace',
      ),
      (
        level: LogLevel.info,
        label: 'Info',
        subtitle: 'Routine operational entries + warnings + errors',
      ),
      (
        level: LogLevel.warn,
        label: 'Warn',
        subtitle: 'Degraded paths + errors only',
      ),
      (level: LogLevel.error, label: 'Error', subtitle: 'Failures only'),
      (level: null, label: 'Off', subtitle: 'No routine logs written'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(
            Icons.article_outlined,
            size: 16,
            color: AppTheme.fg.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logging level',
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    color: AppTheme.fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  options.firstWhere((o) => o.level == selected).subtitle,
                  style: TextStyle(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fg.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<LogLevel?>(
              value: selected,
              isDense: true,
              onChanged: onChanged,
              items: [
                for (final opt in options)
                  DropdownMenuItem<LogLevel?>(
                    value: opt.level,
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: AppFonts.sm,
                        color: AppTheme.fg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
