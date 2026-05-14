import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../bus/app_bus.dart';
import '../../utils/logger.dart';

/// Whether the app is currently auto-locked.
///
/// `true` → the root widget tree swaps to the lock screen and blocks
/// all interaction; the DB key is zeroed in memory. `false` → normal
/// UI.
///
/// **Source of truth for the lock state is Rust's `tier_machine`.**
/// The notifier subscribes to `BusTopic.tier` and flips on the
/// `locked` / `wiping` wire names. The Dart side never originates a
/// lock by mutating the bool directly — auto-lock requests go through
/// `tierMachineDispatch(DbTierEvent::LockRequested)`, which dispatches
/// the transition Rust-side and publishes the bus event that the
/// notifier observes.
final lockStateProvider = NotifierProvider<LockStateNotifier, bool>(
  LockStateNotifier.new,
);

/// Riverpod notifier backing [lockStateProvider].
///
/// Two transition paths, both idempotent:
///
/// 1. **Lock** — Rust's `tier_machine` emits
///    `BusEvent::TierStateChanged { state_wire_name: "locked" }` (or
///    `"wiping"`) and the bus subscription flips [state] to `true`.
///    Triggers: idle timer, lifecycle backgrounding,
///    `WipeAllService`, or any other path that dispatches
///    `TierEvent::LockRequested` / `TierEvent::Wiped` against the
///    singleton tier machine.
/// 2. **Unlock** — driven entirely by the Dart-side cascade in
///    `LockScreen`. The Rust orchestrator fires
///    `TierStateChanged { wire: "unlocked" }` BEFORE the
///    `TierUnlockedListener` finishes its post-unlock work (caches,
///    `dbInit`, `securityStateProvider`, config persist). The lock
///    overlay stays up across that cascade because the workspace UI
///    re-mounts on the bool flip and would otherwise hit a transient
///    half-open DB. [markUnlockCascadeComplete] is called by the
///    lock screen AFTER the listener resolves, which is when it's
///    actually safe to swap back to the workspace tree.
class LockStateNotifier extends Notifier<bool> {
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  @override
  bool build() {
    // Subscribe to the tier topic so any Rust-side transition into a
    // locking-style state (auto-lock, wipe, settings-driven manual
    // lock, …) flips the overlay. The subscribe call hits the FRB
    // native lib at construction time; flutter_test contexts that
    // don't load the lib raise synchronously. Catch + log so the
    // notifier stays usable in tests; the [AppBus] layer itself also
    // promotes the dead subscription once FRB lands so a
    // pre-FRB-init `ref.watch` during the first runApp frame doesn't
    // permanently anchor a half-wired notifier.
    try {
      _busSub = AppBus.instance
          .subscribe(rust_bus.BusTopic.tier)
          .listen(_onBusEvent);
    } catch (e) {
      AppLogger.instance.log(
        'LockStateNotifier bus subscribe failed: $e',
        name: 'LockState',
        level: LogLevel.warn,
      );
    }
    ref.onDispose(() {
      unawaited(_busSub?.cancel());
      _busSub = null;
    });
    return false;
  }

  void _onBusEvent(rust_bus.BusEvent event) {
    if (event is! rust_bus.BusEvent_TierStateChanged) return;
    switch (event.stateWireName) {
      case 'locked':
      case 'wiping':
        if (!state) {
          AppLogger.instance.log(
            'lock overlay → on (tier wire: ${event.stateWireName})',
            name: 'LockState',
          );
          state = true;
        }
      case 'unlocked':
      case 'unlocking':
        // Don't flip on `unlocked` — the Dart post-unlock cascade in
        // `TierUnlockedListener` still has work to do (caches,
        // dbInit, securityStateProvider, config persist) and the
        // workspace UI would otherwise re-mount against a transient
        // half-open DB. [markUnlockCascadeComplete] is the signal
        // that the cascade is done and it's safe to swap back to the
        // workspace tree. `unlocking` is a transient state with no
        // overlay implication of its own.
        break;
      case _:
        // Unknown wire name — log + drop. New `TierState` variants
        // ship Rust-side with their own bus visibility; the notifier
        // doesn't need to react until the variant is wired here.
        AppLogger.instance.log(
          'LockState: unknown tier wire name ${event.stateWireName}',
          name: 'LockState',
          level: LogLevel.warn,
        );
    }
  }

  /// Signal that the Dart-side post-unlock cascade has finished and
  /// the workspace UI can re-mount. Called by the lock screen after
  /// `TierUnlockedListener.awaitNextUnlock` resolves — the workspace
  /// would otherwise re-mount on the bus event ahead of the cascade
  /// landing the rusqlite handle.
  void markUnlockCascadeComplete() {
    if (state) {
      AppLogger.instance.log(
        'lock overlay → off (Dart unlock cascade complete)',
        name: 'LockState',
      );
      state = false;
    }
  }

  /// Test-only seam — force the lock overlay on without round-tripping
  /// through the Rust tier machine + bus. The production lock path
  /// drives through `tierMachineDispatch(LockRequested)` which fires
  /// `BusEvent::TierStateChanged { locked }`; flutter_test contexts
  /// don't load the FRB native lib so that round-trip never lands. The
  /// auto-lock detector + lock-screen widget tests need to seed a
  /// locked state directly.
  @visibleForTesting
  void debugForceLocked() {
    if (!state) state = true;
  }
}
