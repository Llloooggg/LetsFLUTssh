import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/persisted_rate_limit_actor.dart'
    as rust_persisted_actor;
import '../../src/rust/api/rate_limit.dart' as rust_rate_limit;
import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '_crypto_compat.dart';

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
/// record to disk (used by L2 keychain-with-password, where the
/// wrap-less check would otherwise permit immediate retry after a
/// relaunch).
abstract class PasswordRateLimiter {
  /// Seconds to wait between attempts after N consecutive failures.
  /// Index 0 = "no failures yet, no wait"; index 1 = "one failure,
  /// wait 1 s"; every index above that doubles up to the cap.
  ///
  /// Hydrated lazily from
  /// `lfs_core::rate_limit::BACKOFF_SCHEDULE` (FRB sync) so the
  /// schedule lives one place across Dart + Rust; falls back to
  /// the inline literal when the FRB native lib is not loaded
  /// (flutter_test contexts that don't initialise `RustLib`).
  static List<int> get backoffSchedule {
    return _cachedBackoff ??= _resolveBackoff();
  }

  static List<int>? _cachedBackoff;
  static const List<int> _backoffFallback = [0, 1, 2, 4, 8, 16, 32, 60, 60, 60];

  static List<int> _resolveBackoff() {
    try {
      return List.unmodifiable(
        rust_rate_limit.rateLimitBackoffScheduleSeconds().map((s) => s.toInt()),
      );
    } catch (_) {
      return _backoffFallback;
    }
  }

  /// Clock injection for deterministic tests.
  final DateTime Function() _now;

  PasswordRateLimiter({DateTime Function()? now}) : _now = now ?? DateTime.now;

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

