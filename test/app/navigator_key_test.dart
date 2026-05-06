/// Coverage for [OverlayModalRouteObserver] — the popup-route counter
/// the startup splash listens to so it can hide while a recovery
/// dialog (`showTierReset` / `showDbCorrupt`) is open.
///
/// The observer's invariants live or die on three properties:
///   * `PopupRoute` push/pop bumps the count exactly once
///   * `PageRoute` (full-page nav) is ignored
///   * The count clamps to zero — an unbalanced pop must not leave
///     the splash thinking a modal is still up forever.
///
/// All three are pure synchronous operations over the public
/// `NavigatorObserver` API, so the test drives them directly with
/// fake Route subtypes — no widget tree, no `pumpAndSettle`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';

void main() {
  group('OverlayModalRouteObserver', () {
    late OverlayModalRouteObserver observer;

    setUp(() {
      observer = OverlayModalRouteObserver();
    });

    test('initial active count is zero', () {
      expect(observer.activeCount.value, 0);
    });

    test('didPush(PopupRoute) increments the count', () {
      observer.didPush(_FakePopupRoute<void>(), null);
      expect(observer.activeCount.value, 1);
    });

    test('didPush(PageRoute) is ignored', () {
      observer.didPush(_FakePageRoute<void>(), null);
      expect(observer.activeCount.value, 0);
    });

    test('multiple PopupRoute pushes accumulate', () {
      observer.didPush(_FakePopupRoute<void>(), null);
      observer.didPush(_FakePopupRoute<void>(), null);
      observer.didPush(_FakePopupRoute<void>(), null);
      expect(observer.activeCount.value, 3);
    });

    test('didPop(PopupRoute) decrements the count', () {
      final route = _FakePopupRoute<void>();
      observer.didPush(route, null);
      observer.didPop(route, null);
      expect(observer.activeCount.value, 0);
    });

    test('didPop(PageRoute) is ignored', () {
      observer.didPush(_FakePopupRoute<void>(), null);
      observer.didPop(_FakePageRoute<void>(), null);
      // The popup push set the count to 1; popping a page route must
      // not change it.
      expect(observer.activeCount.value, 1);
    });

    test('didRemove(PopupRoute) decrements the count', () {
      final route = _FakePopupRoute<void>();
      observer.didPush(route, null);
      observer.didRemove(route, null);
      expect(observer.activeCount.value, 0);
    });

    test('didRemove(PageRoute) is ignored', () {
      observer.didPush(_FakePopupRoute<void>(), null);
      observer.didRemove(_FakePageRoute<void>(), null);
      expect(observer.activeCount.value, 1);
    });

    test('didPop clamps to zero on underflow', () {
      // Regression guard: if the counter dipped negative, the splash
      // would never re-show. Real-world trigger was the framework
      // calling didPop without a prior didPush during a rotation.
      observer.didPop(_FakePopupRoute<void>(), null);
      expect(observer.activeCount.value, 0);
    });

    test('didRemove clamps to zero on underflow', () {
      observer.didRemove(_FakePopupRoute<void>(), null);
      expect(observer.activeCount.value, 0);
    });

    test('mixed push/pop sequence balances out', () {
      final a = _FakePopupRoute<void>();
      final b = _FakePopupRoute<void>();
      observer.didPush(a, null);
      observer.didPush(b, null);
      expect(observer.activeCount.value, 2);
      observer.didPop(b, null);
      expect(observer.activeCount.value, 1);
      observer.didPop(a, null);
      expect(observer.activeCount.value, 0);
    });
  });

  group('top-level singletons', () {
    test('navigatorKey is non-null + reusable across reads', () {
      expect(navigatorKey, isNotNull);
      expect(identical(navigatorKey, navigatorKey), isTrue);
    });

    test('overlayModalRouteObserver singleton tracks its own count', () {
      // The shared instance is what `MaterialApp.navigatorObservers`
      // pins; the test must not mutate its state for fear of bleeding
      // into other tests in the same isolate. Just verify the wiring
      // is consistent: the convenience listenable returns the same
      // ValueListenable backing the observer's counter.
      expect(overlayModalRouteObserver, isNotNull);
      expect(
        identical(
          activeOverlayModalCount,
          overlayModalRouteObserver.activeCount,
        ),
        isTrue,
      );
    });
  });
}

/// Minimal `PopupRoute` stand-in — the observer only switches on
/// `route is PopupRoute`, so the abstract page builder etc. never
/// fire. Defaults satisfy the abstract surface without doing
/// anything user-visible.
class _FakePopupRoute<T> extends PopupRoute<T> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox.shrink();
}

/// Minimal `PageRoute` stand-in. Distinct from `_FakePopupRoute` so
/// the observer's `route is PopupRoute` check evaluates false.
class _FakePageRoute<T> extends PageRoute<T> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => false;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox.shrink();
}
