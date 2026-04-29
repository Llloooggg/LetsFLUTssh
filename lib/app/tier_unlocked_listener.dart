import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/bus/app_bus.dart';
import '../core/db/rust_db_init.dart';
import '../core/security/security_tier.dart';
import '../providers/config_provider.dart';
import '../providers/connection_provider.dart' show knownHostsProvider;
import '../providers/key_provider.dart' show keyStoreProvider;
import '../providers/security_provider.dart';
import '../providers/session_provider.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/tier_machine.dart' as rust_tier;
import '../utils/logger.dart';

/// Bus-driven post-unlock orchestrator. Subscribes to
/// `BusTopic.tier`, takes the key the Rust per-tier
/// orchestrator staged under `TIER_UNLOCK_KEY_ID`, and runs
/// the existing Dart post-unlock cascade — invalidate caches,
/// publish `securityStateProvider`, open the Rust DB,
/// persist the tier into config.
///
/// Lives as a Provider so [SecurityInitController] can hand
/// off the post-unlock work without owning either the bus
/// subscription or the per-tier `_injectDatabase` step
/// itself; the controller now just dispatches the orchestrator
/// and awaits [awaitNextUnlock] for the cascade to settle.
///
/// Both terminal events (`unlocked` and `locked`) resolve the
/// pending await — `locked` arrives from
/// `UnlockFailed { ... }` dispatches so a wrong-secret /
/// cancel / corruption branch unblocks the caller without
/// hanging on a never-arriving `unlocked` signal.
class TierUnlockedListener {
  TierUnlockedListener(this._ref);

  final Ref _ref;
  StreamSubscription<rust_bus.BusEvent>? _sub;
  Completer<TierUnlockOutcome>? _pending;

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
  Future<TierUnlockOutcome> awaitNextUnlock() {
    // Replace any in-flight wait — only one cascade at a time.
    final stale = _pending;
    if (stale != null && !stale.isCompleted) {
      stale.complete(TierUnlockOutcome.aborted);
    }
    final next = Completer<TierUnlockOutcome>();
    _pending = next;
    return next.future;
  }

  void _onEvent(rust_bus.BusEvent event) {
    if (event is! rust_bus.BusEvent_TierStateChanged) return;
    switch (event.stateWireName) {
      case 'unlocked':
        unawaited(_handleUnlocked());
      case 'locked':
        _resolvePending(TierUnlockOutcome.locked);
      case _:
        // Unlocking / Wiping — transient, no Dart-side work.
        break;
    }
  }

  Future<void> _handleUnlocked() async {
    try {
      // Take the key the Rust orchestrator staged. Atomic
      // read-and-remove so the SecretStore entry is gone
      // after the take — single FRB byte crossing per
      // unlock cascade.
      final keyBytes = rust_app.secretsTake(id: 'tier.unlock.key');
      // Resolve the active tier wire name to the Dart enum
      // so the post-unlock Dart cascade fans out the right
      // `securityStateProvider.set` slot.
      final tierWire = rust_tier.tierMachineActiveTierWireName();
      final tier = _tierFromWireName(tierWire);
      final key = keyBytes.isEmpty ? null : Uint8List.fromList(keyBytes);
      // Invalidate Dart-side store caches so the next read
      // pulls fresh rows after the engine swap. Mirrors the
      // existing `_injectDatabase` pre-step.
      _ref.read(sessionStoreProvider).invalidateCache();
      _ref.read(keyStoreProvider).invalidateCache();
      _ref.read(knownHostsProvider).invalidateCache();
      if (key != null) {
        _ref.read(securityStateProvider.notifier).set(tier, key);
      }
      // Open the Rust-owned sqlite handle keyed off the same
      // master key the orchestrator just resolved.
      await ensureRustDbOpen(key: key);
      // Persist the tier into config so a cold-restart picks
      // up the same tier without re-entering the wizard.
      // Modifiers come from the wizard / settings flow that
      // ran earlier; the listener reads the current config
      // and updates only when the resolved (tier, modifiers)
      // pair differs from what's stored.
      await _persistSecurityTier(tier);
      _resolvePending(TierUnlockOutcome.unlocked);
    } catch (e, st) {
      AppLogger.instance.log(
        'TierUnlockedListener post-unlock cascade failed: $e',
        name: 'TierUnlock',
        level: LogLevel.warn,
        error: e,
        stackTrace: st,
      );
      _resolvePending(TierUnlockOutcome.failed);
    }
  }

  /// Mirror of `SecurityInitController._persistSecurityTier`.
  /// Reads the current tier + modifiers from config and writes
  /// only when the resolved pair differs from the stored one.
  /// Modifiers come from the wizard's prior write — the listener
  /// just keeps the tier slot consistent with what the
  /// orchestrator just unlocked.
  Future<void> _persistSecurityTier(SecurityTier tier) async {
    final existing = _ref.read(configProvider).security;
    final resolved = existing?.modifiers ?? SecurityTierModifiers.defaults;
    if (existing != null &&
        existing.tier == tier &&
        existing.modifiers == resolved) {
      return;
    }
    final next = SecurityConfig(tier: tier, modifiers: resolved);
    await _ref
        .read(configProvider.notifier)
        .update((cfg) => cfg.copyWithSecurity(security: next));
  }

  void _resolvePending(TierUnlockOutcome outcome) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
  }
}

/// Outcome of the post-unlock cascade.
enum TierUnlockOutcome {
  /// `Unlocked` event fired + drift open + securityStateProvider
  /// set + caches invalidated. Caller proceeds with sessions /
  /// workspace bootstrap.
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

/// Resolve a tier wire name from the FRB-mirrored `tier_machine`
/// active-tier accessor. Mirrors `SecurityTier.values
/// .firstWhere(name)` shape inline so the listener doesn't pull
/// the security_tier enum into its imports.
SecurityTier _tierFromWireName(String wireName) {
  switch (wireName) {
    case 'plaintext':
      return SecurityTier.plaintext;
    case 'keychain':
      return SecurityTier.keychain;
    case 'keychain_with_password':
      return SecurityTier.keychainWithPassword;
    case 'hardware':
      return SecurityTier.hardware;
    case 'paranoid':
      return SecurityTier.paranoid;
  }
  // Defensive — orchestrator should never set an unknown tier.
  return SecurityTier.plaintext;
}

/// Process-singleton listener. Started from app bootstrap;
/// re-used across the entire process lifetime.
final tierUnlockedListenerProvider = Provider<TierUnlockedListener>((ref) {
  final listener = TierUnlockedListener(ref);
  ref.onDispose(listener.stop);
  return listener;
});