  /// How long the user must wait from [fromNow] before the next
  /// retry is allowed, or `Duration.zero` if no cooldown is active.
  Duration _cooldownRemaining(DateTime? nextRetryAt) {
    if (nextRetryAt == null) return Duration.zero;
    final diff = nextRetryAt.difference(_now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Compute the next-retry timestamp from the current failure count.
  DateTime? _nextRetryAfterFailure(int failureCount) {
    final idx = failureCount < backoffSchedule.length
        ? failureCount
        : backoffSchedule.length - 1;
    final seconds = backoffSchedule[idx];
    if (seconds == 0) return null;
    return _now().add(Duration(seconds: seconds));
  }
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
  InMemoryRateLimiter({super.now}) : _id = const Uuid().v4();

  final String _id;
  bool _disposed = false;

  @override
  RateLimitStatus status() {
    if (_disposed) {
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
    }
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
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
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

/// Disk-backed rate limiter — used by the L2 keychain-with-password
/// path where the password is a bystander gate with no cryptographic
/// strength, and a restart-reset counter would let an attacker just
/// relaunch the process between attempts.
///
/// State file holds `{failureCount, nextRetryAtMillis, hmac}`. The
/// HMAC is computed with a secret key the caller supplies — in L2's
/// case the SHA-256 of the comparison-hash already held in the
/// keychain, so an attacker who tampers with the state file without
/// also possessing the keychain entry ends up with a detectable HMAC
/// mismatch and is immediately thrown into max cooldown.
///
/// Tamper path: [status] verifies the HMAC at load. On mismatch the
/// failure counter is clamped to the schedule cap and `nextRetryAt`
/// is set to `now + maxCooldown`. Legitimate writers always produce
/// a valid HMAC, so a legit restart never trips this branch.
class PersistedRateLimiter extends PasswordRateLimiter {
  PersistedRateLimiter({
    required Uint8List hmacKey,
    Future<File> Function()? stateFileFactory,
    String? id,
    super.now,
  }) : _hmacKey = hmacKey,
       _stateFile = stateFileFactory ?? _defaultStateFile,
       _id = id ?? const Uuid().v4();

  static const _fileName = 'rate_limit_state.bin';

  final Uint8List _hmacKey;
  final Future<File> Function() _stateFile;

  /// Per-instance id under which the Rust
  /// `persisted_rate_limit_actor` registers this limiter. Each
  /// Dart instance auto-allocates one so multiple gates
  /// (production + tests) never share counters inside the
  /// singleton registry.
  final String _id;

  /// Set once `_initOnce` confirms the Rust actor loaded the
  /// on-disk frame. Until then, [status] returns the safe zero
  /// baseline so the unlock dialog renders no cooldown before the
  /// load settles.
  bool _initialised = false;

  /// True when the Rust `persisted_rate_limit_actor` is reachable
  /// (production). False when the FRB native lib is not loaded
  /// (flutter_test) — the limiter falls back to an in-memory
  /// state machine + per-instance disk write chain.
  bool _useRust = true;

  // ── Dart-fallback state (used when `_useRust == false`) ────────
  _RateState? _cachedFallback;
  bool _loadedFallback = false;
  Future<void> _pendingSaveFallback = Future<void>.value();

  /// Force a re-read on next status call. Drops the Rust actor's
  /// cache + the Dart fallback cache.
  void invalidateCache() {
    _initialised = false;
    _cachedFallback = null;
    _loadedFallback = false;
    if (_useRust) {
      try {
        rust_persisted_actor.persistedRateLimitActorClear(id: _id);
      } catch (_) {
        // Actor unreachable — fallback path will re-load on
        // next status call.
      }
    }
  }

  /// Awaits any pending save. In Rust mode the actor schedules
  /// writes via `tokio::spawn_blocking`; we yield twice to give
  /// the worker thread a chance to drain. In fallback mode we
  /// await the `_pendingSaveFallback` chain directly.
  Future<void> awaitPendingSave() async {
    if (_useRust) {
      await Future<void>.value();
      await Future<void>.value();
    } else {
      await _pendingSaveFallback;
    }
  }

  @override
  RateLimitStatus status() {
    if (_useRust && _initialised) {
      try {
        return _toRateLimitStatus(
          rust_persisted_actor.persistedRateLimitActorStatus(id: _id),
        );
      } catch (_) {
        // Actor unreachable mid-flight — fall through to fallback.
        _useRust = false;
      }
    }
    if (_useRust && !_initialised) {
      // Init hasn't settled yet (production caller didn't await
      // statusAsync). Return the safe baseline so the unlock
      // dialog renders no cooldown — the bus event will refresh
      // it once init completes.
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
    }
    return _statusFallback();
  }

  /// Async variant — loads the on-disk frame (HMAC-verified)
  /// before snapshotting. The unlock dialog awaits this on open
  /// so the post-restart cooldown countdown lands on the first
  /// frame.
  Future<RateLimitStatus> statusAsync() async {
    await _ensureLoaded();
    return status();
  }

  @override
  void recordFailure() {
    if (_useRust) {
      if (!_initialised) {
        // First-call probe: attempt the Rust path so a sync
        // caller (test harness) gets either a Rust-side update
        // or a fast fall-through to the inline state machine.
        try {
          rust_persisted_actor.persistedRateLimitActorRecordFailure(id: _id);
          // Rust accepted the call — actor is reachable. Mark
          // initialised so subsequent reads route through Rust
          // even if the caller never awaits statusAsync.
          _initialised = true;
          return;
        } catch (_) {
          _useRust = false;
        }
      } else {
        try {
          rust_persisted_actor.persistedRateLimitActorRecordFailure(id: _id);
          return;
        } catch (e) {
          _useRust = false;
          AppLogger.instance.log(
            'PersistedRateLimiter recordFailure rust path failed, '
            'falling through to fallback: $e',
            name: 'PersistedRateLimiter',
          );
        }
      }
    }
    _recordFailureFallback();
  }

  @override
  void recordSuccess() {
    if (_useRust) {
      if (!_initialised) {
        try {
          rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: _id);
          _initialised = true;
          return;
        } catch (_) {
          _useRust = false;
        }
      } else {
        try {
          rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: _id);
          return;
        } catch (e) {
          _useRust = false;
          AppLogger.instance.log(
            'PersistedRateLimiter recordSuccess rust path failed, '
            'falling through to fallback: $e',
            name: 'PersistedRateLimiter',
          );
        }
      }
    }
    _recordSuccessFallback();
  }

  Future<void> _ensureLoaded() async {
    if (_initialised || _loadedFallback) return;
    File? file;
    try {
      file = await _stateFile();
      await file.parent.create(recursive: true);
      rust_persisted_actor.persistedRateLimitActorInitOrGet(
        id: _id,
        filePath: file.path,
        hmacKey: _hmacKey,
      );
      _initialised = true;
      _useRust = true;
      return;
    } catch (_) {
      // Rust actor unreachable, or the path_provider plugin is not
      // mocked (flutter_test contexts). Fall back to the inline
      // Dart state machine + disk write chain so the limiter still
      // functions in unit tests.
      _useRust = false;
    }
    if (file != null) {
      await _ensureLoadedFallback(file);
    } else {
      // path_provider call failed before yielding a path — adopt
      // the zero-state baseline so subsequent recordFailure calls
      // still update the in-memory cache (writes will silently
      // fail in the same way the Dart-only legacy branch did).
      _cachedFallback = const _RateState(failureCount: 0);
      _loadedFallback = true;
    }
  }

  // ── Dart fallback implementation ───────────────────────────────

  RateLimitStatus _statusFallback() {
    if (!_loadedFallback) {
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
    }
    final state = _cachedFallback;
    if (state == null) {
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
    }
    return RateLimitStatus(
      failureCount: state.failureCount,
      cooldownRemaining: _cooldownRemaining(state.nextRetryAt),
    );
  }

  void _recordFailureFallback() {
    final current = _cachedFallback ?? const _RateState(failureCount: 0);
    final cap = PasswordRateLimiter.backoffSchedule.length - 1;
    final next = current.failureCount + 1;
    final nextCount = next > cap ? cap : next;
    final nextRetryAt = _nextRetryAfterFailure(nextCount);
    final state = _RateState(failureCount: nextCount, nextRetryAt: nextRetryAt);
    _cachedFallback = state;
    _loadedFallback = true;
    _unawaitedSaveFallback(state);
  }

  void _recordSuccessFallback() {
    _cachedFallback = const _RateState(failureCount: 0);
    _loadedFallback = true;
    _unawaitedSaveFallback(_cachedFallback!);
  }

  void _unawaitedSaveFallback(_RateState state) {
    _pendingSaveFallback = _pendingSaveFallback.catchError((_) {}).then((
      _,
    ) async {
      try {
        final file = await _stateFile();
        await file.parent.create(recursive: true);
        final bytes = persistedRateLimitEncodeCompat(
          PersistedRateLimitState(
            failureCount: state.failureCount,
            nextRetryAtMillis: state.nextRetryAt?.millisecondsSinceEpoch,
          ),
          _hmacKey,
        );
        await file.writeAsBytes(bytes, flush: true);
        await hardenFilePerms(file.path);
      } catch (e) {
        AppLogger.instance.log(
          'PersistedRateLimiter fallback save failed: $e',
          name: 'PersistedRateLimiter',
        );
      }
    });
  }

  Future<void> _ensureLoadedFallback(File file) async {
    if (_loadedFallback) return;
    try {
      if (!await file.exists()) {
        _cachedFallback = const _RateState(failureCount: 0);
        _loadedFallback = true;
        return;
      }
      final raw = await file.readAsBytes();
      final decoded = persistedRateLimitDecodeCompat(raw, _hmacKey);
      if (decoded == null) {
        _cachedFallback = _RateState(
          failureCount: PasswordRateLimiter.backoffSchedule.length - 1,
          nextRetryAt: _now().add(
            Duration(seconds: PasswordRateLimiter.backoffSchedule.last),
          ),
        );
      } else {
        final cap = PasswordRateLimiter.backoffSchedule.length - 1;
        final clamped = decoded.failureCount < 0
            ? 0
            : (decoded.failureCount > cap ? cap : decoded.failureCount);
        _cachedFallback = _RateState(
          failureCount: clamped,
          nextRetryAt: decoded.nextRetryAtMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(decoded.nextRetryAtMillis!),
        );
      }
      _loadedFallback = true;
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter fallback load failed: $e',
        name: 'PersistedRateLimiter',
      );
      _cachedFallback = const _RateState(failureCount: 0);
      _loadedFallback = true;
    }
  }

  static RateLimitStatus _toRateLimitStatus(
    rust_rate_limit.DbRateLimitStatus s,
  ) {
    final ms = s.cooldownRemainingMs.toInt();
    return RateLimitStatus(
      failureCount: s.failureCount.toInt(),
      cooldownRemaining: ms > 0 ? Duration(milliseconds: ms) : Duration.zero,
    );
  }

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }
}

