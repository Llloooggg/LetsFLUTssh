import 'package:flutter/foundation.dart';

/// Per-pane recording controller — exposed through
/// [PaneRecordingRegistry] so the connection bar's record button
/// (which lives in a different widget subtree than the terminal pane)
/// can read the recording state and toggle it.
///
/// `isRecording` drives the button's visual state (`ValueListenable`
/// so only the icon rebuilds when recording flips). `canRecord`
/// gates the button at all — false for quick-connect sessions (no
/// `sessionId`, no on-disk destination). `toggle` is the imperative
/// action invoked on tap: start a recorder if not recording, stop
/// the current one otherwise. Failures are surfaced via the
/// recorder's own logger; the toggle resolves either way so the
/// button never gets stuck spinning.
class PaneRecordingHandle {
  final ValueListenable<bool> isRecording;
  final bool canRecord;
  final Future<void> Function() toggle;

  const PaneRecordingHandle({
    required this.isRecording,
    required this.canRecord,
    required this.toggle,
  });
}

/// Global lookup from pane id to its [PaneRecordingHandle]. Each
/// `TerminalPaneState` registers itself in `initState` and removes
/// itself in `dispose`, so the registry only ever holds entries
/// for currently-mounted panes. Look-ups by paneId from the
/// workspace's connection bar resolve through this singleton —
/// the bar reads the focused pane id from `focusedPaneProvider`
/// (Riverpod) and grabs the matching handle here.
///
/// Not a `ChangeNotifier` — registration churn does not need
/// to rebuild the bar (the bar reads the focused-pane id, not
/// the whole map). `isRecording` flips on each handle drive the
/// only relevant rebuilds.
class PaneRecordingRegistry {
  PaneRecordingRegistry._();
  static final PaneRecordingRegistry instance = PaneRecordingRegistry._();

  final Map<String, PaneRecordingHandle> _byPane = {};

  PaneRecordingHandle? get(String paneId) => _byPane[paneId];

  void register(String paneId, PaneRecordingHandle handle) {
    _byPane[paneId] = handle;
  }

  void unregister(String paneId) {
    _byPane.remove(paneId);
  }
}
