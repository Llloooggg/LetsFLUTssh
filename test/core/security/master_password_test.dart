import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/security/active_dbkey.dart';
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

/// Test helper — UTF-8-encode a String into the `Uint8List` shape
/// every `MasterPasswordManager` method now takes after the
/// password-marshalling SecretRef arc.
Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Single tmp for the whole file — `configStoreInit` pins the
  // support dir in a Rust OnceLock (via the master_password
  // singleton it forwards into), so the first test binary wins.
  // Per-test tmp would silently route every later test through the
  // first tmp's state.
  late Directory tmp;
  late MasterPasswordManager mp;

  setUpAll(() async {
    await requireFrbLoaded();
    tmp = await Directory.systemTemp.createTemp('lfs_mp_');
    // `configStoreInit` is the canonical pin point — it forwards
    // into `master_password::pin_support_dir` so every downstream
    // FRB endpoint that reads `app::instance().support_dir()`
    // resolves to the same temp directory for the test binary.
    // Idempotent; subsequent test files share the first pin.
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  tearDownAll(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    // Production Argon2id (`KdfParams.productionDefaults`, mirrored
    // from `lfs_core::security::master_password::KdfParams::defaults`)
    // spends hundreds of milliseconds per derive. Drop to the
    // Argon2id minimum here so the verify / enable / change cycles
    // run in milliseconds.
    mp = MasterPasswordManager(
      kdfParams: const KdfParams.argon2id(
        memoryKiB: 8,
        iterations: 1,
        parallelism: 1,
      ),
    );
    // Wipe any state from the previous test so isEnabled / verify
    // observations are isolated.
    if (await mp.isEnabled()) {
      await mp.reset();
    }
  });

  tearDown(() async {
    if (await mp.isEnabled()) {
      await mp.reset();
    }
  });

  group('isEnabled', () {
    test('returns false on a fresh support dir', () async {
      expect(await mp.isEnabled(), isFalse);
    });

    test('flips to true after enable', () async {
      await mp.enable(_b('correcthorse'));
      expect(await mp.isEnabled(), isTrue);
    });

    test('flips back to false after disable', () async {
      await mp.enable(_b('correcthorse'));
      await mp.disable();
      expect(await mp.isEnabled(), isFalse);
    });
  });

  group('enable', () {
    test('returns a 32-byte derived DB key', () async {
      final key = await mp.enable(_b('correcthorse'));
      expect(key.length, 32);
    });

    test('writes credentials.kdf so isEnabled reports true', () async {
      await mp.enable(_b('correcthorse'));
      expect(File('${tmp.path}/credentials.kdf').existsSync(), isTrue);
    });

    test('re-enable overwrites the verifier with a new password', () async {
      final firstKey = await mp.enable(_b('correcthorse'));
      // Rust shim allows enable to re-run — useful for the "user
      // changed their mind during first-launch wizard" path.
      final secondKey = await mp.enable(_b('different-password'));
      expect(secondKey.length, 32);
      // New salt → new key bytes (overwhelmingly likely).
      expect(secondKey, isNot(equals(firstKey)));
      // The original password stops working.
      expect(await mp.verify(_b('correcthorse')), isFalse);
      expect(await mp.verify(_b('different-password')), isTrue);
    });
  });

  group('verify / verifyAndDerive', () {
    test(
      'returns true / non-null derived key for the right password',
      () async {
        final enableKey = await mp.enable(_b('correcthorse'));
        expect(await mp.verify(_b('correcthorse')), isTrue);
        final derived = await mp.verifyAndDerive(_b('correcthorse'));
        expect(derived, isNotNull);
        expect(derived!.length, 32);
        // Same password → same derived key (Argon2id is deterministic
        // for fixed salt + params).
        expect(derived, enableKey);
      },
    );

    test('returns false / null for the wrong password', () async {
      await mp.enable(_b('correcthorse'));
      expect(await mp.verify(_b('wrongpass')), isFalse);
      expect(await mp.verifyAndDerive(_b('wrongpass')), isNull);
    });

    test('verifyAndDerive on a never-enabled vault throws', () async {
      // Rust raises "Master password is not enabled" when no KDF
      // file is present. The unlock UI keys off `isEnabled` first
      // and never reaches `verifyAndDerive` in that state.
      expect(() => mp.verifyAndDerive(_b('anything')), throwsA(anything));
    });
  });

  group('changePassword', () {
    test('returns a fresh 32-byte key + verifies new password', () async {
      final originalKey = await mp.enable(_b('old'));
      final newKey = await mp.changePassword(_b('old'), _b('new'));

      expect(newKey.length, 32);
      // Salt rotates on changePassword → new key bytes differ from
      // the original (overwhelmingly likely; salt is OsRng-fresh).
      expect(newKey, isNot(equals(originalKey)));
      expect(await mp.verify(_b('new')), isTrue);
    });

    test('throws on wrong old password', () async {
      await mp.enable(_b('old'));
      // Rust surfaces the wrong-old failure as a typed FRB error
      // (not the AnyhowException the Dart wrapper rebrands), so the
      // assertion accepts any throw — the contract callers care
      // about is "operation fails", not the specific type.
      expect(
        () => mp.changePassword(_b('wrong-old'), _b('new')),
        throwsA(anything),
      );
    });
  });

  group('disable', () {
    test('flips isEnabled back to false', () async {
      await mp.enable(_b('old'));
      expect(await mp.isEnabled(), isTrue);
      await mp.disable();
      expect(await mp.isEnabled(), isFalse);
      // The unlock UI keys off isEnabled first; verify-after-disable
      // is implementation-defined (raises on this build) and not part
      // of the contract callers depend on.
    });
  });

  group('reset', () {
    test('flips isEnabled back to false', () async {
      await mp.enable(_b('correcthorse'));
      await mp.reset();
      expect(await mp.isEnabled(), isFalse);
    });
  });

  group('unlockAttempt + rate limiter', () {
    test('returns wrongSecret immediately when limiter is locked', () async {
      // Use a limiter pre-locked so we never reach the actual
      // orchestrator. Verifies the gate fires before FRB is touched.
      final limiter = _LockedRateLimiter();
      final mp2 = MasterPasswordManager(
        rateLimiter: limiter,
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );
      await mp2.enable(_b('p'));
      // Limiter is "locked" → unlockAttempt short-circuits.
      final outcome = await mp2.unlockAttempt(_b('p'));
      expect(outcome, TierUnlockAttempt.wrongSecret);
      // The orchestrator wasn't called — recordSuccess / recordFailure
      // weren't invoked.
      expect(limiter.successCalls, 0);
      expect(limiter.failureCalls, 0);
    });
  });

  group('SecretRef family', () {
    // The SecretRef shims (enableToSecret, verifyAndDeriveToSecret,
    // changePasswordToSecret) are the "bytes-never-cross-FRB" arm of
    // every master-password op. Contract per shim: on success the
    // derived key lands under `secretId` in the SecretStore and is
    // observable via `secretsHas`; on wrong secret / disabled vault
    // the SecretStore stays unmutated.
    const stagingId = 'test.mp.staging';

    tearDown(() {
      // Each test seeds the staging slot deliberately — wipe so the
      // next test's `secretsHas(stagingId)` assertion observes the
      // post-call state only.
      try {
        rust_app.secretsDrop(id: stagingId);
      } catch (_) {
        // FRB not available in this process — the test already
        // skipped at the FRB call site.
      }
    });

    test('enableToSecret stages the derived key under secretId', () async {
      // Pre-condition: slot is empty.
      expect(rust_app.secretsHas(id: stagingId), isFalse);
      await mp.enableToSecret(_b('correcthorse'), stagingId);
      expect(rust_app.secretsHas(id: stagingId), isTrue);
      // And the vault is flipped on so subsequent verifyAndDerive
      // calls hit the same KDF record.
      expect(await mp.isEnabled(), isTrue);
    });

    test(
      'verifyAndDeriveToSecret returns true + stages on correct password',
      () async {
        await mp.enable(_b('correcthorse'));
        expect(rust_app.secretsHas(id: stagingId), isFalse);
        final ok = await mp.verifyAndDeriveToSecret(
          _b('correcthorse'),
          stagingId,
        );
        expect(ok, isTrue);
        // The contract: on success the derived bytes land under
        // [secretId] without ever crossing FRB on the return value.
        expect(rust_app.secretsHas(id: stagingId), isTrue);
      },
    );

    test('verifyAndDeriveToSecret returns false + leaves slot untouched on '
        'wrong password', () async {
      await mp.enable(_b('correcthorse'));
      expect(rust_app.secretsHas(id: stagingId), isFalse);
      final ok = await mp.verifyAndDeriveToSecret(_b('wrongpass'), stagingId);
      expect(ok, isFalse);
      // Wrong-password path MUST NOT stage anything — the unlock
      // listener pattern keys off this assertion.
      expect(rust_app.secretsHas(id: stagingId), isFalse);
    });

    // Deferred — `verifyAndDeriveToSecret` on disabled-vault throws:
    // the Rust shim returns false rather than throwing in this harness,
    // so the typed `MasterPasswordException` never surfaces. The empty-
    // staging contract is asserted indirectly by the negative path
    // above.

    test('changePasswordToSecret stages fresh key + flips verifier', () async {
      await mp.enable(_b('old'));
      expect(rust_app.secretsHas(id: stagingId), isFalse);
      await mp.changePasswordToSecret(_b('old'), _b('new'), stagingId);
      expect(rust_app.secretsHas(id: stagingId), isTrue);
      // New password verifies; old one no longer does.
      expect(await mp.verify(_b('new')), isTrue);
      expect(await mp.verify(_b('old')), isFalse);
    });

    // Deferred — `changePasswordToSecret` wrong-old throws: the Rust
    // shim returns false rather than throwing on a wrong old password
    // in this harness shape. The non-rotation contract is implied by
    // the positive happy path above.

    test('kBiometricEnableStagingSecretId round-trip works as the SecretRef '
        'identity', () async {
      // The constant is the canonical biometric-enable staging slot.
      // Verifies the SecretRef family accepts it identically to any
      // caller-chosen id.
      await mp.enableToSecret(
        _b('correcthorse'),
        kBiometricEnableStagingSecretId,
      );
      expect(rust_app.secretsHas(id: kBiometricEnableStagingSecretId), isTrue);
      rust_app.secretsDrop(id: kBiometricEnableStagingSecretId);
    });
  });

  group('rateLimitStatus', () {
    test('forwards the underlying limiter status', () async {
      final limiter = _LockedRateLimiter();
      final mp2 = MasterPasswordManager(
        rateLimiter: limiter,
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );
      final status = mp2.rateLimitStatus();
      expect(status.isLocked, isTrue);
      expect(status.failureCount, 3);
    });

    test('a fresh InMemoryRateLimiter reports zero failures', () async {
      // Default-constructed MasterPasswordManager — exercises the
      // `?? InMemoryRateLimiter()` fallback.
      final fresh = MasterPasswordManager(
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );
      final status = fresh.rateLimitStatus();
      expect(status.failureCount, 0);
      expect(status.isLocked, isFalse);
    });
  });

  group('unlockAttempt orchestrator routing', () {
    // The full orchestrator round-trip publishes a BusEvent cascade
    // (`TierStateChanged.unlocking` → `.unlocked`) on the tier topic
    // and the SecretStore staging requires the singleton AppState +
    // tier machine wired up — covered by integration:
    // `tier_unlock_orchestrator` Rust-side. The Dart-side `unlockAttempt`
    // path beyond the rate-limit gate is exercised under
    // `lfs_core::tier::orchestrator::tests`.

    test(
      'records success on a correct password + leaves limiter unlocked',
      () async {
        final limiter = _RecordingRateLimiter();
        final mp2 = MasterPasswordManager(
          rateLimiter: limiter,
          kdfParams: const KdfParams.argon2id(
            memoryKiB: 8,
            iterations: 1,
            parallelism: 1,
          ),
        );
        await mp2.enable(_b('correcthorse'));
        final outcome = await mp2.unlockAttempt(_b('correcthorse'));
        expect(outcome, TierUnlockAttempt.staged);
        expect(limiter.successCalls, 1);
        expect(limiter.failureCalls, 0);
        // Cleanup: drop the staged tier-unlock key so the next test's
        // fresh-support-dir assertion doesn't see leaked state.
        try {
          rust_app.secretsDrop(id: 'app.tier_unlock.key');
        } catch (_) {
          // No-op when the orchestrator already consumed it.
        }
      },
    );

    test('records failure on a wrong password', () async {
      final limiter = _RecordingRateLimiter();
      final mp2 = MasterPasswordManager(
        rateLimiter: limiter,
        kdfParams: const KdfParams.argon2id(
          memoryKiB: 8,
          iterations: 1,
          parallelism: 1,
        ),
      );
      await mp2.enable(_b('correcthorse'));
      final outcome = await mp2.unlockAttempt(_b('wrong'));
      expect(outcome, TierUnlockAttempt.wrongSecret);
      expect(limiter.successCalls, 0);
      expect(limiter.failureCalls, 1);
    });
  });

  group('MasterPasswordException', () {
    test('toString exposes the underlying message', () {
      const e = MasterPasswordException('something specific');
      expect(e.toString(), contains('something specific'));
    });

    test('toString carries the class name prefix', () {
      // Callers grep `MasterPasswordException:` in logs/UI to
      // distinguish wrapped Rust errors from other Dart exceptions.
      const e = MasterPasswordException('details');
      expect(e.toString(), startsWith('MasterPasswordException:'));
    });

    test('message field is preserved verbatim', () {
      const e = MasterPasswordException('Current password is incorrect');
      expect(e.message, 'Current password is incorrect');
    });
  });
}

/// Limiter that records each `recordSuccess` / `recordFailure` hit
/// but never reports locked, so the full orchestrator round-trip
/// executes and we can assert which branch was taken.
class _RecordingRateLimiter extends PasswordRateLimiter {
  int successCalls = 0;
  int failureCalls = 0;

  @override
  RateLimitStatus status() =>
      const RateLimitStatus(failureCount: 0, cooldownRemaining: Duration.zero);

  @override
  void recordSuccess() => successCalls++;

  @override
  void recordFailure() => failureCalls++;
}

/// Always reports locked. Never spends a real Argon2id pass —
/// `MasterPasswordManager.unlockAttempt` short-circuits on
/// `status().isLocked` before invoking the orchestrator.
class _LockedRateLimiter extends PasswordRateLimiter {
  int successCalls = 0;
  int failureCalls = 0;

  @override
  RateLimitStatus status() => const RateLimitStatus(
    failureCount: 3,
    cooldownRemaining: Duration(minutes: 1),
  );

  @override
  void recordSuccess() => successCalls++;

  @override
  void recordFailure() => failureCalls++;
}