class _RateState {
  final int failureCount;
  final DateTime? nextRetryAt;

  const _RateState({required this.failureCount, this.nextRetryAt});
}

/// Thin software counter layered **on top of** the hardware rate
/// limit enforced by the platform keystore / Secure Enclave / TPM
/// `dictionaryAttackLockout`. Defense-in-depth: if the hardware
/// lockout is misconfigured on the host (older TPMs, custom
/// firmware) or a platform CVE defeats it, the software limiter
/// still slows the attacker via the same exp-backoff schedule the
/// other limiters use.
///
/// State is in-memory — the hardware layer is the source of truth
/// for persistent lockout semantics. Resets on process restart;
/// anyone restarting the process already paid the cost of talking
/// to the hardware again, which itself is rate-limited.
class HardwareRateLimiter extends PasswordRateLimiter {
  HardwareRateLimiter({super.now});

  int _failureCount = 0;
  DateTime? _nextRetryAt;

  @override
  RateLimitStatus status() => RateLimitStatus(
    failureCount: _failureCount,
    cooldownRemaining: _cooldownRemaining(_nextRetryAt),
  );

  @override
  void recordFailure() {
    final cap = PasswordRateLimiter.backoffSchedule.length - 1;
    final next = _failureCount + 1;
    _failureCount = next > cap ? cap : next;
    _nextRetryAt = _nextRetryAfterFailure(_failureCount);
  }

  @override
  void recordSuccess() {
    _failureCount = 0;
    _nextRetryAt = null;
  }
}
