import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/transfer_task.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/transfer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/clipped_row.dart';
import '../../widgets/column_resize_handle.dart';
import '../../widgets/hover_region.dart';

/// Sort columns for the transfer table.
enum TransferSortColumn { name, local, remote, size, time }

/// Collapsible bottom panel showing transfer progress and history.
class TransferPanel extends ConsumerStatefulWidget {
  const TransferPanel({super.key});

  @override
  ConsumerState<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<TransferPanel> {
  bool _expanded = false;
  bool _wasRunning = false;
  double _panelHeight = 200;

  // Resizable column widths
  double _localColWidth = 110;
  double _remoteColWidth = 110;
  double _sizeColWidth = 50;
  double _timeColWidth = 95;

  // Sorting
  TransferSortColumn _sortColumn = TransferSortColumn.time;
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(transferManagerProvider);
    final historyAsync = ref.watch(transferHistoryProvider);
    final statusAsync = ref.watch(transferStatusProvider);

    // Auto-expand when transfers start
    final status = statusAsync.value;
    final isRunning = status?.hasActive ?? false;
    if (isRunning && !_wasRunning && !_expanded) {
      _expanded = true;
    }
    _wasRunning = isRunning;

    return Container(
      color: AppTheme.bg1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle header with overlaid drag handle
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Container(
                  height: AppTheme.barHeightSm,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: AppTheme.bg0,
                  child: ClippedRow(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 11,
                        color: AppTheme.fgDim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Transfers:',
                        style: AppFonts.inter(
                          fontSize: AppFonts.xs,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.fgDim,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (status != null) ...[
                        Text(
                          '${status.running} active',
                          style: AppFonts.inter(
                            fontSize: AppFonts.xs,
                            color: AppTheme.accent,
                          ),
                        ),
                        Text(
                          ', ${status.queued} queued',
                          style: AppFonts.inter(
                            fontSize: AppFonts.xs,
                            color: AppTheme.fgDim,
                          ),
                        ),
                      ],
                      const Spacer(),
                      historyAsync.when(
                        data: (history) => Text(
                          '${history.length} in history',
                          style: AppFonts.inter(
                            fontSize: AppFonts.xxs,
                            color: AppTheme.fgFaint,
                          ),
                        ),
                        loading: SizedBox.shrink,
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 4),
                      if (_expanded)
                        _headerButton(
                          icon: Icons.delete_outline,
                          tooltip: S.of(context).clearHistory,
                          onTap: () => manager.clearHistory(),
                        ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Positioned(
                  top: -3,
                  left: 0,
                  right: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          _panelHeight = (_panelHeight - d.delta.dy).clamp(
                            80.0,
                            500.0,
                          );
                        });
                      },
                      child: const SizedBox(height: 6),
                    ),
                  ),
                ),
            ],
          ),
          // Column headers + transfer list
          if (_expanded) ...[
            _buildColumnHeaders(),
            Flexible(
              child: SizedBox(
                height: _panelHeight,
                child: _buildTransferList(historyAsync, ref),
              ),
            ),
          ],
        ],
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
      size: 12,
      boxSize: 20,
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
        final sorted = _sortHistory(history);
        final totalCount = active.length + sorted.length;
        return ListView.builder(
          itemCount: totalCount,
          itemExtent: 24,
          itemBuilder: (context, index) {
            if (index < active.length) {
              return _ActiveRow(
                entry: active[index],
                localWidth: _localColWidth,
                remoteWidth: _remoteColWidth,
                sizeWidth: _sizeColWidth,
                timeWidth: _timeColWidth,
              );
            }
            return _HistoryRow(
              entry: sorted[index - active.length],
              localWidth: _localColWidth,
              remoteWidth: _remoteColWidth,
              sizeWidth: _sizeColWidth,
              timeWidth: _timeColWidth,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(S.of(context).errorPrefix(e.toString()))),
    );
  }

  static String _localPath(HistoryEntry e) =>
      e.direction == TransferDirection.upload ? e.sourcePath : e.targetPath;

  static String _remotePath(HistoryEntry e) =>
      e.direction == TransferDirection.upload ? e.targetPath : e.sourcePath;

  List<HistoryEntry> _sortHistory(List<HistoryEntry> history) {
    final sorted = List<HistoryEntry>.from(history);
    sorted.sort((a, b) {
      final cmp = switch (_sortColumn) {
        TransferSortColumn.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        TransferSortColumn.local => _localPath(a).compareTo(_localPath(b)),
        TransferSortColumn.remote => _remotePath(a).compareTo(_remotePath(b)),
        TransferSortColumn.size => a.sizeBytes.compareTo(b.sizeBytes),
        TransferSortColumn.time =>
          (a.endedAt ?? a.startedAt ?? a.createdAt).compareTo(
            b.endedAt ?? b.startedAt ?? b.createdAt,
          ),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  void _setSort(TransferSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  static Color? _headerColor(bool isActive, bool hovered) {
    if (isActive) return AppTheme.accent;
    if (hovered) return AppTheme.fgDim;
    return null;
  }

  Widget _buildColumnHeaders() {
    final style = AppFonts.inter(
      fontSize: AppFonts.xxs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    Widget headerCell(
      String label,
      TransferSortColumn column, {
      double? width,
    }) {
      final isActive = _sortColumn == column;
      String sortSuffix = '';
      if (isActive) {
        sortSuffix = _sortAscending ? ' ↑' : ' ↓';
      }
      return HoverRegion(
        cursor: SystemMouseCursors.click,
        onTap: () => _setSort(column),
        builder: (hovered) {
          final color = _headerColor(isActive, hovered);
          return SizedBox(
            width: width,
            child: Text(
              '$label$sortSuffix',
              style: color != null ? style.copyWith(color: color) : style,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    }

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
            child: headerCell(S.of(context).name, TransferSortColumn.name),
          ),
          ColumnResizeHandle(
            onDrag: (dx) => setState(
              () => _localColWidth = (_localColWidth - dx).clamp(60, 300),
            ),
          ),
          headerCell(
            S.of(context).local,
            TransferSortColumn.local,
            width: _localColWidth,
          ),
          ColumnResizeHandle(
            onDrag: (dx) => setState(
              () => _remoteColWidth = (_remoteColWidth - dx).clamp(60, 300),
            ),
          ),
          headerCell(
            S.of(context).remote,
            TransferSortColumn.remote,
            width: _remoteColWidth,
          ),
          ColumnResizeHandle(
            onDrag: (dx) => setState(
              () => _sizeColWidth = (_sizeColWidth - dx).clamp(40, 150),
            ),
          ),
          headerCell(
            S.of(context).size,
            TransferSortColumn.size,
            width: _sizeColWidth,
          ),
          ColumnResizeHandle(
            onDrag: (dx) => setState(
              () => _timeColWidth = (_timeColWidth - dx).clamp(60, 200),
            ),
          ),
          headerCell(
            S.of(context).time,
            TransferSortColumn.time,
            width: _timeColWidth,
          ),
        ],
      ),
    );
  }
}

/// Column divider line matching the file browser dividers.
Widget _colDivider() {
  return SizedBox(
    width: 10,
    child: Center(
      child: Container(
        width: 1,
        color: AppTheme.fgFaint.withValues(alpha: 0.15),
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;
  final double localWidth;
  final double remoteWidth;
  final double sizeWidth;
  final double timeWidth;

  const _HistoryRow({
    required this.entry,
    required this.localWidth,
    required this.remoteWidth,
    required this.sizeWidth,
    required this.timeWidth,
  });

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
              message: isFailed
                  ? (entry.error ?? S.of(context).failed)
                  : S.of(context).completed,
              child: Icon(
                isFailed ? Icons.error_outline : Icons.check_circle_outline,
                size: 10,
                color: isFailed ? AppTheme.red : AppTheme.green,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Name
          Expanded(
            child: Text(
              entry.name,
              style: AppFonts.mono(
                fontSize: AppFonts.xs,
                color: isFailed ? AppTheme.red : AppTheme.fgDim,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Local path
          _colDivider(),
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
          _colDivider(),
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
          _colDivider(),
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
          _colDivider(),
          SizedBox(
            width: timeWidth,
            child: Tooltip(
              message: _timeTooltip(entry),
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

  static String _timeTooltip(HistoryEntry entry) {
    final parts = <String>[];
    parts.add('Created: ${formatTimestamp(entry.createdAt)}');
    if (entry.startedAt != null) {
      parts.add('Started: ${formatTimestamp(entry.startedAt!)}');
    }
    if (entry.endedAt != null) {
      parts.add('Ended: ${formatTimestamp(entry.endedAt!)}');
    }
    if (entry.duration != null) {
      parts.add('Duration: ${formatDuration(entry.duration!)}');
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
  final double localWidth;
  final double remoteWidth;
  final double sizeWidth;
  final double timeWidth;

  const _ActiveRow({
    required this.entry,
    required this.localWidth,
    required this.remoteWidth,
    required this.sizeWidth,
    required this.timeWidth,
  });

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
              Expanded(
                child: Row(
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
              _colDivider(),
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
              _colDivider(),
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
              _colDivider(),
              SizedBox(
                width: sizeWidth,
                child: Text(
                  isQueued ? 'Queued' : '${entry.percent.toStringAsFixed(0)}%',
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Message
              _colDivider(),
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
