import 'dart:math' as math;

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
