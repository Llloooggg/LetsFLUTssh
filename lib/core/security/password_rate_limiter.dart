import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/persisted_rate_limit_actor.dart'
    as rust_persisted_actor;
import '../../src/rust/api/rate_limit.dart' as rust_rate_limit;
import '../../utils/logger.dart';

/// Exponential-backoff password rate limiter.
///
/// The schedule is deliberately small at the low end so a mistyped
/// password on the first try costs zero wait, and ramps up quickly
/// enough that dictionary poking via our UI becomes tedious. The cap
/// at 60 seconds is chosen so a legitimate user who genuinely forgot
/// their password never waits more than a minute between retries —
/// we are protecting against "person at the desk", not against a
/// determined offline attacker (Argon2id is what stops them).
///
/// Subclasses decide whether the state survives a process restart:
/// [InMemoryRateLimiter] drops everything on restart (fine for
/// Paranoid master-password mode, where the Argon2id cost is the
/// real brake), [PersistedRateLimiter] writes an HMAC-authenticated
/// record to disk (used by T1+pw keychain-with-password, where the
/// wrap-less check would otherwise permit immediate retry after a
/// relaunch).
abstract class PasswordRateLimiter {
  /// Seconds to wait between attempts after N consecutive failures.
  /// Index 0 = "no failures yet, no wait"; index 1 = "one failure,
  /// wait 1 s"; every index above that doubles up to the cap.
  ///
  /// Hydrated lazily from
  /// `lfs_core::rate_limit::BACKOFF_SCHEDULE` (FRB sync) so the
  /// schedule lives one place across Dart + Rust.
  static List<int> get backoffSchedule {
    return _cachedBackoff ??= List.unmodifiable(
      rust_rate_limit.rateLimitBackoffScheduleSeconds().map((s) => s.toInt()),
    );
  }

  static List<int>? _cachedBackoff;

  PasswordRateLimiter();

  /// Describes the limiter's current state to the caller. When a
  /// cooldown is active, [cooldownRemaining] is non-null and the
  /// UI renders a countdown instead of the password field.
  RateLimitStatus status();

  /// Register a failed attempt. Bumps the failure counter and sets
  /// the next-retry timestamp to now + next-step-of-backoff.
  void recordFailure();

  /// Register a successful attempt. Wipes the counter so the next
  /// unlock starts fresh.
  void recordSuccess();
}

/// Current state of a [PasswordRateLimiter]. `cooldownRemaining`
/// is non-null only when the next attempt is not yet permitted.
class RateLimitStatus {
  final int failureCount;
  final Duration? cooldownRemaining;

  const RateLimitStatus({
    required this.failureCount,
    required this.cooldownRemaining,
  });

  bool get isLocked =>
      cooldownRemaining != null && cooldownRemaining! > Duration.zero;
}

/// In-memory rate limiter. Used for Paranoid master-password mode
/// where the expensive Argon2id KDF is the real attacker cost; a
/// persistent counter here would be security theatre and user-
/// hostile (forgot-password wait carries across restarts for no
/// extra safety).
/// Thin shim over `lfs_core::rate_limit::InMemoryRateLimiterRegistry`
/// — the canonical exponential-backoff state lives Rust-side and
/// survives across Dart hot reload + Riverpod provider rebuilds.
/// Each instance allocates a unique id so multiple
/// `MasterPasswordManager` instances (production + tests) never
/// share counters.
///
/// The injected `now` clock is no longer honoured — Rust uses
/// `SystemTime::now`. Tests that need deterministic time should
/// build their own `PasswordRateLimiter` subclass; the production
/// path covers paranoid mode where Argon2id provides the real
/// brake regardless of the limiter clock.
class InMemoryRateLimiter extends PasswordRateLimiter {
  InMemoryRateLimiter() : _id = const Uuid().v4();

  final String _id;
  bool _disposed = false;

