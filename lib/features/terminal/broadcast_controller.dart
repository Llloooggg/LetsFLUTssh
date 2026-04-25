import 'package:flutter/foundation.dart';

import '../../utils/logger.dart';

/// Sink that consumes broadcast bytes for a single pane.
///
/// The pane registers a callback that writes the bytes to its own SSH
/// shell. The controller invokes this callback when the pane is a
/// receiver and the driver pane fans out a keystroke.
typedef BroadcastSink = void Function(Uint8List bytes);

/// Per-tab fan-out coordinator for terminal broadcast input.
///
/// One pane per tab can be the **driver**: every byte the driver's
/// `Terminal.onOutput` produces is mirrored into every registered
/// **receiver** pane's shell sink. Driver and receivers are
/// identified by the leaf-node id of their pane in the tiling tree.
///
/// **Why per-tab.** A workspace-wide controller would let the driver
/// in tab A leak keystrokes into tab B's receivers — almost never
/// what the user wants when they tab-switched. Tying lifetime to the
/// tab matches the user's mental "I'm broadcasting in this tab"
/// model and survives split / unsplit operations within the same tab.
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

  /// Register the byte sink for [paneId]. Called by the pane in its
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

  /// Fan [bytes] from [originPaneId] into every registered receiver
  /// sink. No-op when [originPaneId] is not the current driver — the
  /// shell helper calls this on every keystroke regardless, the
  /// controller enforces the gate. Also no-op when no receivers are
  /// wired (the broadcast feature is opt-in; without receivers the
  /// driver is a label, not a multiplexer).
  void broadcastFrom(String originPaneId, Uint8List bytes) {
    if (originPaneId != _driverId) return;
    if (_receiverIds.isEmpty) return;
    for (final receiverId in _receiverIds) {
      if (receiverId == originPaneId) continue;
      final sink = _sinks[receiverId];
      if (sink == null) continue;
      try {
        sink(bytes);
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
