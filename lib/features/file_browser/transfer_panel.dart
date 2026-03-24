import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/transfer/transfer_task.dart';
import '../../providers/transfer_provider.dart';
import '../../utils/format.dart';

/// Collapsible bottom panel showing transfer progress and history.
class TransferPanel extends ConsumerStatefulWidget {
  const TransferPanel({super.key});

  @override
  ConsumerState<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<TransferPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = ref.watch(transferManagerProvider);
    final historyAsync = ref.watch(transferHistoryProvider);

    return Column(
      children: [
        // Toggle header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.expand_less,
                  size: 16,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Transfers',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (manager.runningCount > 0)
                  Text(
                    '${manager.runningCount} active, ${manager.queueLength} queued',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
                  ),
                if (manager.currentTransferInfo != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    manager.currentTransferInfo!,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
                const Spacer(),
                historyAsync.when(
                  data: (history) => Text(
                    '${history.length} in history',
                    style: const TextStyle(fontSize: 11),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
                if (_expanded)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      onPressed: () => manager.clearHistory(),
                      icon: const Icon(Icons.delete_sweep, size: 14),
                      tooltip: 'Clear history',
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Expanded history list
        if (_expanded)
          SizedBox(
            height: 200,
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
}

class _HistoryRow extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = entry.status == TransferStatus.failed;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            entry.directionIcon,
            style: TextStyle(
              fontSize: 14,
              color: entry.direction == TransferDirection.upload
                  ? Colors.blue
                  : Colors.green,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            isFailed ? Icons.error : Icons.check_circle,
            size: 14,
            color: isFailed ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.name,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.duration != null) ...[
            const SizedBox(width: 8),
            Text(
              formatDuration(entry.duration!),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (isFailed && entry.error != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: entry.error!,
              child: Icon(Icons.info_outline, size: 14, color: Colors.red[300]),
            ),
          ],
        ],
      ),
    );
  }
}
