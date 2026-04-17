import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/transfer_task.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/transfer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart'
    show formatDuration, formatSize, formatTimestamp, localizeError;
import '../../utils/platform.dart' as plat;
import '../../widgets/app_icon_button.dart';
import '../../widgets/clipped_row.dart';
import '../../widgets/column_resize_handle.dart';
import '../../widgets/sortable_header_cell.dart';
import 'transfer_panel_controller.dart';

/// Collapsible bottom panel showing transfer progress and history.
class TransferPanel extends ConsumerStatefulWidget {
  const TransferPanel({super.key});

  @override
  ConsumerState<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<TransferPanel> {
  late final TransferPanelController _ctrl;

  // Linked horizontal scroll controllers for header + body sync — stay
  // in the widget because ScrollController lifecycle is a Flutter
  // concern, not business state.
  final _headerScrollCtrl = ScrollController();
  final _bodyScrollCtrl = ScrollController();

  static bool get _mobile => plat.isMobilePlatform;

  @override
  void initState() {
    super.initState();
    _ctrl = TransferPanelController();
    _headerScrollCtrl.addListener(_syncHeaderToBody);
    _bodyScrollCtrl.addListener(_syncBodyToHeader);
  }

  bool _syncing = false;

  void _syncHeaderToBody() {
    if (_syncing) return;
    _syncing = true;
    if (_bodyScrollCtrl.hasClients) {
      _bodyScrollCtrl.jumpTo(_headerScrollCtrl.offset);
    }
    _syncing = false;
  }

  void _syncBodyToHeader() {
    if (_syncing) return;
    _syncing = true;
    if (_headerScrollCtrl.hasClients) {
      _headerScrollCtrl.jumpTo(_bodyScrollCtrl.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _headerScrollCtrl.removeListener(_syncHeaderToBody);
    _bodyScrollCtrl.removeListener(_syncBodyToHeader);
    _headerScrollCtrl.dispose();
    _bodyScrollCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(transferManagerProvider);
    final historyAsync = ref.watch(transferHistoryProvider);
    final statusAsync = ref.watch(transferStatusProvider);

    // Auto-expand edge is owned by the controller; calling this on
    // every build is safe because it's idempotent on same-value writes.
    final status = statusAsync.value;
    _ctrl.syncAutoExpand(status?.hasActive ?? false);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Container(
        color: AppTheme.bg1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle header with overlaid drag handle
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: _ctrl.toggleExpanded,
                  child: Container(
                    height: AppTheme.barHeightSm,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: AppTheme.bg0,
                    child: ClippedRow(
                      children: [
                        Icon(
                          _ctrl.expanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 11,
                          color: AppTheme.fgDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          S.of(context).transfersLabel,
                          style: AppFonts.inter(
                            fontSize: AppFonts.xs,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.fgDim,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (status != null) ...[
                          Text(
                            S.of(context).transferCountActive(status.running),
                            style: AppFonts.inter(
                              fontSize: AppFonts.xs,
                              color: AppTheme.accent,
                            ),
                          ),
                          Text(
                            S.of(context).transferCountQueued(status.queued),
                            style: AppFonts.inter(
                              fontSize: AppFonts.xs,
                              color: AppTheme.fgDim,
                            ),
                          ),
                        ],
                        const Spacer(),
                        historyAsync.when(
                          data: (history) => Text(
                            S
                                .of(context)
                                .transferCountInHistory(history.length),
                            style: AppFonts.inter(
                              fontSize: AppFonts.xxs,
                              color: AppTheme.fgFaint,
                            ),
                          ),
                          loading: SizedBox.shrink,
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 4),
                        if (_ctrl.expanded && _mobile)
                          _headerButton(
                            icon: Icons.sort,
                            tooltip: S.of(context).sort,
                            onTap: () => _showMobileSortMenu(context),
                          ),
                        if (_ctrl.expanded)
                          _headerButton(
                            icon: Icons.delete_outline,
                            tooltip: S.of(context).clearHistory,
                            onTap: () => manager.clearHistory(),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_ctrl.expanded)
                  Positioned(
                    top: -3,
                    left: 0,
                    right: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeRow,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) =>
                            _ctrl.resizePanelHeightBy(d.delta.dy),
                        child: const SizedBox(height: 6),
                      ),
                    ),
                  ),
              ],
            ),
            // Column headers + transfer list
            if (_ctrl.expanded) ...[
              _mobile ? _buildScrollableHeader() : _buildColumnHeaders(),
              Flexible(
                child: SizedBox(
                  height: _ctrl.panelHeight,
                  child: _mobile
                      ? _buildScrollableBody(historyAsync, ref)
                      : _buildTransferList(historyAsync, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return AppIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      dense: true,
      color: AppTheme.fgFaint,
    );
  }

  Widget _buildTransferList(
    AsyncValue<List<HistoryEntry>> historyAsync,
    WidgetRef ref,
  ) {
    final activeAsync = ref.watch(activeTransfersProvider);
    final active = activeAsync.value ?? [];

    return historyAsync.when(
      data: (history) {
        if (active.isEmpty && history.isEmpty) {
          return Center(
            child: Text(
              S.of(context).noTransfersYet,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgFaint,
              ),
            ),
          );
        }
        final sorted = _ctrl.sorted(history);
        final totalCount = active.length + sorted.length;
        return ListView.builder(
          itemCount: totalCount,
          itemExtent: 24,
          itemBuilder: (context, index) {
            if (index < active.length) {
              return _ActiveRow(
                entry: active[index],
                localWidth: _ctrl.localColWidth,
                remoteWidth: _ctrl.remoteColWidth,
                sizeWidth: _ctrl.sizeColWidth,
                timeWidth: _ctrl.timeColWidth,
              );
            }
            return _HistoryRow(
              entry: sorted[index - active.length],
              localWidth: _ctrl.localColWidth,
              remoteWidth: _ctrl.remoteColWidth,
              sizeWidth: _ctrl.sizeColWidth,
              timeWidth: _ctrl.timeColWidth,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(S.of(context).errorPrefix(e.toString()))),
    );
  }

  /// Trailing icon for a sort-menu row: an arrow in the current sort
  /// direction when [col] is the active column, nothing otherwise.
  Widget? _sortDirectionIcon(TransferSortColumn col) {
    if (col != _ctrl.sortColumn) return null;
    return Icon(
      _ctrl.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
      size: 18,
    );
  }

  /// Bottom-sheet sort picker for mobile. The scrollable header layout
  /// pushes the time column off-screen by default, so reaching it via the
  /// header is fiddly on a phone — match the file-browser pattern and
  /// offer a one-tap menu instead. Selecting the active column toggles
  /// ascending ↔ descending, same as tapping the header on desktop.
  void _showMobileSortMenu(BuildContext context) {
    final l10n = S.of(context);
    final columns = <(TransferSortColumn, String, IconData)>[
      (TransferSortColumn.name, l10n.name, Icons.sort_by_alpha),
      (TransferSortColumn.local, l10n.local, Icons.folder_outlined),
      (TransferSortColumn.remote, l10n.remote, Icons.dns_outlined),
      (TransferSortColumn.size, l10n.size, Icons.storage),
      (TransferSortColumn.time, l10n.time, Icons.schedule),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.sort,
                style: TextStyle(
                  fontSize: AppFonts.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (col, label, icon) in columns)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: _sortDirectionIcon(col),
                selected: col == _ctrl.sortColumn,
                onTap: () {
                  Navigator.pop(ctx);
                  _ctrl.setSort(col);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _sortableCell(
    String label,
    TransferSortColumn column,
    TextStyle style, {
    double? width,
  }) {
    return SortableHeaderCell(
      label: label,
      isActive: _ctrl.sortColumn == column,
      sortAscending: _ctrl.sortAscending,
      onTap: () => _ctrl.setSort(column),
      style: style,
      width: width,
    );
  }

  // Total width for the scrollable row (mobile).
  // 12 padding + 16 (#) + 4 + 20 (status) + 4 + name + 4×columnDivider(10)
  // + local + remote + size + time + 12 padding
  double get _scrollableRowWidth =>
      12 +
      16 +
      4 +
      20 +
      4 +
      TransferPanelController.nameColWidth +
      10 +
      _ctrl.localColWidth +
      10 +
      _ctrl.remoteColWidth +
      10 +
      _ctrl.sizeColWidth +
      10 +
      _ctrl.timeColWidth +
      12;

  Widget _buildScrollableHeader() {
    final style = AppFonts.inter(
      fontSize: AppFonts.xxs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    return Container(
      height: AppTheme.barHeightSm,
      decoration: BoxDecoration(color: AppTheme.bg3),
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        controller: _headerScrollCtrl,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _scrollableRowWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(width: 16, child: Text('#', style: style)),
                const SizedBox(width: 4),
                SizedBox(width: 20, child: Text('', style: style)),
                const SizedBox(width: 4),
                _sortableCell(
                  S.of(context).name,
                  TransferSortColumn.name,
                  style,
                  width: TransferPanelController.nameColWidth,
                ),
                columnDivider(),
                _sortableCell(
                  S.of(context).local,
                  TransferSortColumn.local,
                  style,
                  width: _ctrl.localColWidth,
                ),
                columnDivider(),
                _sortableCell(
                  S.of(context).remote,
                  TransferSortColumn.remote,
                  style,
                  width: _ctrl.remoteColWidth,
                ),
                columnDivider(),
                _sortableCell(
                  S.of(context).size,
                  TransferSortColumn.size,
                  style,
                  width: _ctrl.sizeColWidth,
                ),
                columnDivider(),
                _sortableCell(
                  S.of(context).time,
                  TransferSortColumn.time,
                  style,
                  width: _ctrl.timeColWidth,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableBody(
    AsyncValue<List<HistoryEntry>> historyAsync,
    WidgetRef ref,
  ) {
    final activeAsync = ref.watch(activeTransfersProvider);
    final active = activeAsync.value ?? [];

    return historyAsync.when(
      data: (history) {
        if (active.isEmpty && history.isEmpty) {
          return Center(
            child: Text(
              S.of(context).noTransfersYet,
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                color: AppTheme.fgFaint,
              ),
            ),
          );
        }
        final sorted = _ctrl.sorted(history);
        final totalCount = active.length + sorted.length;
        return SingleChildScrollView(
          controller: _bodyScrollCtrl,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _scrollableRowWidth,
            child: ListView.builder(
              itemCount: totalCount,
              itemExtent: 24,
              itemBuilder: (context, index) {
                if (index < active.length) {
                  return _ActiveRow(
                    entry: active[index],
                    nameWidth: TransferPanelController.nameColWidth,
                    localWidth: _ctrl.localColWidth,
                    remoteWidth: _ctrl.remoteColWidth,
                    sizeWidth: _ctrl.sizeColWidth,
                    timeWidth: _ctrl.timeColWidth,
                  );
                }
                return _HistoryRow(
                  entry: sorted[index - active.length],
                  nameWidth: TransferPanelController.nameColWidth,
                  localWidth: _ctrl.localColWidth,
                  remoteWidth: _ctrl.remoteColWidth,
                  sizeWidth: _ctrl.sizeColWidth,
                  timeWidth: _ctrl.timeColWidth,
                );
              },
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(S.of(context).errorPrefix(e.toString()))),
    );
  }

  Widget _buildColumnHeaders() {
    final style = AppFonts.inter(
      fontSize: AppFonts.xxs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppTheme.bg3),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          SizedBox(width: 16, child: Text('#', style: style)),
          const SizedBox(width: 4),
          SizedBox(width: 20, child: Text('', style: style)),
          const SizedBox(width: 4),
          Expanded(
            child: _sortableCell(
              S.of(context).name,
              TransferSortColumn.name,
              style,
            ),
          ),
          ColumnResizeHandle(onDrag: _ctrl.resizeLocalColBy),
          _sortableCell(
            S.of(context).local,
            TransferSortColumn.local,
            style,
            width: _ctrl.localColWidth,
          ),
          ColumnResizeHandle(onDrag: _ctrl.resizeRemoteColBy),
          _sortableCell(
            S.of(context).remote,
            TransferSortColumn.remote,
            style,
            width: _ctrl.remoteColWidth,
          ),
          ColumnResizeHandle(onDrag: _ctrl.resizeSizeColBy),
          _sortableCell(
            S.of(context).size,
            TransferSortColumn.size,
            style,
            width: _ctrl.sizeColWidth,
          ),
          ColumnResizeHandle(onDrag: _ctrl.resizeTimeColBy),
          _sortableCell(
            S.of(context).time,
            TransferSortColumn.time,
            style,
            width: _ctrl.timeColWidth,
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  final double? nameWidth;
  final double localWidth;
  final double remoteWidth;
  final double sizeWidth;
  final double timeWidth;

  const _HistoryRow({
    required this.entry,
    this.nameWidth,
    required this.localWidth,
    required this.remoteWidth,
    required this.sizeWidth,
    required this.timeWidth,
  });

  Widget _nameCell(Widget child) {
    if (nameWidth != null) {
      return SizedBox(width: nameWidth, child: child);
    }
    return Expanded(child: child);
  }

  static String _errorLabel(BuildContext context, Object error) {
    return localizeError(S.of(context), error);
  }

  String _statusTooltip(BuildContext context, bool isFailed, HistoryEntry e) {
    if (!isFailed) return S.of(context).completed;
    if (e.error != null) return localizeError(S.of(context), e.error!);
    return S.of(context).failed;
  }

  @override
  Widget build(BuildContext context) {
    final isFailed = entry.status == TransferStatus.failed;
    final isUpload = entry.direction == TransferDirection.upload;

    return Container(
      height: AppTheme.itemHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClippedRow(
        children: [
          // Direction icon
          SizedBox(
            width: 16,
            child: Icon(
              isUpload ? Icons.arrow_upward : Icons.arrow_downward,
              size: 10,
              color: isUpload ? AppTheme.green : AppTheme.blue,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 20,
            child: Tooltip(
              message: _statusTooltip(context, isFailed, entry),
              child: Icon(
                isFailed ? Icons.error_outline : Icons.check_circle_outline,
                size: 10,
                color: isFailed ? AppTheme.red : AppTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Name (+ inline error for failed transfers)
          _nameCell(
            Row(
              children: [
                Flexible(
                  child: Text(
                    entry.name,
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: isFailed ? AppTheme.red : AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFailed && entry.error != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    flex: 0,
                    child: Text(
                      _errorLabel(context, entry.error!),
                      style: AppFonts.mono(
                        fontSize: AppFonts.tiny,
                        color: AppTheme.red.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Local path
          columnDivider(),
          SizedBox(
            width: localWidth,
            child: Tooltip(
              message: isUpload ? entry.sourcePath : entry.targetPath,
              child: Text(
                _shortenPath(isUpload ? entry.sourcePath : entry.targetPath),
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Remote path
          columnDivider(),
          SizedBox(
            width: remoteWidth,
            child: Tooltip(
              message: isUpload ? entry.targetPath : entry.sourcePath,
              child: Text(
                _shortenPath(isUpload ? entry.targetPath : entry.sourcePath),
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Size
          columnDivider(),
          SizedBox(
            width: sizeWidth,
            child: Text(
              entry.sizeBytes > 0 ? formatSize(entry.sizeBytes) : '',
              style: AppFonts.mono(
                fontSize: AppFonts.xs,
                color: AppTheme.fgFaint,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Time
          columnDivider(),
          SizedBox(
            width: timeWidth,
            child: Tooltip(
              message: _timeTooltip(entry, S.of(context)),
              child: Text(
                _timeDisplay(entry),
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _timeDisplay(HistoryEntry entry) {
    final ts = entry.endedAt ?? entry.startedAt ?? entry.createdAt;
    final dur = entry.duration;
    if (dur != null) {
      return '${formatTimestamp(ts)} (${formatDuration(dur)})';
    }
    return formatTimestamp(ts);
  }

  static String _timeTooltip(HistoryEntry entry, S loc) {
    final parts = <String>[];
    parts.add(loc.transferTooltipCreated(formatTimestamp(entry.createdAt)));
    if (entry.startedAt != null) {
      parts.add(loc.transferTooltipStarted(formatTimestamp(entry.startedAt!)));
    }
    if (entry.endedAt != null) {
      parts.add(loc.transferTooltipEnded(formatTimestamp(entry.endedAt!)));
    }
    if (entry.duration != null) {
      parts.add(loc.transferTooltipDuration(formatDuration(entry.duration!)));
    }
    return parts.join('\n');
  }

  /// Shorten a path to just the last 2 segments for display.
  static String _shortenPath(String path) {
    if (path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return normalized;
    return '.../${parts.sublist(parts.length - 2).join('/')}';
  }
}

/// Row for an active or queued transfer.
class _ActiveRow extends StatelessWidget {
  final ActiveEntry entry;
  final double? nameWidth;
  final double localWidth;
  final double remoteWidth;
  final double sizeWidth;
  final double timeWidth;

  const _ActiveRow({
    required this.entry,
    this.nameWidth,
    required this.localWidth,
    required this.remoteWidth,
    required this.sizeWidth,
    required this.timeWidth,
  });

  Widget _nameCell(Widget child) {
    if (nameWidth != null) {
      return SizedBox(width: nameWidth, child: child);
    }
    return Expanded(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final isUpload = entry.direction == TransferDirection.upload;
    final isQueued = entry.status == TransferStatus.queued;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: AppTheme.itemHeightXs,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClippedRow(
            children: [
              // Direction icon
              SizedBox(
                width: 16,
                child: Icon(
                  isUpload ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10,
                  color: isUpload ? AppTheme.green : AppTheme.blue,
                ),
              ),
              const SizedBox(width: 4),
              // Status icon
              SizedBox(
                width: 20,
                child: Icon(
                  isQueued ? Icons.schedule : Icons.sync,
                  size: 10,
                  color: isQueued ? AppTheme.fgFaint : AppTheme.accent,
                ),
              ),
              const SizedBox(width: 4),
              // Name + speed
              _nameCell(
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        style: AppFonts.mono(
                          fontSize: AppFonts.xs,
                          color: AppTheme.fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isQueued && entry.message.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        flex: 0,
                        child: Text(
                          entry.message,
                          style: AppFonts.mono(
                            fontSize: AppFonts.tiny,
                            color: AppTheme.accent,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Local path
              columnDivider(),
              SizedBox(
                width: localWidth,
                child: Tooltip(
                  message: isUpload ? entry.sourcePath : entry.targetPath,
                  child: Text(
                    _HistoryRow._shortenPath(
                      isUpload ? entry.sourcePath : entry.targetPath,
                    ),
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Remote path
              columnDivider(),
              SizedBox(
                width: remoteWidth,
                child: Tooltip(
                  message: isUpload ? entry.targetPath : entry.sourcePath,
                  child: Text(
                    _HistoryRow._shortenPath(
                      isUpload ? entry.targetPath : entry.sourcePath,
                    ),
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Progress
              columnDivider(),
              SizedBox(
                width: sizeWidth,
                child: Text(
                  isQueued
                      ? S.of(context).transferStatusQueued
                      : '${entry.percent.toStringAsFixed(0)}%',
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Message
              columnDivider(),
              SizedBox(
                width: timeWidth,
                child: Text(
                  entry.message,
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgFaint,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // 2px progress bar under active transfers
        if (!isQueued)
          Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              value: entry.percent / 100.0,
              backgroundColor: AppTheme.bg0,
              valueColor: AlwaysStoppedAnimation(AppTheme.accent),
              minHeight: 2,
            ),
          ),
      ],
    );
  }
}
