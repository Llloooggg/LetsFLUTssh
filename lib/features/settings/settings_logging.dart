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

/// Inline live log viewer — `xterm.dart`-backed TerminalView mounted
/// against the app-level `LogTerminal` singleton. Open is instant
/// (the Terminal is primed at boot from the on-disk log file and
/// fed live by `AppLogger.liveEntries`); selection / copy /
/// scroll-back follow standard terminal UX. The viewer keeps the
/// level chips + search box; toggling either calls
/// `LogTerminal.applyFilter` which re-feeds the Terminal with the
/// filtered subset. Selection is dropped on filter change —
/// expected when the displayed corpus changes.
class _LiveLogViewer extends ConsumerStatefulWidget {
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
  ConsumerState<_LiveLogViewer> createState() => _LiveLogViewerState();
}

class _LiveLogViewerState extends ConsumerState<_LiveLogViewer> {
  final _searchController = TextEditingController();
  late final TerminalController _terminalController;

  /// Which severity levels render in the viewer. All three start on;
  /// users can hide info noise to focus on warnings + errors during a
  /// support session. Mutating either of these state slots calls
  /// [_pushFilter] which re-feeds the Terminal.
  final Set<LogLevel> _visibleLevels = {...LogLevel.values};

  /// Case-insensitive substring filter on the message body. Applied
  /// after the level filter (AND) so a `search: "keychain" + level: W`
  /// shows only warn rows whose message mentions keychain.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _terminalController = TerminalController();
    // Idempotent — `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners`
    // already kicked the seed at boot; this call just reads the
    // already-primed singleton. No await — if the seed is still
    // running the live stream will populate the Terminal as
    // entries arrive.
    unawaited(ref.read(logTerminalProvider).ensureSeeded());
  }

  @override
  void dispose() {
    _terminalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Push the current filter state into the LogTerminal so the
  /// Terminal scrollback shows the filtered subset of entries.
  /// Called from the level chip toggle and the search-query
  /// `onChanged`.
  void _pushFilter() {
    ref
        .read(logTerminalProvider)
        .applyFilter(visibleLevels: _visibleLevels, query: _query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = AppTheme.green;
    final mobile = plat.isMobilePlatform;
    final buttonBg = mobile ? AppTheme.bg3 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(context, theme, fg, mobile, buttonBg),
        // Box height = viewport - 280 px chrome budget, floored at 200,
        // so the viewer fills the dialog on tall windows but still leaves
        // a usable strip on short ones.
        LayoutBuilder(
          builder: (context, _) {
            final viewportHeight = MediaQuery.of(context).size.height;
            final maxHeight = (viewportHeight - 280).clamp(
              200.0,
              double.infinity,
            );
            return _buildLogBox(maxHeight, fg);
          },
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    ThemeData theme,
    Color fg,
    bool mobile,
    Color? buttonBg,
  ) {
    final indicatorColor = widget.active
        ? fg
        : theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final titleText = widget.active ? S.of(context).liveLog : 'Archived log';
    return Row(
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
          onTap: () => _copyLogToClipboard(context),
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
          onTap: _clearAndRefresh,
          tooltip: S.of(context).clearLogs,
          backgroundColor: buttonBg,
          borderRadius: AppTheme.radiusSm,
        ),
      ],
    );
  }

  /// Copy semantics:
  /// - If the user has a Terminal selection active, copy that
  ///   (via `terminalController.selection` → buffer text).
  /// - Otherwise serialize every entry currently in the
  ///   `LogTerminal._allEntries` list (filter-independent — a
  ///   `Copy log` button means "all", not "what is shown after my
  ///   level filter"). Falls back to a "log is empty" toast when
  ///   nothing has been logged yet.
  void _copyLogToClipboard(BuildContext context) {
    final logTerminal = ref.read(logTerminalProvider);
    final selection = _terminalController.selection;
    String text;
    if (selection != null) {
      text = logTerminal.terminal.buffer.getText(selection);
    } else {
      final entries = logTerminal.allEntries;
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
      text = buf.toString();
    }
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
    // The on-disk wipe is async (file delete); the in-memory
    // Terminal mirror is wiped synchronously here so the viewer
    // empties even if the file delete is still pending.
    ref.read(logTerminalProvider).clearAll();
  }

  Widget _buildLogBox(double maxHeight, Color fg) {
    return Container(
      width: double.infinity,
      height: maxHeight,
      decoration: BoxDecoration(
        color: AppTheme.bg0,
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
            onLevelToggle: _toggleLevel,
            onQueryChanged: (q) {
              setState(() => _query = q);
              _pushFilter();
            },
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildLogBody(fg)),
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

  Widget _buildLogBody(Color fg) {
    final terminal = ref.watch(logTerminalProvider).terminal;
    return TerminalView(
      terminal,
      controller: _terminalController,
      // Read-only viewer — never accept keyboard input as terminal
      // input. `hardwareKeyboardOnly: false` keeps standard text-
      // selection shortcuts (Ctrl+C / Ctrl+A) reaching us through
      // the surrounding shortcut layer. The selection itself is
      // managed by `_terminalController`; copy lives in the
      // toolbar.
      autofocus: false,
      hardwareKeyboardOnly: false,
      backgroundOpacity: 1.0,
      padding: const EdgeInsets.all(4),
      theme: AppTheme.terminalTheme,
      textStyle: TerminalStyle(
        fontSize: AppFonts.sm,
        fontFamily: AppFonts.monoFamily,
        fontFamilyFallback: AppFonts.monoFallback,
      ),
    );
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

/// Level-threshold picker for the logging section.
///
/// Replaces the old enable/disable toggle — user picks a minimum
/// severity (or "Off"). The choice maps straight to
/// `config.behavior.logLevel`, which `ConfigNotifier` fans out to
/// `AppLogger.setThreshold`. No intermediate bool flag.
/// Options shown in the logging level picker. Ordered from noisiest
/// (Debug) to silent (Off) so the menu matches Logcat / IDE log
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
