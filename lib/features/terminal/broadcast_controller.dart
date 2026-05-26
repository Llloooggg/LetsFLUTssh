import 'package:flutter/foundation.dart';

import '../../src/rust/api/terminal.dart' as rust_terminal;
import '../../utils/logger.dart';

/// One unit of broadcast input fanned from the driver pane to each
/// receiver. Two shapes, because the two input paths must be replayed
/// differently on the receiver side:
///
///   * [BroadcastKey] carries a logical [rust_terminal.TerminalKey]. The
///     receiver re-encodes it against **its own** terminal mode via
///     `TerminalSession.sendKey`, so an arrow key lands as the right
///     SS3/CSI form even when the driver and receiver shells differ in
///     DECCKM / keypad state.
///   * [BroadcastBytes] carries already-encoded bytes (a paste body, a
///     snippet command, an on-bar special key) for `writeInput`. These
///     are mode-independent — bracketed-paste framing is decided at the
///     driver before the bytes are produced — so each receiver writes
///     them verbatim.
///
/// Fanning the high-level action (rather than the driver's encoded
/// keystroke bytes) is the load-bearing choice: re-encoding per receiver
/// is the only way a single broadcast keeps working across panes whose
/// programs put the terminal in different modes.
sealed class BroadcastInput {
  const BroadcastInput();
}

/// A logical key press to re-encode against each receiver's own mode.
class BroadcastKey extends BroadcastInput {
  const BroadcastKey(this.key);

  final rust_terminal.TerminalKey key;
}

/// Pre-encoded input bytes (paste / snippet / special on-bar key) to
/// write verbatim into each receiver's shell.
class BroadcastBytes extends BroadcastInput {
  const BroadcastBytes(this.bytes);

  final Uint8List bytes;
}

/// Sink that consumes broadcast input for a single pane.
///
/// The pane registers a callback that replays the [BroadcastInput] on
/// its own SSH shell — keys through `sendKey`, bytes through
/// `writeInput`. The controller invokes this callback when the pane is a
/// receiver and the driver pane fans out an input action.
typedef BroadcastSink = void Function(BroadcastInput input);

/// Per-tab fan-out coordinator for terminal broadcast input.
///
/// One pane per tab can be the **driver**: every input action the driver
/// produces (a key, a paste, a snippet) is mirrored into every registered
/// **receiver** pane's shell sink. Driver and receivers are identified by
/// the leaf-node id of their pane in the tiling tree.
///
/// **Why per-tab.** A workspace-wide controller would let the driver
/// in tab A leak keystrokes into tab B's receivers — almost never
/// what the user wants when they tab-switched. Tying lifetime to the
/// tab matches the user's mental "I'm broadcasting in this tab"
/// model and survives split / unsplit operations within the same tab.
///
/// **Why input-layer mirroring.** Broadcast taps the driver pane's
/// **input** path (the key / paste / snippet the user produced), not the
/// shell's output. Mirroring output would echo the driver's rendered
/// bytes onto receivers as if they were typed — doubling prompts and
/// corrupting the receiver grids. Each receiver re-runs the action
/// against its own session instead.
///
/// **Failure isolation.** A receiver sink may throw (broken shell,
/// closed connection). The controller wraps each invocation in a
/// `try/catch`, logs the failure through `AppLogger`, and continues
/// — one broken receiver never stalls the driver or starves later
/// receivers. The sink is left registered so the next reconnect can
/// reuse the same registration without the pane having to re-attach.
class BroadcastController extends ChangeNotifier {
  final String tabId;

  String? _driverId;
  final Set<String> _receiverIds = <String>{};
  final Map<String, BroadcastSink> _sinks = <String, BroadcastSink>{};

  BroadcastController(this.tabId);

  String? get driverId => _driverId;
  Set<String> get receiverIds => Set.unmodifiable(_receiverIds);

  /// True when at least one receiver is wired AND a driver is set.
  /// Driver-only or receivers-only states do not broadcast — both
  /// halves of the contract must be present.
  bool get isActive =>
      _driverId != null && _receiverIds.any((id) => id != _driverId);

  /// True iff [paneId] is currently broadcasting.
  bool isDriver(String paneId) => _driverId == paneId;

  /// True iff [paneId] is currently consuming the driver's stream.
  bool isReceiver(String paneId) =>
      _receiverIds.contains(paneId) && paneId != _driverId;

  /// Register the input sink for [paneId]. Called by the pane in its
  /// `initState` flow; idempotent on the same id (latest sink wins,
  /// since a pane that lost its shell on reconnect re-registers with
  /// a fresh write callback).
  void registerSink(String paneId, BroadcastSink sink) {
    _sinks[paneId] = sink;
  }

  /// Drop the sink and any driver/receiver assignment for [paneId].
  /// Called by the pane in `dispose`. Notifies listeners so any UI
  /// indicator on the now-removed pane can clean up.
  void unregisterSink(String paneId) {
    final removedAny = _sinks.remove(paneId) != null;
    final wasDriver = _driverId == paneId;
    final wasReceiver = _receiverIds.remove(paneId);
    if (wasDriver) _driverId = null;
    if (removedAny || wasDriver || wasReceiver) notifyListeners();
  }

  /// Promote [paneId] to driver. Pass `null` to clear the driver.
  /// A pane cannot be both driver and receiver at the same time —
  /// the controller drops the receiver assignment automatically when
  /// the same id is promoted to driver.
  void setDriver(String? paneId) {
    if (_driverId == paneId) return;
    _driverId = paneId;
    if (paneId != null) _receiverIds.remove(paneId);
    notifyListeners();
  }

  /// Toggle [paneId] in the receiver set. The driver pane is filtered
  /// at fan-out, so toggling the driver here is allowed but a no-op
  /// for routing. Returns the new membership state for UI feedback.
  bool toggleReceiver(String paneId) {
    final added = !_receiverIds.contains(paneId);
    if (added) {
      _receiverIds.add(paneId);
    } else {
      _receiverIds.remove(paneId);
    }
    notifyListeners();
    return added;
  }

  /// Clear driver + every receiver. Single-call escape hatch for the
  /// "stop everything" shortcut.
  void clearAll() {
    if (_driverId == null && _receiverIds.isEmpty) return;
    _driverId = null;
    _receiverIds.clear();
    notifyListeners();
  }

  /// Fan [input] from [originPaneId] into every registered receiver
  /// sink. No-op when [originPaneId] is not the current driver — the
  /// pane calls this on every key / paste regardless, the controller
  /// enforces the gate. Also no-op when no receivers are wired (the
  /// broadcast feature is opt-in; without receivers the driver is a
  /// label, not a multiplexer).
  void broadcastFrom(String originPaneId, BroadcastInput input) {
    if (originPaneId != _driverId) return;
    if (_receiverIds.isEmpty) return;
    for (final receiverId in _receiverIds) {
      if (receiverId == originPaneId) continue;
      final sink = _sinks[receiverId];
      if (sink == null) continue;
      try {
        sink(input);
      } catch (e, st) {
        AppLogger.instance.log(
          'Broadcast sink failed for receiver',
          name: 'Broadcast',
          error: e,
          stackTrace: st,
        );
      }
    }
  }
}
