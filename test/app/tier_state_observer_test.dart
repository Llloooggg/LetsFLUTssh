/// Coverage for [TierStateObserver] start/stop public surface.
///
/// The observer is a diagnostic-only subscriber: it logs every
/// `BusEvent_TierStateChanged` the Rust tier machine publishes. The
/// `_onEvent` log path is private; what this file asserts is the
/// public lifecycle contract every cold-start caller relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/tier_state_observer.dart';
import 'package:letsflutssh/src/rust/frb_generated.dart' show RustLib;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(TierStateObserver.stop);

  group('cold-start safety — RustLib not yet initialised', () {
    test('start() does not throw before FRB is loaded', () {
      if (RustLib.instance.initialized) {
        markTestSkipped('FRB already loaded in this isolate');
        return;
      }
      expect(TierStateObserver.start, returnsNormally);
    });

    test('stop() does not throw without a prior start', () {
      expect(TierStateObserver.stop, returnsNormally);
    });
  });

  group('post-FRB — subscription wiring', () {
    setUpAll(requireFrbLoaded);

    test('start() attaches a subscription without throwing', () {
      expect(TierStateObserver.start, returnsNormally);
    });

    test('start() is idempotent — repeated calls do not stack', () {
      TierStateObserver.start();
      TierStateObserver.start();
      TierStateObserver.start();
      expect(TierStateObserver.stop, returnsNormally);
    });

    test('stop() then start() re-attaches', () {
      TierStateObserver.start();
      TierStateObserver.stop();
      expect(TierStateObserver.start, returnsNormally);
    });

    test('stop() is safe to call repeatedly', () {
      TierStateObserver.stop();
      TierStateObserver.stop();
    });
  });
}
