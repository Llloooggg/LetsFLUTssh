import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/transfer/transfer_manager.dart';
import '../core/transfer/transfer_task.dart';

/// Global transfer manager instance.
final transferManagerProvider = Provider<TransferManager>((ref) {
  final manager = TransferManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Reactive transfer history.
final transferHistoryProvider = StreamProvider<List<HistoryEntry>>((
  ref,
) async* {
  final manager = ref.watch(transferManagerProvider);
  yield manager.history;
  await for (final _ in manager.onChange) {
    yield manager.history;
  }
});

/// Reactive active/queued transfer entries for UI display.
final activeTransfersProvider = StreamProvider<List<ActiveEntry>>((ref) async* {
  final manager = ref.watch(transferManagerProvider);
  yield manager.activeEntries;
  await for (final _ in manager.onChange) {
    yield manager.activeEntries;
  }
});

/// Reactive transfer status (running count, queue length, current info).
final transferStatusProvider = StreamProvider<ActiveTransferState>((
  ref,
) async* {
  final manager = ref.watch(transferManagerProvider);
  yield ActiveTransferState(
    running: manager.runningCount,
    queued: manager.queueLength,
    currentInfo: manager.currentTransferInfo,
  );
  await for (final _ in manager.onChange) {
    yield ActiveTransferState(
      running: manager.runningCount,
      queued: manager.queueLength,
      currentInfo: manager.currentTransferInfo,
    );
  }
});

/// Snapshot of active transfer state.
class ActiveTransferState {
  final int running;
  final int queued;
  final String? currentInfo;

  const ActiveTransferState({
    this.running = 0,
    this.queued = 0,
    this.currentInfo,
  });

  bool get hasActive => running > 0 || queued > 0;
}
