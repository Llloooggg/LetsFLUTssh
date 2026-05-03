import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/src/rust/api/tier_unlock_orchestrator.dart'
    as rust_orch;

void main() {
  group('mapUnlockOutcome', () {
    test('Staged → staged', () {
      expect(
        mapUnlockOutcome(const rust_orch.DbUnlockOutcome.staged()),
        TierUnlockAttempt.staged,
      );
    });

    test('WrongSecret → wrongSecret', () {
      expect(
        mapUnlockOutcome(const rust_orch.DbUnlockOutcome.wrongSecret()),
        TierUnlockAttempt.wrongSecret,
      );
    });

    test('Cancelled → cancelled', () {
      expect(
        mapUnlockOutcome(const rust_orch.DbUnlockOutcome.cancelled()),
        TierUnlockAttempt.cancelled,
      );
    });

    test('PluginError(reason) collapses to error', () {
      // Plugin reason text is informational only — the dialog UI
      // does not differentiate plugin vs corruption errors. Pin
      // the contract.
      expect(
        mapUnlockOutcome(
          const rust_orch.DbUnlockOutcome.pluginError('keychain unreachable'),
        ),
        TierUnlockAttempt.error,
      );
    });

    test('Corruption(detail) collapses to error', () {
      expect(
        mapUnlockOutcome(
          const rust_orch.DbUnlockOutcome.corruption('hmac mismatch'),
        ),
        TierUnlockAttempt.error,
      );
    });
  });
}
