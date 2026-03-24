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
    final theme = Theme.of(context);
    final manager = ref.watch(transferManagerProvider);
    final historyAsync = ref.watch(transferHistoryProvider);
    final statusAsync = ref.watch(transferStatusProvider);

    // Auto-expand when transfers start
    final status = statusAsync.valueOrNull;
    final isRunning = status?.hasActive ?? false;
    if (isRunning && !_wasRunning && !_expanded) {
      _expanded = true;
    }
    _wasRunning = isRunning;

    return Column(
      children: [
        // Toggle header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Transfers',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (status != null && status.hasActive)
                  Text(
                    '${status.running} active, ${status.queued} queued',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  ),
                if (status?.currentInfo != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status!.currentInfo!,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                historyAsync.when(
                  data: (history) => Text(
                    '${history.length} in history',
                    style: const TextStyle(fontSize: 12),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
                if (_expanded)
                  IconButton(
                    onPressed: () => manager.clearHistory(),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    tooltip: 'Clear history',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
        // Resize handle
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
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
        // Column headers
        if (_expanded)
          _buildColumnHeaders(theme),
        // Expanded history list
        if (_expanded)
          SizedBox(
            height: _panelHeight,
            child: historyAsync.when(
              data: (history) {
                if (history.isEmpty) {
                  return const Center(
                    child: Text('No transfers yet', style: TextStyle(fontSize: 12)),
                  );
                }
                return ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) => _HistoryRow(entry: history[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
      ],
    );
  }

  Widget _buildColumnHeaders(ThemeData theme) {
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    const style = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);
    final divider = Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: theme.dividerColor,
    );

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          const SizedBox(width: 4),
          const SizedBox(width: 24),
          divider,
          Expanded(flex: 2, child: Text('Name', style: style.copyWith(color: dimColor))),
          divider,
          Expanded(flex: 2, child: Text('Local', style: style.copyWith(color: dimColor))),
          divider,
          Expanded(flex: 2, child: Text('Remote', style: style.copyWith(color: dimColor))),
          divider,
          SizedBox(width: 60, child: Text('Size', style: style.copyWith(color: dimColor), textAlign: TextAlign.right)),
          divider,
          SizedBox(width: 55, child: Text('Duration', style: style.copyWith(color: dimColor))),
          const SizedBox(width: 8),
          const SizedBox(width: 16),
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
    final theme = Theme.of(context);
    final isFailed = entry.status == TransferStatus.failed;
    final isUpload = entry.direction == TransferDirection.upload;
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final divider = Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: theme.dividerColor,
    );

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Direction icon
          SizedBox(
            width: 24,
            child: Text(
              entry.directionIcon,
              style: TextStyle(
                fontSize: 14,
                color: isUpload ? AppTheme.info : AppTheme.connected,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 4),
          // Status icon
          SizedBox(
            width: 24,
            child: Icon(
              isFailed ? Icons.error : Icons.check_circle,
              size: 14,
              color: isFailed ? AppTheme.disconnected : AppTheme.connected,
            ),
          ),
          divider,
          // Name
          Expanded(
            flex: 2,
            child: Text(
              entry.name,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          divider,
          // Local path
          Expanded(
            flex: 2,
            child: Tooltip(
              message: isUpload ? entry.sourcePath : entry.targetPath,
              child: Text(
                _shortenPath(isUpload ? entry.sourcePath : entry.targetPath),
                style: TextStyle(fontSize: 11, color: dimColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          divider,
          // Remote path
          Expanded(
            flex: 2,
            child: Tooltip(
              message: isUpload ? entry.targetPath : entry.sourcePath,
              child: Text(
                _shortenPath(isUpload ? entry.targetPath : entry.sourcePath),
                style: TextStyle(fontSize: 11, color: dimColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          divider,
          // Size
          SizedBox(
            width: 60,
            child: Text(
              entry.sizeBytes > 0 ? formatSize(entry.sizeBytes) : '',
              style: TextStyle(fontSize: 11, color: dimColor),
              textAlign: TextAlign.right,
            ),
          ),
          divider,
          // Duration
          SizedBox(
            width: 55,
            child: Text(
              entry.duration != null ? formatDuration(entry.duration!) : '',
              style: TextStyle(fontSize: 11, color: dimColor),
            ),
          ),
          const SizedBox(width: 8),
          // Error icon
          SizedBox(
            width: 16,
            child: isFailed && entry.error != null
                ? Tooltip(
                    message: entry.error!,
                    child: const Icon(Icons.info_outline, size: 14, color: AppTheme.disconnected),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Shorten a path to just the last 2 segments for display.
  static String _shortenPath(String path) {
    if (path.isEmpty) return '';
    // Normalize separators
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return normalized;
    return '.../${parts.sublist(parts.length - 2).join('/')}';
  }
}
