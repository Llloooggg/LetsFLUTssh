import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/security/security_tier.dart';
import '../providers/security_provider.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../utils/logger.dart';

/// Wall-clock budget for `awaitNextUnlock().timeout(...)` across
/// every tier-unlock and first-launch path. The Rust orchestrator
/// fires `UnlockCascadeReady` after it opens the rusqlite handle
/// + persists the tier — on a fresh-install Windows IoT box with
/// Defender + SQLCipher PBKDF2-256k header derivation + first-time
/// vendored-OpenSSL init, the Rust-side cascade end-to-end is
/// ~6-10s. Anything tighter (the previous 5s budget) raced against
/// the Rust side and fired the destructive Dart-fallback / vault-
/// missing path even though the unlock was succeeding. 30s mirrors
/// the connect-actor timeout, well past worst observed init wall-
/// clock; users on hung systems still get a recovery dialog within
/// a single coffee-sip rather than the prior 5s flap-into-data-
/// destruction window.
const tierUnlockedListenerWaitTimeout = Duration(seconds: 30);

/// Bus-driven post-unlock listener. Subscribes to
/// `BusTopic.tier`; the Rust per-tier orchestrator owns the
/// post-stage cascade (DB-open via `app::instance().db_init`,
/// tier persistence via `config_store::update_security_tier`)
/// and publishes `BusEvent::UnlockCascadeReady { tier_wire,
/// has_key }` after both side-effects settle. The Dart half
/// runs ONLY the Riverpod work — cache invalidations +
/// `securityStateProvider.setActive` — driven off the payload
/// the Rust side carries.
///
/// Lives as a Provider so [SecurityInitController] can hand
/// off the post-unlock work without owning either the bus
/// subscription or the per-tier ordering itself; the controller
/// now just dispatches the orchestrator and awaits
/// [awaitNextUnlock] for the cascade to settle.
///
/// Both terminal events (cascade-ready and `locked`) resolve the
/// pending await — `locked` arrives from
/// `UnlockFailed { ... }` dispatches so a wrong-secret /
/// cancel / corruption branch unblocks the caller without
/// hanging on a never-arriving cascade-ready signal.
class TierUnlockedListener {
  TierUnlockedListener(this._ref);

  final Ref _ref;
  StreamSubscription<rust_bus.BusEvent>? _sub;
  Completer<TierUnlockOutcome>? _pending;

  /// When true, the in-flight `_pending` future ignores intermediate
  /// `locked` terminal events (orchestrator emits one per failed
  /// attempt in multi-attempt dialog tiers — T1+pw/T2/Paranoid). Only
  /// `unlocked` or an explicit [cancelPending] resolves the wait.
  /// T0/T1 (single-shot) keep the default `false` so a missing
  /// keychain entry surfaces as `locked` instead of hanging.
  bool _onlyUnlocked = false;

