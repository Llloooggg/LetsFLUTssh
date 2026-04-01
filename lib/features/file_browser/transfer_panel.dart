import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/transfer_task.dart';
import '../../providers/transfer_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

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
      children: [
        // Drag handle
        if (_expanded)
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onVerticalDragUpdate: (d) {
                setState(() {
                  _panelHeight = (_panelHeight - d.delta.dy).clamp(80.0, 500.0);
                });
              },
              child: Container(
                height: 4,
                color: AppTheme.bg0,
                alignment: Alignment.center,
                child: Container(width: 32, height: 1, color: AppTheme.borderLight),
              ),
            ),
          ),
        // Toggle header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.bg3,
              border: Border(
                top: BorderSide(color: AppTheme.border),
                bottom: _expanded
                    ? BorderSide(color: AppTheme.border)
                    : BorderSide.none,
              ),
            ),
            child: Row(
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
                    style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.accent),
                  ),
                  Text(
                    ', ${status.queued} queued',
                    style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
                  ),
                ],
                const Spacer(),
                historyAsync.when(
                  data: (history) => Text(
                    '${history.length} in history',
                    style: AppFonts.inter(fontSize: AppFonts.xxs, color: AppTheme.fgFaint),
                  ),
                  loading: SizedBox.shrink,
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
                if (_expanded)
                  _headerButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Clear history',
                    onTap: () => manager.clearHistory(),
                  ),
              ],
            ),
          ),
        ),
        // Column headers + transfer list
        if (_expanded) ...[
          _buildColumnHeaders(),
          SizedBox(
            height: _panelHeight,
            child: _buildTransferList(historyAsync, ref),
          ),
          _buildFooter(ref),
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(icon, size: 12, color: AppTheme.fgFaint),
        ),
      ),
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
              'No transfers yet',
              style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
            ),
          );
        }
        final totalCount = active.length + history.length;
        return ListView.builder(
          itemCount: totalCount,
          itemExtent: 24,
          itemBuilder: (context, index) {
            if (index < active.length) {
              return _ActiveRow(entry: active[index]);
            }
            return _HistoryRow(entry: history[index - active.length]);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildColumnHeaders() {
    final style = AppFonts.inter(
      fontSize: AppFonts.xxs,
      fontWeight: FontWeight.w500,
      color: AppTheme.fgFaint,
    );

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppTheme.bg3,
      child: Row(
        children: [
          SizedBox(width: 16, child: Text('#', style: style)),
          const SizedBox(width: 4),
          SizedBox(width: 20, child: Text('', style: style)),
          const SizedBox(width: 4),
          Expanded(flex: 2, child: Text('Name', style: style)),
          Expanded(flex: 2, child: Text('Local', style: style)),
          Expanded(flex: 2, child: Text('Remote', style: style)),
          SizedBox(width: 56, child: Text('Size', style: style, textAlign: TextAlign.right)),
          SizedBox(width: 50, child: Text('Duration', style: style)),
        ],
      ),
    );
  }

  Widget _buildFooter(WidgetRef ref) {
    final statusAsync = ref.watch(transferStatusProvider);
    final status = statusAsync.value;
    final historyAsync = ref.watch(transferHistoryProvider);
    final historyCount = historyAsync.value?.length ?? 0;

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.bg0,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 5, color: AppTheme.green),
          const SizedBox(width: 6),
          if (status != null)
            Text(
              '${status.running} active · ${status.queued} queued',
              style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
            ),
          Text(
            ' · $historyCount in hist',
            style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isFailed = entry.status == TransferStatus.failed;
    final isUpload = entry.direction == TransferDirection.upload;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Status icon
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
            child: Icon(
              isFailed ? Icons.error_outline : Icons.check_circle_outline,
              size: 10,
              color: isFailed ? AppTheme.red : AppTheme.green,
            ),
          ),
          const SizedBox(width: 4),
          // Name
          Expanded(
            flex: 2,
            child: Text(
              entry.name,
              style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgDim),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Local path
          Expanded(
            flex: 2,
            child: Tooltip(
              message: isUpload ? entry.sourcePath : entry.targetPath,
              child: Text(
                _shortenPath(isUpload ? entry.sourcePath : entry.targetPath),
                style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Remote path
          Expanded(
            flex: 2,
            child: Tooltip(
              message: isUpload ? entry.targetPath : entry.sourcePath,
              child: Text(
                _shortenPath(isUpload ? entry.targetPath : entry.sourcePath),
                style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Size
          SizedBox(
            width: 56,
            child: Text(
              entry.sizeBytes > 0 ? formatSize(entry.sizeBytes) : '',
              style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
              textAlign: TextAlign.right,
            ),
          ),
          // Duration
          SizedBox(
            width: 50,
            child: Text(
              entry.duration != null ? formatDuration(entry.duration!) : '',
              style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
            ),
          ),
        ],
      ),
    );
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

  const _ActiveRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isUpload = entry.direction == TransferDirection.upload;
    final isQueued = entry.status == TransferStatus.queued;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
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
                flex: 2,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fg),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isQueued && entry.message.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        entry.message,
                        style: AppFonts.mono(fontSize: AppFonts.tiny, color: AppTheme.accent),
                      ),
                    ],
                  ],
                ),
              ),
              // Local path
              Expanded(
                flex: 2,
                child: Tooltip(
                  message: isUpload ? entry.sourcePath : entry.targetPath,
                  child: Text(
                    _HistoryRow._shortenPath(isUpload ? entry.sourcePath : entry.targetPath),
                    style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Remote path
              Expanded(
                flex: 2,
                child: Tooltip(
                  message: isUpload ? entry.targetPath : entry.sourcePath,
                  child: Text(
                    _HistoryRow._shortenPath(isUpload ? entry.targetPath : entry.sourcePath),
                    style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Progress
              SizedBox(
                width: 56,
                child: Text(
                  isQueued ? 'Queued' : '${entry.percent.toStringAsFixed(0)}%',
                  style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.accent),
                  textAlign: TextAlign.right,
                ),
              ),
              // Message
              SizedBox(
                width: 50,
                child: Text(
                  entry.message,
                  style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgFaint),
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
