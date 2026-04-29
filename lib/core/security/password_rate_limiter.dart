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
/// **Backend selection.** Two implementations sit behind one façade:
/// the Rust [`persisted_rate_limit_actor`] (production: tokio actor
/// with periodic flush) and an inline Dart state-machine + per-write
/// disk chain (flutter_test: FRB native lib not loaded). The choice
/// is decided **once** at first init — a successful `actorInitOrGet`
/// pins the Rust backend; any failure (or sync entry before init)
/// falls into the Dart backend permanently. No mid-flight switching,
/// no per-call probe.
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

  /// Resolved on first call. `null` means undecided — the next
  /// `_ensureBackend` picks one (Rust if reachable, else Dart).
  _Backend? _backend;

  /// Force a re-read on next status call. Drops both backend
  /// caches; the next operation re-initialises.
  void invalidateCache() {
    final b = _backend;
    if (b is _RustBackend) {
      try {
        rust_persisted_actor.persistedRateLimitActorClear(id: _id);
      } catch (_) {
        // Actor unreachable — backend gets re-resolved on next call.
      }
    }
    _backend = null;
  }

  /// Awaits any pending save. Rust mode: the actor schedules writes
  /// via `tokio::spawn_blocking`; we yield twice to give the worker
  /// a chance to drain. Dart mode: await the in-memory chain.
  Future<void> awaitPendingSave() async {
    final b = _backend;
    if (b is _DartBackend) {
      await b.pendingSave;
    } else {
      await Future<void>.value();
      await Future<void>.value();
    }
  }

  @override
  RateLimitStatus status() {
    final b = _backend;
    if (b == null) {
      // Init hasn't settled yet (sync caller hit before
      // `statusAsync`). Return the safe baseline so the unlock
      // dialog renders no cooldown — `statusAsync` resolves the
      // backend and the next read shows the real state.
      return _zero;
    }
    return b.status(this);
  }

  /// Async variant — loads the on-disk frame (HMAC-verified) before
  /// snapshotting. The unlock dialog awaits this on open so the
  /// post-restart cooldown countdown lands on the first frame.
  Future<RateLimitStatus> statusAsync() async {
    await _ensureBackend();
    return status();
  }

  @override
  void recordFailure() {
    final b = _backend;
    if (b != null) {
      b.recordFailure(this);
      return;
    }
    // First call before `statusAsync` settled — try the Rust actor
    // direct (the call is itself the probe; success means Rust is
    // reachable and accepted the failure; failure means we adopt
    // the Dart backend permanently).
    try {
      rust_persisted_actor.persistedRateLimitActorRecordFailure(id: _id);
      _backend = _RustBackend();
    } catch (_) {
      final dart = _DartBackend(_hmacKey, _stateFile);
      _backend = dart;
      dart.recordFailure(this);
    }
  }

  @override
  void recordSuccess() {
    final b = _backend;
    if (b != null) {
      b.recordSuccess(this);
      return;
    }
    try {
      rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: _id);
      _backend = _RustBackend();
    } catch (_) {
      final dart = _DartBackend(_hmacKey, _stateFile);
      _backend = dart;
      dart.recordSuccess(this);
    }
  }

  Future<void> _ensureBackend() async {
    if (_backend != null) return;
    File? file;
    try {
      file = await _stateFile();
      await file.parent.create(recursive: true);
      rust_persisted_actor.persistedRateLimitActorInitOrGet(
        id: _id,
        filePath: file.path,
        hmacKey: _hmacKey,
      );
      _backend = _RustBackend();
      return;
    } catch (_) {
      // Rust actor unreachable, or the path_provider plugin is not
      // mocked (flutter_test contexts). Fall back to the inline Dart
      // backend so the limiter still functions in unit tests.
    }
    final dart = _DartBackend(_hmacKey, _stateFile);
    _backend = dart;
    if (file != null) {
      await dart.loadFromFile(file, this);
    }
  }

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
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

// ── Backend implementations ──────────────────────────────────────────

const _zero = RateLimitStatus(
  failureCount: 0,
  cooldownRemaining: Duration.zero,
);

