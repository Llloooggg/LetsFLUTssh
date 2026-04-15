part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Logging section — enable toggle, live log viewer, export/clear
// ═══════════════════════════════════════════════════════════════════

class _LoggingSection extends ConsumerWidget {
  const _LoggingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(configProvider.select((c) => c.enableLogging));
    final logPath = AppLogger.instance.logPath;

    return Column(
      children: [
        _Toggle(
          label: S.of(context).enableLogging,
          value: enabled,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) =>
                    c.copyWith(behavior: c.behavior.copyWith(enableLogging: v)),
              ),
        ),
        if (enabled && logPath != null) ...[
          const SizedBox(height: 8),
          _LiveLogViewer(
            onExport: () => _exportLog(context),
            onClear: () => _clearLogs(context),
          ),
        ],
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

/// Inline live log viewer — polls the log file every second and displays the
/// content in a dark terminal-style panel with Copy and Clear action buttons.
class _LiveLogViewer extends StatefulWidget {
  final VoidCallback onExport;
  final VoidCallback onClear;

  const _LiveLogViewer({required this.onExport, required this.onClear});

  @override
  State<_LiveLogViewer> createState() => _LiveLogViewerState();
}

class _LiveLogViewerState extends State<_LiveLogViewer> {
  final _scrollController = ScrollController();
  String _content = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: fg),
            const SizedBox(width: 6),
            Text(
              S.of(context).liveLog,
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
              size: 16,
            ),
            AppIconButton(
              icon: Icons.save_alt,
              onTap: widget.onExport,
              tooltip: S.of(context).exportLog,
              size: 16,
            ),
            AppIconButton(
              icon: Icons.delete_outline,
              onTap: () async {
                widget.onClear();
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await _refresh();
              },
              tooltip: S.of(context).clearLogs,
              size: 16,
            ),
          ],
        ),
        // Log content — fill remaining vertical space
        LayoutBuilder(
          builder: (context, constraints) {
            // Use available height minus toolbar (~40px), clamped to reasonable min
            final availableHeight = MediaQuery.of(context).size.height - 200;
            return Container(
              width: double.infinity,
              height: availableHeight.clamp(200.0, double.infinity),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppTheme.radiusLg,
              ),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  _content.isEmpty ? '(no log entries yet)' : _content,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    fontFamily: 'monospace',
                    color: fg,
                    height: 1.4,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
