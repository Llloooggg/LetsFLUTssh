import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Root `MaterialApp` navigator key.
///
/// Used by callers outside the widget tree that need a `BuildContext`
/// with a mounted Navigator — crash-handler dialogs, deep-link pump,
/// post-frame toasts — because those contexts fire from `runZoned` /
/// async callbacks / native method channels where the framework
/// cannot otherwise hand them a live `BuildContext`.
///
/// Readers must always check `currentContext?.mounted` before use —
/// the MaterialApp can be in the middle of a rebuild or rotation
/// when the async callback resumes, at which point the context is
/// unmounted and calling `Navigator.of(context)` / `showDialog`
/// would throw.
final navigatorKey = GlobalKey<NavigatorState>();

/// Tracks how many overlay-style modal routes (`PopupRoute` —
/// covers `showDialog`, `showModalBottomSheet`, `showMenu`, …) sit
/// on top of the root navigator's stack. `PageRoute` pushes
/// (full-page navigation) are intentionally ignored.
///
/// Wired to [MaterialApp.navigatorObservers] in `main_app.dart`. The
/// startup splash overlay (`_StartupSplash`) listens to
/// [activeOverlayModalCount] and hides itself while the count is
/// non-zero, otherwise a bootstrap-time recovery dialog
/// (`showTierReset` / `showDbCorrupt`) lands inside the navigator
/// *under* the splash — modal painted, but the user can't see it,
/// so the spinner spins forever waiting for a click that can't
/// happen. Observer-driven coordination keeps the splash dumb (no
/// per-call site try/finally around every `_dialogs.show*` invocation).
class OverlayModalRouteObserver extends NavigatorObserver {
  final ValueNotifier<int> activeCount = ValueNotifier(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) activeCount.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      activeCount.value = (activeCount.value - 1).clamp(0, 1 << 30);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      activeCount.value = (activeCount.value - 1).clamp(0, 1 << 30);
    }
  }
}

/// Singleton observer instance. Attached to `MaterialApp.navigatorObservers`
/// once; the splash widget watches [activeOverlayModalCount].
final overlayModalRouteObserver = OverlayModalRouteObserver();

/// Convenience handle exposing only the listenable side of the
/// observer's counter — splash widgets watch through this rather
/// than the full observer to make the read-only contract explicit.
ValueListenable<int> get activeOverlayModalCount =>
    overlayModalRouteObserver.activeCount;