/// PersistedRateLimiter backend — production (Rust actor) or
/// flutter_test (Dart in-memory + disk).
abstract class _Backend {
  RateLimitStatus status(PersistedRateLimiter outer);
  void recordFailure(PersistedRateLimiter outer);
  void recordSuccess(PersistedRateLimiter outer);
}

class _RustBackend extends _Backend {
  @override
  RateLimitStatus status(PersistedRateLimiter outer) {
    try {
      final s = rust_persisted_actor.persistedRateLimitActorStatus(
        id: outer._id,
      );
      final ms = s.cooldownRemainingMs.toInt();
      return RateLimitStatus(
        failureCount: s.failureCount.toInt(),
        cooldownRemaining: ms > 0 ? Duration(milliseconds: ms) : Duration.zero,
      );
    } catch (_) {
      return _zero;
    }
  }

  @override
  void recordFailure(PersistedRateLimiter outer) {
    try {
      rust_persisted_actor.persistedRateLimitActorRecordFailure(id: outer._id);
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter Rust recordFailure failed: $e',
        name: 'PersistedRateLimiter',
      );
    }
  }

  @override
  void recordSuccess(PersistedRateLimiter outer) {
    try {
      rust_persisted_actor.persistedRateLimitActorRecordSuccess(id: outer._id);
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter Rust recordSuccess failed: $e',
        name: 'PersistedRateLimiter',
      );
    }
  }
}

class _DartBackend extends _Backend {
  _DartBackend(this._hmacKey, this._stateFile);

  final Uint8List _hmacKey;
  final Future<File> Function() _stateFile;

  int _failureCount = 0;
  DateTime? _nextRetryAt;
  bool _loaded = false;
  Future<void> pendingSave = Future<void>.value();

  Future<void> loadFromFile(File file, PersistedRateLimiter outer) async {
    if (_loaded) return;
    try {
      if (!await file.exists()) {
        _loaded = true;
        return;
      }
      final raw = await file.readAsBytes();
      final decoded = persistedRateLimitDecodeCompat(raw, _hmacKey);
      if (decoded == null) {
        // HMAC mismatch — clamp to max cooldown.
        _failureCount = PasswordRateLimiter.backoffSchedule.length - 1;
        _nextRetryAt = outer._now().add(
          Duration(seconds: PasswordRateLimiter.backoffSchedule.last),
        );
      } else {
        final cap = PasswordRateLimiter.backoffSchedule.length - 1;
        _failureCount = decoded.failureCount.clamp(0, cap);
        _nextRetryAt = decoded.nextRetryAtMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(decoded.nextRetryAtMillis!);
      }
      _loaded = true;
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter Dart load failed: $e',
        name: 'PersistedRateLimiter',
      );
      _loaded = true;
    }
  }

  @override
  RateLimitStatus status(PersistedRateLimiter outer) {
    if (!_loaded) return _zero;
    return RateLimitStatus(
      failureCount: _failureCount,
      cooldownRemaining: outer._cooldownRemaining(_nextRetryAt),
    );
  }

  @override
  void recordFailure(PersistedRateLimiter outer) {
    final cap = PasswordRateLimiter.backoffSchedule.length - 1;
    final next = _failureCount + 1;
    _failureCount = next > cap ? cap : next;
    _nextRetryAt = outer._nextRetryAfterFailure(_failureCount);
    _loaded = true;
    _scheduleSave();
  }

  @override
  void recordSuccess(PersistedRateLimiter outer) {
    _failureCount = 0;
    _nextRetryAt = null;
    _loaded = true;
    _scheduleSave();
  }

  void _scheduleSave() {
    final snapshot = PersistedRateLimitState(
      failureCount: _failureCount,
      nextRetryAtMillis: _nextRetryAt?.millisecondsSinceEpoch,
    );
    pendingSave = pendingSave.catchError((_) {}).then((_) async {
      try {
        final file = await _stateFile();
        await file.parent.create(recursive: true);
        final bytes = persistedRateLimitEncodeCompat(snapshot, _hmacKey);
        await file.writeAsBytes(bytes, flush: true);
        await hardenFilePerms(file.path);
      } catch (e) {
        AppLogger.instance.log(
          'PersistedRateLimiter Dart save failed: $e',
          name: 'PersistedRateLimiter',
        );
      }
    });
  }
}