  @override
  RateLimitStatus status() {
    if (_disposed) return _zero;
    try {
      final s = rust_rate_limit.rateLimitStatus(id: _id);
      return RateLimitStatus(
        failureCount: s.failureCount.toInt(),
        cooldownRemaining: Duration(
          milliseconds: s.cooldownRemainingMs.toInt(),
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitStatus FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
      return _zero;
    }
  }

  @override
  void recordFailure() {
    if (_disposed) return;
    try {
      rust_rate_limit.rateLimitRecordFailure(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitRecordFailure FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
    }
  }

  @override
  void recordSuccess() {
    if (_disposed) return;
    try {
      rust_rate_limit.rateLimitRecordSuccess(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitRecordSuccess FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop the Rust-side limiter for this instance's id. Idempotent;
  /// safe to call multiple times. Not part of the abstract base —
  /// only the in-memory variant has Rust state to release.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      rust_rate_limit.rateLimitDrop(id: _id);
    } catch (_) {
      // FRB unavailable in flutter_test; nothing to drop.
    }
  }
}

/// Disk-backed rate limiter — used by the T1+pw keychain-with-password
/// path where the password is a bystander gate with no cryptographic
/// strength, and a restart-reset counter would let an attacker just
/// relaunch the process between attempts.
///
/// State file holds `{failureCount, nextRetryAtMillis, hmac}`. The
/// HMAC is computed with a secret key the caller supplies — in T1+pw's
/// case the SHA-256 of the comparison-hash already held in the
/// keychain, so an attacker who tampers with the state file without
/// also possessing the keychain entry ends up with a detectable HMAC
/// mismatch and is immediately thrown into max cooldown.
///
/// State lives in `lfs_core::security::persisted_rate_limit_actor`
/// (tokio actor with periodic flush). This Dart class is a thin
/// façade — `init_or_get` registers the limiter under [_id] with
/// the on-disk path + HMAC key; subsequent ops snapshot / mutate
/// that registered slot.
///
/// The production path uses [`PersistedRateLimiter.fromPrebuiltId`]:
/// `lfs_core::security::keychain_password_gate_actor::
/// build_persisted_rate_limiter` reads the gate envelope and
/// registers the slot inside Rust, so the HMAC bytes never cross
/// the FRB boundary. The default constructor stays for tests that
/// need to drive the limiter against an explicit HMAC + state
/// file path without going through the gate actor.
class PersistedRateLimiter extends PasswordRateLimiter {
  PersistedRateLimiter({required this._hmacKey, String? id})
    : _id = id ?? const Uuid().v4(),
      _initialised = false;

  /// Build a limiter against an id whose Rust-side slot is already
  /// registered (via `keychain_password_gate_actor::
  /// build_persisted_rate_limiter`). The HMAC + state-file path
  /// live entirely in the Rust actor under `id`; this Dart wrapper
  /// only forwards status / record ops to that slot. Skips the
  /// `_ensureInit` round-trip — the actor is already wired.
  PersistedRateLimiter.fromPrebuiltId(String id)
    : _hmacKey = Uint8List(0),
      _id = id,
      _initialised = true;

  /// Only consulted by the explicit-constructor path; the
  /// `fromPrebuiltId` factory leaves this empty because the actor
  /// is already wired with the HMAC inside Rust.
  final Uint8List _hmacKey;

  /// Per-instance id under which the Rust
  /// `persisted_rate_limit_actor` registers this limiter. Each
  /// Dart instance auto-allocates one so multiple gates
  /// (production + tests) never share counters inside the
  /// singleton registry.
  final String _id;

  /// True once the Rust actor has a registered slot for [_id]. The
  /// `fromPrebuiltId` factory starts true because Rust already
  /// registered the slot before handing the id over; the default
  /// constructor starts false and flips via `statusAsync` /
  /// `_ensureInit` on first call.
  bool _initialised;

  /// Force a re-read on next status call. Clears the actor's slot
  /// and the local init flag so the next operation re-initialises.
  void invalidateCache() {
    if (_initialised) {
      try {
        rust_persisted_actor.persistedRateLimitActorClear(id: _id);
      } catch (_) {
        // Actor unreachable — re-init on next call will recover.
      }
    }
    _initialised = false;
  }

  /// Awaits the actor's most-recent in-flight `tokio::spawn_blocking`
  /// disk write for this limiter. Routes through
  /// `persisted_rate_limit_actor_flush` (FRB async) so callers
  /// observe a settled disk state deterministically — replaces the
  /// earlier `Future.delayed(50ms)` heuristic.
  ///
  /// Safe to call when no write is pending — the FRB function
  /// returns immediately in that case.
  Future<void> awaitPendingSave() async {
    try {
      await rust_persisted_actor.persistedRateLimitActorFlush(id: _id);
    } catch (_) {
      // FRB unavailable / actor unreachable in some test contexts —
      // fall through; the worst case is the test observes the
      // pre-write state, not an empty / corrupt one.
    }
  }

  @override
  RateLimitStatus status() {
    if (!_initialised) {
      // Init hasn't settled yet (sync caller hit before
      // `statusAsync`). Return the safe baseline so the unlock
      // dialog renders no cooldown — `statusAsync` resolves the
      // actor slot and the next read shows the real state.
      return _zero;
    }
    try {
      final s = rust_persisted_actor.persistedRateLimitActorStatus(id: _id);
      final ms = s.cooldownRemainingMs.toInt();
      return RateLimitStatus(
        failureCount: s.failureCount.toInt(),
        cooldownRemaining: ms > 0 ? Duration(milliseconds: ms) : Duration.zero,
      );
    } catch (_) {
      return _zero;
    }
  }

  /// Async variant — loads the on-disk frame (HMAC-verified) before
  /// snapshotting. The unlock dialog awaits this on open so the
  /// post-restart cooldown countdown lands on the first frame.
  Future<RateLimitStatus> statusAsync() async {
    await _ensureInit();
    return status();
  }

  @override
  void recordFailure() {
    if (!_initialised) {
      // First call before `statusAsync` settled — try the Rust
      // actor direct (the call is itself the probe; success means
      // the actor accepted the failure under [_id], failure means
      // the slot wasn't registered yet and the failure is lost).
      try {
        rust_persisted_actor.persistedRateLimitActorRecordFailure(id: _id);
        _initialised = true;
      } catch (e) {
        AppLogger.instance.log(
          'PersistedRateLimiter recordFailure pre-init dropped: $e',
          name: 'PersistedRateLimiter',
        );
      }
      return;
    }
    try {
      rust_persisted_actor.persistedRateLimitActorRecordFailure(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter recordFailure failed: $e',
        name: 'PersistedRateLimiter',
      );
    }
  }

  @override
  void recordSuccess() {
    if (!_initialised) {
      try {
        rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: _id);
        _initialised = true;
      } catch (e) {
        AppLogger.instance.log(
          'PersistedRateLimiter recordSuccess pre-init dropped: $e',
          name: 'PersistedRateLimiter',
        );
      }
      return;
    }
    try {
      rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter recordSuccess failed: $e',
        name: 'PersistedRateLimiter',
      );
    }
  }

  Future<void> _ensureInit() async {
    if (_initialised) return;
    try {
      rust_persisted_actor.persistedRateLimitActorInitOrGet(
        id: _id,
        hmacKey: _hmacKey,
      );
      _initialised = true;
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter init failed: $e',
        name: 'PersistedRateLimiter',
      );
    }
  }
}

/// Thin software counter layered **on top of** the hardware rate
/// limit enforced by the platform keystore / Secure Enclave / TPM
/// `dictionaryAttackLockout`. Defense-in-depth: if the hardware
/// lockout is misconfigured on the host (older TPMs, custom
/// firmware) or a platform CVE defeats it, the software limiter
/// still slows the attacker via the same exp-backoff schedule the
/// other limiters use.
///
/// State lives in `lfs_core::rate_limit::InMemoryRateLimiterRegistry`,
/// the same registry [`InMemoryRateLimiter`] uses; the canonical
/// schedule + counter math lives one place across both Dart limiter
/// shims so the hardware-overlay can never drift from the in-memory
/// path. Each instance allocates a unique id so multiple unlock
/// flows (production + tests) never share counters.
///
/// State is in-memory — the hardware layer is the source of truth
/// for persistent lockout semantics. Resets on process restart;
/// anyone restarting the process already paid the cost of talking
/// to the hardware again, which itself is rate-limited.
///
/// The injected `now` clock is no longer honoured — Rust uses
/// `SystemTime::now`. Mirrors [`InMemoryRateLimiter`].
class HardwareRateLimiter extends PasswordRateLimiter {
  HardwareRateLimiter() : _id = const Uuid().v4();