  /// Subscribe to the tier topic. Idempotent — repeated calls
  /// re-bind to the same singleton.
  void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance.subscribe(rust_bus.BusTopic.tier).listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'TierUnlockedListener subscribe failed: $e',
        name: 'TierUnlock',
        level: LogLevel.warn,
      );
    }
  }

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(TierUnlockOutcome.aborted);
    }
  }

  /// Arm a single-shot await for the next terminal-state event.
  /// Returns `unlocked` when the cascade reaches `Unlocked` +
  /// the post-unlock Dart steps land, or `locked` when the
  /// orchestrator emits `UnlockFailed { ... }`. Caller must
  /// arm BEFORE dispatching the orchestrator (otherwise the
  /// event may fire before the await registers and the next
  /// arm picks up a stale completion).
  ///
  /// [onlyUnlocked]: ignore intermediate `locked` events. The
  /// multi-attempt dialog tiers (T1+pw/T2/Paranoid) re-enter the
  /// orchestrator on every wrong-secret submit; each attempt
  /// fires a paired `UnlockFailed` → `Locked` transition. The
  /// caller awaits the FINAL `Unlocked` (set when the user
  /// either submits a correct secret or dismisses the dialog
  /// — dismiss routes through [cancelPending]).
  Future<TierUnlockOutcome> awaitNextUnlock({bool onlyUnlocked = false}) {
    // Replace any in-flight wait — only one cascade at a time.
    final stale = _pending;
    if (stale != null && !stale.isCompleted) {
      stale.complete(TierUnlockOutcome.aborted);
    }
    final next = Completer<TierUnlockOutcome>();
    _pending = next;
    _onlyUnlocked = onlyUnlocked;
    return next.future;
  }

  /// Resolve the in-flight wait with `aborted`. Used by the
  /// multi-attempt dialog dismiss path (user closed the dialog
  /// without submitting a correct secret) — the listener was
  /// armed with `onlyUnlocked: true` so the intermediate
  /// `locked` events from per-attempt failures didn't resolve
  /// it; the dismiss is the explicit signal.
  void cancelPending() {
    _resolvePending(TierUnlockOutcome.aborted);
  }

  void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_UnlockCascadeReady) {
      _handleCascadeReady(event);
      return;
    }
    if (event is! rust_bus.BusEvent_TierStateChanged) return;
    switch (event.stateWireName) {
      case 'locked':
        if (_onlyUnlocked) {
          // Multi-attempt dialog mode — caller is awaiting the
          // FINAL unlocked. Wrong-secret per-attempt locks are
          // intermediate; the dialog handles the retry UI and
          // the dismiss path resolves explicitly via
          // [cancelPending].
          break;
        }
        _resolvePending(TierUnlockOutcome.locked);
      case _:
        // Unlocking / Unlocked / Wiping — the Rust orchestrator
        // drives its half of the cascade and then publishes
        // `UnlockCascadeReady`; the Dart Riverpod work runs off
        // that single payload instead of the per-state wire-name
        // dance.
        break;
    }
  }

  /// Dart-side half of the unlock cascade. Runs after the Rust
  /// orchestrator already opened the rusqlite handle + persisted
  /// the tier into `config.json`; this body is the Riverpod-only
  /// rendezvous (cache invalidations + `securityStateProvider`
  /// flip + resolve the pending `awaitNextUnlock`).
  void _handleCascadeReady(rust_bus.BusEvent_UnlockCascadeReady event) {
    try {
      final tier = SecurityTierWireName.fromWireName(event.tierWire);
      // Sessions + ssh_keys + known_hosts streams re-fetch off the
      // `SessionsChanged` / `KeysChanged` / `KnownHostsChanged` bus
      // events the Rust orchestrator publishes right before
      // `UnlockCascadeReady` — no Dart-side cache to invalidate.
      _ref
          .read(securityStateProvider.notifier)
          .setActive(tier, hasKey: event.hasKey);
      _resolvePending(TierUnlockOutcome.unlocked);
    } catch (e, st) {
      AppLogger.instance.log(
        'TierUnlockedListener Riverpod cascade failed: $e',
        name: 'TierUnlock',
        level: LogLevel.warn,
        error: e,
        stackTrace: st,
      );
      _resolvePending(TierUnlockOutcome.failed);
    }
  }

  void _resolvePending(TierUnlockOutcome outcome) {
    final pending = _pending;
    _pending = null;
    _onlyUnlocked = false;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
  }
}

/// Outcome of the post-unlock cascade.
enum TierUnlockOutcome {
  /// `Unlocked` event fired + rusqlite/SQLCipher open via
  /// `dbInit` + securityStateProvider set + caches invalidated.
  /// Caller proceeds with sessions / workspace bootstrap.
  unlocked,

  /// `Locked` event fired (orchestrator emitted UnlockFailed).
  /// Caller routes through the wrong-secret / cancel / corruption
  /// branch.
  locked,

  /// Post-unlock cascade itself threw. Caller falls back to a
  /// plaintext recovery path.
  failed,

  /// Listener torn down before any terminal event landed.
  aborted,
}

/// Process-singleton listener. Started from app bootstrap;
/// re-used across the entire process lifetime.
final tierUnlockedListenerProvider = Provider<TierUnlockedListener>((ref) {
  final listener = TierUnlockedListener(ref);
  ref.onDispose(listener.stop);
  return listener;
});
