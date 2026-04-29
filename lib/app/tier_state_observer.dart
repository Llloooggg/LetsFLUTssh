import 'dart:async';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../utils/logger.dart';

/// Diagnostic subscriber for the C9 `tier_machine` bus topic.
///
/// Logs every transition the actor publishes so support traces
/// show the unlock / lock / wipe sequence the user observed.
/// Non-functional — does not own any state, does not change the
/// unlock flow. The production Dart `SecurityInitController`
/// keeps owning the cascade until the C9.1+ per-tier wiring
/// commits flip individual tiers behind feature gates.
///
/// Process-singleton subscription. Cold-start init from
/// `MainScreenState.initState` alongside the other bus
/// listeners.
class TierStateObserver {
  TierStateObserver._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;

  /// Idempotent — repeated calls re-bind to the same singleton
  /// subscription so a hot-reload or a second wire pass doesn't
  /// stack listeners.
  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance.subscribe(rust_bus.BusTopic.tier).listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'TierStateObserver subscribe failed: $e',
        name: 'TierMachine',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_TierStateChanged) {
      AppLogger.instance.log(
        'TierStateChanged: ${event.stateWireName}',
        name: 'TierMachine',
      );
    }
  }
}
