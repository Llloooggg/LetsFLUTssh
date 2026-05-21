import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/bus.dart' as rust_bus;
import '../core/bus/app_bus.dart';
import '../utils/logger.dart';

/// Whether the app is currently auto-locked.
///
/// `true` → the root widget tree swaps to the lock screen and blocks
/// all interaction; the DB key is zeroed in memory. `false` → normal
/// UI.
///
/// **Source of truth for the lock state is Rust's `tier_machine`.**
/// The notifier subscribes to `BusTopic.tier` and flips on the
/// `locked` / `wiping` wire names (lock path) and on
/// `UnlockCascadeReady` (unlock path). The Dart side never originates
/// a transition by mutating the bool directly — auto-lock requests go
/// through `tierMachineDispatch(DbTierEvent::LockRequested)` and
/// unlock attempts go through `tier_unlock_*` orchestrators, both of
/// which publish the bus events that the notifier observes.
final lockStateProvider = NotifierProvider<LockStateNotifier, bool>(
  LockStateNotifier.new,
);

/// Riverpod notifier backing [lockStateProvider].
///
/// Two transition paths, both idempotent, both Rust-driven:
///
/// 1. **Lock** — Rust's `tier_machine` emits
///    `BusEvent::TierStateChanged { state_wire_name: "locked" }` (or
///    `"wiping"`) and the bus subscription flips [state] to `true`.
///    Triggers: idle timer, lifecycle backgrounding,
///    `WipeAllService`, or any other path that dispatches
///    `TierEvent::LockRequested` / `TierEvent::Wiped` against the
///    singleton tier machine.
/// 2. **Unlock** — Rust's `run_post_unlock_cascade` opens the DB,
///    persists the tier, publishes the store-changed events
///    (`SessionsChanged` / `KeysChanged` / `KnownHostsChanged`),
///    then publishes `BusEvent::UnlockCascadeReady { tier_wire,
///    has_key }`. The notifier flips [state] back to `false` on that
///    terminal event — every store the workspace tree reads has
///    already re-fetched, so the re-mount lands on ready data.
///    `TierStateChanged { wire: "unlocked" }` fires earlier in the
///    Rust cascade and is intentionally ignored here.
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
    if (event is rust_bus.BusEvent_UnlockCascadeReady) {
      // Terminal Rust-side cascade signal — DB open, tier persisted,
      // store-changed events already published. Safe to drop the
      // overlay and let the workspace tree re-mount.
      if (state) {
        AppLogger.instance.log(
          'lock overlay → off (Rust cascade ready, tier: ${event.tierWire})',
          name: 'LockState',
        );
        state = false;
      }
      return;
    }
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
        // Don't flip on `unlocked` — Rust's `run_post_unlock_cascade`
        // emits this BEFORE it opens the rusqlite handle, persists
        // the tier, and publishes the store-changed events. The
        // workspace tree would otherwise re-mount against a transient
        // half-open DB. `UnlockCascadeReady` is the terminal signal
        // that every store is ready; the overlay clears there.
        // `unlocking` is a transient state with no overlay
        // implication of its own.
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

  /// Test-only seam — force the lock overlay off without
  /// round-tripping through Rust's `run_post_unlock_cascade` +
  /// `BusEvent::UnlockCascadeReady`. Mirrors [debugForceLocked]; the
  /// lock-screen widget tests use an `_ImmediateListener` that
  /// short-circuits the orchestrator, so the bus never delivers the
  /// cascade-ready event that production flips on.
  @visibleForTesting
  void debugForceUnlocked() {
    if (state) state = false;
  }
}
