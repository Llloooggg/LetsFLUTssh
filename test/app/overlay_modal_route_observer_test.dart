import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/navigator_key.dart';

/// Unit-tests `OverlayModalRouteObserver` against synthetic Route
/// instances, not a live Navigator. We're testing the route-class
/// discriminator (PopupRoute increments, PageRoute does not), not
/// Flutter's navigator implementation.
///
/// The earlier widget-driven version pumped a `MaterialPageRoute`
/// through `pumpAndSettle` and hung on the route's enter
/// transition animation under `flutter_test`'s clock — bypassing
/// the navigator entirely keeps the test deterministic.
void main() {
  group('OverlayModalRouteObserver', () {
    late OverlayModalRouteObserver observer;

    setUp(() {
      observer = OverlayModalRouteObserver();
      // Reset the singleton too — the splash widget reads it directly,
      // and a previous test that leaked count would carry into prod
      // counters within the same isolate. The instance under test
      // is the local `observer`, but the assertion below covers the
      // singleton path the widget reads through.
      overlayModalRouteObserver.activeCount.value = 0;
    });

    test('didPush(PageRoute) does not increment', () {
      observer.didPush(_FakePageRoute(), null);
      expect(observer.activeCount.value, 0);
    });

    test('didPush(PopupRoute) increments', () {
      observer.didPush(_FakePopupRoute(), null);
      expect(observer.activeCount.value, 1);
    });

    test('didPop(PopupRoute) decrements after a push', () {
      final route = _FakePopupRoute();
      observer.didPush(route, null);
      observer.didPop(route, null);
      expect(observer.activeCount.value, 0);
    });

    test('didRemove(PopupRoute) decrements after a push', () {
      final route = _FakePopupRoute();
      observer.didPush(route, null);
      observer.didRemove(route, null);
      expect(observer.activeCount.value, 0);
    });

    test('count clamps at zero on spurious decrements', () {
      // Defence against an out-of-order didPop (e.g. observer added
      // mid-frame after a route already pushed). Going negative
      // would let later pushes fail to mask the splash.
      observer.didPop(_FakePopupRoute(), null);
      observer.didPop(_FakePopupRoute(), null);
      expect(observer.activeCount.value, 0);
    });

    test('multiple PopupRoutes stack the count', () {
      observer.didPush(_FakePopupRoute(), null);
      observer.didPush(_FakePopupRoute(), null);
      expect(observer.activeCount.value, 2);
    });

    test(
      'singleton activeOverlayModalCount is wired to the singleton observer',
      () {
        expect(
          activeOverlayModalCount,
          same(overlayModalRouteObserver.activeCount),
        );
      },
    );
  });
}

/// Minimal `PopupRoute` stand-in. Implementing the abstract surface
/// in full is unnecessary — the observer only reads `route is
/// PopupRoute`, so `extends PopupRoute` with stub overrides
/// satisfies the discriminator without dragging in an Overlay.
class _FakePopupRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => false;
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

class _FakePageRoute extends PageRoute<void> {
  @override
  Color? get barrierColor => null;
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
  @override
  bool get opaque => true;
}
