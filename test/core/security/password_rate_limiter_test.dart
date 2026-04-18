import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';

void main() {
  group('InMemoryRateLimiter', () {
    test('fresh limiter is unlocked with zero failures', () {
      final limiter = InMemoryRateLimiter();
      final status = limiter.status();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });

    test('first failure = 1 s cooldown per backoff schedule', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = InMemoryRateLimiter(now: () => clock);
      limiter.recordFailure();
      final status = limiter.status();
      expect(status.failureCount, 1);
      expect(status.isLocked, isTrue);
      expect(status.cooldownRemaining!.inSeconds, 1);
    });

    test('second failure = 2 s, third = 4 s — exponential growth', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = InMemoryRateLimiter(now: () => clock);
      limiter.recordFailure();
      limiter.recordFailure();
      expect(limiter.status().cooldownRemaining!.inSeconds, 2);
      limiter.recordFailure();
      expect(limiter.status().cooldownRemaining!.inSeconds, 4);
    });

    test('cooldown clears once time passes', () {
      var clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = InMemoryRateLimiter(now: () => clock);
      limiter.recordFailure();
      expect(limiter.status().isLocked, isTrue);
      clock = clock.add(const Duration(seconds: 2));
      expect(limiter.status().isLocked, isFalse);
    });

    test('backoff is capped at the last schedule entry (60 s)', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = InMemoryRateLimiter(now: () => clock);
      for (var i = 0; i < 100; i++) {
        limiter.recordFailure();
      }
      expect(limiter.status().cooldownRemaining!.inSeconds, 60);
    });

    test('recordSuccess resets counter and clears cooldown', () {
      final clock = DateTime(2026, 1, 1, 12, 0, 0);
      final limiter = InMemoryRateLimiter(now: () => clock);
      limiter.recordFailure();
      limiter.recordFailure();
      expect(limiter.status().isLocked, isTrue);
      limiter.recordSuccess();
      expect(limiter.status().failureCount, 0);
      expect(limiter.status().isLocked, isFalse);
    });
  });
}
