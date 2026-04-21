import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/file_utils.dart';
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
/// record to disk (used by L2 keychain-with-password, where the
/// wrap-less check would otherwise permit immediate retry after a
/// relaunch).
abstract class PasswordRateLimiter {
  /// Seconds to wait between attempts after N consecutive failures.
  /// Index 0 = "no failures yet, no wait"; index 1 = "one failure,
  /// wait 1 s"; every index above that doubles up to the cap.
  static const List<int> backoffSchedule = [0, 1, 2, 4, 8, 16, 32, 60, 60, 60];

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
class InMemoryRateLimiter extends PasswordRateLimiter {
  InMemoryRateLimiter({super.now});

  int _failureCount = 0;
  DateTime? _nextRetryAt;

  @override
  RateLimitStatus status() => RateLimitStatus(
    failureCount: _failureCount,
    cooldownRemaining: _cooldownRemaining(_nextRetryAt),
  );

  @override
  void recordFailure() {
    _failureCount = math.min(
      _failureCount + 1,
      PasswordRateLimiter.backoffSchedule.length - 1,
    );
    _nextRetryAt = _nextRetryAfterFailure(_failureCount);
  }

  @override
  void recordSuccess() {
    _failureCount = 0;
    _nextRetryAt = null;
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
    super.now,
  }) : _hmacKey = hmacKey,
       _stateFile = stateFileFactory ?? _defaultStateFile;

  static const _fileName = 'rate_limit_state.bin';

  final Uint8List _hmacKey;
  final Future<File> Function() _stateFile;

  _RateState? _cached;
  bool _loaded = false;

  /// Serialises writes so two rapid-fire `recordFailure` /
  /// `recordSuccess` calls never race each other at the filesystem —
  /// the second write always observes the first's completion even
  /// though neither is awaited by the caller.
  Future<void> _pendingSave = Future<void>.value();

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Force an on-disk read on the next [status] call. Primarily
  /// exists for tests that edit the state file behind the limiter's
  /// back to simulate tamper.
  void invalidateCache() {
    _cached = null;
    _loaded = false;
  }

  /// Awaits the currently-pending save chain so a test can assert
  /// post-write invariants deterministically. Production callers
  /// never need this — the unlock flow is fine with fire-and-forget.
  Future<void> awaitPendingSave() => _pendingSave;

  @override
  RateLimitStatus status() {
    // Returning a synchronous snapshot is required by the base-class
    // contract; `statusAsync` runs the disk read + HMAC verify.
    if (!_loaded) {
      return const RateLimitStatus(
        failureCount: 0,
        cooldownRemaining: Duration.zero,
      );
    }
    final state = _cached;
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

  /// Async variant that loads + HMAC-verifies the on-disk state.
  /// Callers on the unlock path should await this before rendering a
  /// cooldown countdown.
  Future<RateLimitStatus> statusAsync() async {
    await _ensureLoaded();
    return status();
  }

  @override
  void recordFailure() {
    final current = _cached ?? const _RateState(failureCount: 0);
    final nextCount = math.min(
      current.failureCount + 1,
      PasswordRateLimiter.backoffSchedule.length - 1,
    );
    final nextRetryAt = _nextRetryAfterFailure(nextCount);
    final state = _RateState(failureCount: nextCount, nextRetryAt: nextRetryAt);
    _cached = state;
    _loaded = true;
    _unawaitedSave(state);
  }

  @override
  void recordSuccess() {
    _cached = const _RateState(failureCount: 0);
    _loaded = true;
    _unawaitedSave(_cached!);
  }

  /// Kicks off the disk write without awaiting. A persist failure is
  /// logged but never blocks the unlock flow — worst case is the
  /// counter drops on restart, which is a smaller loss than a failed
  /// password field. Writes are chained on `_pendingSave` so a
  /// sequence of `recordFailure; recordSuccess` always lands as two
  /// sequential writes rather than a race.
  void _unawaitedSave(_RateState state) {
    _pendingSave = _pendingSave.catchError((_) {}).then((_) async {
      try {
        final file = await _stateFile();
        await file.parent.create(recursive: true);
        final bytes = _encode(state);
        await file.writeAsBytes(bytes, flush: true);
        await hardenFilePerms(file.path);
      } catch (e) {
        AppLogger.instance.log(
          'PersistedRateLimiter save failed: $e',
          name: 'PersistedRateLimiter',
        );
      }
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final file = await _stateFile();
      if (!await file.exists()) {
        _cached = const _RateState(failureCount: 0);
        _loaded = true;
        return;
      }
      final raw = await file.readAsBytes();
      final decoded = _decode(raw);
      if (decoded == null) {
        // Tamper or corruption — treat as worst-case cooldown.
        _cached = _RateState(
          failureCount: PasswordRateLimiter.backoffSchedule.length - 1,
          nextRetryAt: _now().add(
            Duration(seconds: PasswordRateLimiter.backoffSchedule.last),
          ),
        );
        _loaded = true;
        AppLogger.instance.log(
          'PersistedRateLimiter state tampered or corrupt — max cooldown',
          name: 'PersistedRateLimiter',
        );
        return;
      }
      _cached = decoded;
      _loaded = true;
    } catch (e) {
      AppLogger.instance.log(
        'PersistedRateLimiter load failed: $e',
        name: 'PersistedRateLimiter',
      );
      _cached = const _RateState(failureCount: 0);
      _loaded = true;
    }
  }

  Uint8List _encode(_RateState state) {
    final payload = jsonEncode({
      'failure_count': state.failureCount,
      'next_retry_at_millis': state.nextRetryAt?.millisecondsSinceEpoch,
    });
    final payloadBytes = utf8.encode(payload);
    final hmac = Hmac(sha256, _hmacKey).convert(payloadBytes);
    final frame = jsonEncode({
      'payload': base64.encode(payloadBytes),
      'hmac': base64.encode(hmac.bytes),
    });
    return Uint8List.fromList(utf8.encode(frame));
  }

  _RateState? _decode(Uint8List bytes) {
    try {
      final frame = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final payloadB64 = frame['payload'];
      final hmacB64 = frame['hmac'];
      if (payloadB64 is! String || hmacB64 is! String) return null;
      final payloadBytes = base64.decode(payloadB64);
      final claimed = base64.decode(hmacB64);
      final expected = Hmac(sha256, _hmacKey).convert(payloadBytes).bytes;
      if (!_constantTimeEqual(claimed, expected)) return null;
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final failureCount = (payload['failure_count'] as num?)?.toInt() ?? 0;
      final retryMillis = (payload['next_retry_at_millis'] as num?)?.toInt();
      return _RateState(
        failureCount: failureCount.clamp(
          0,
          PasswordRateLimiter.backoffSchedule.length - 1,
        ),
        nextRetryAt: retryMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(retryMillis),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
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
    _failureCount = math.min(
      _failureCount + 1,
      PasswordRateLimiter.backoffSchedule.length - 1,
    );
    _nextRetryAt = _nextRetryAfterFailure(_failureCount);
  }

  @override
  void recordSuccess() {
    _failureCount = 0;
    _nextRetryAt = null;
  }
}
