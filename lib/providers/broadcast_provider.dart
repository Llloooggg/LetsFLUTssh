import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/terminal/broadcast_controller.dart';

/// One [BroadcastController] per terminal tab id.
///
/// Family-keyed so distinct tabs cannot leak keystrokes into one
/// another's panes — see the rationale on `BroadcastController`. The
/// provider keeps every tab's controller alive for the duration of
/// the app process so a quick tab-switch does not lose driver /
/// receiver state mid-broadcast; explicit teardown happens when the
/// last pane in a tab unregisters its sink. UI surfaces consume the
/// notifier via `ref.watch(broadcastControllerProvider(tabId))` and
/// listen for `notifyListeners` updates the same way every other
/// `ChangeNotifier`-backed provider in the app does.
final broadcastControllerProvider =
    Provider.family<BroadcastController, String>((ref, tabId) {
      final controller = BroadcastController(tabId);
      ref.onDispose(controller.dispose);
      return controller;
    });
