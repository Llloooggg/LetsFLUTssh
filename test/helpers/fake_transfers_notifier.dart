import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

/// In-memory [TransfersNotifier] for tests — bypasses the FRB native
/// lib so widget tests can seed history / active / status without
/// bootstrapping `lfs_core::transfer::TransferQueue`.
///
/// `clearHistory` records the call (so tests can assert the button
/// wired through), then clears the in-memory history.
class FakeTransfersNotifier extends TransfersNotifier {
  FakeTransfersNotifier({
    List<HistoryEntry> history = const [],
    List<ActiveEntry> active = const [],
    ActiveTransferState status = const ActiveTransferState(),
  }) : _initial = TransfersState(
         history: List.of(history),
         active: List.of(active),
         status: status,
       );

  final TransfersState _initial;
  int clearHistoryCalls = 0;

  @override
  TransfersState build() {
    state = _initial;
    return state;
  }

  @override
  Future<void> clearHistory() async {
    clearHistoryCalls++;
    state = TransfersState(
      history: const [],
      active: state.active,
      status: state.status,
    );
  }

  /// Convenience for tests: read the current history snapshot.
  List<HistoryEntry> get history => state.history;
}