  final String _id;
  bool _disposed = false;

  @override
  RateLimitStatus status() {
    if (_disposed) return _zero;
    try {
      final s = rust_rate_limit.rateLimitStatus(id: _id);
      return RateLimitStatus(
        failureCount: s.failureCount.toInt(),
        cooldownRemaining: Duration(
          milliseconds: s.cooldownRemainingMs.toInt(),
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitStatus FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
      return _zero;
    }
  }

  @override
  void recordFailure() {
    if (_disposed) return;
    try {
      rust_rate_limit.rateLimitRecordFailure(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitRecordFailure FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
    }
  }

  @override
  void recordSuccess() {
    if (_disposed) return;
    try {
      rust_rate_limit.rateLimitRecordSuccess(id: _id);
    } catch (e) {
      AppLogger.instance.log(
        'rateLimitRecordSuccess FRB failed: $e',
        name: 'RateLimit',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop the Rust-side limiter slot for this instance's id.
  /// Idempotent; safe to call repeatedly. Mirrors
  /// [`InMemoryRateLimiter.dispose`] — the hardware overlay's state
  /// is in the same registry.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      rust_rate_limit.rateLimitDrop(id: _id);
    } catch (_) {
      // FRB unavailable in flutter_test; nothing to drop.
    }
  }
}

const _zero = RateLimitStatus(
  failureCount: 0,
  cooldownRemaining: Duration.zero,
);
