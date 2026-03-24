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
final transferHistoryProvider = StreamProvider<List<HistoryEntry>>((ref) async* {
  final manager = ref.watch(transferManagerProvider);
  yield manager.history;
  await for (final _ in manager.onChange) {
    yield manager.history;
  }
});
