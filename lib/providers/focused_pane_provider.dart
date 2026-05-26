import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks the focused pane id within a single terminal tab. Keyed by
/// `tabId` so split panes in different tabs do not interfere.
///
/// `TerminalTabState` writes here on initial mount (its first leaf)
/// and on every `onPaneFocused` callback. Cross-subtree consumers
/// (today: the workspace's per-panel connection bar, which renders
/// the record button) `ref.watch` this to know which pane's
/// recording state to display and toggle. Local `setState` would
/// not propagate to the connection bar — it lives in a sibling
/// subtree — so the workspace needs a shared, observable channel.
class FocusedPaneNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? paneId) {
    if (state != paneId) state = paneId;
  }
}

final focusedPaneProvider =
    NotifierProvider.family<FocusedPaneNotifier, String?, String>(
      (_) => FocusedPaneNotifier(),
    );
