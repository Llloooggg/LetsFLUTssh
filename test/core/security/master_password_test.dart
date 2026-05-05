import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/src/rust/api/master_password.dart' as rust_mp;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Single tmp for the whole file — `masterPasswordInit` pins the
  // support dir in a Rust OnceLock, so the first test wins. Per-test
  // tmp would silently route every later test through the first
  // tmp's state.
  late Directory tmp;
  late MasterPasswordManager mp;

  setUpAll(() async {
    await requireFrbLoaded();
    // Production Argon2id (46 MiB / 2 iter) takes ~250 ms per derive
    // on a fast laptop. Lower for the duration of this file.
    MasterPasswordManager.debugSetKdfParams(
      const KdfParams.argon2id(memoryKiB: 8, iterations: 1, parallelism: 1),
    );
    tmp = await Directory.systemTemp.createTemp('lfs_mp_');
    // Constructor `basePath:` bypasses `_getBasePath`'s init call;
    // pin the support dir manually so every op below routes through
    // the Rust singleton.
    rust_mp.masterPasswordInit(supportDir: tmp.path);
  });

  tearDownAll(() async {
    MasterPasswordManager.debugSetKdfParams(null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    mp = MasterPasswordManager(basePath: tmp.path);
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
      await mp.enable('correcthorse');
      expect(await mp.isEnabled(), isTrue);
    });

    test('flips back to false after disable', () async {
      await mp.enable('correcthorse');
      await mp.disable();
      expect(await mp.isEnabled(), isFalse);
    });
  });

  group('enable', () {
    test('returns a 32-byte derived DB key', () async {
      final key = await mp.enable('correcthorse');
      expect(key.length, 32);
    });

    test('writes credentials.kdf so isEnabled reports true', () async {
      await mp.enable('correcthorse');
      expect(File('${tmp.path}/credentials.kdf').existsSync(), isTrue);
    });

    test('re-enable overwrites the verifier with a new password', () async {
      final firstKey = await mp.enable('correcthorse');
      // Rust shim allows enable to re-run — useful for the "user
      // changed their mind during first-launch wizard" path.
      final secondKey = await mp.enable('different-password');
      expect(secondKey.length, 32);
      // New salt → new key bytes (overwhelmingly likely).
      expect(secondKey, isNot(equals(firstKey)));
      // The original password stops working.
      expect(await mp.verify('correcthorse'), isFalse);
      expect(await mp.verify('different-password'), isTrue);
    });
  });

  group('verify / verifyAndDerive', () {
    test(
      'returns true / non-null derived key for the right password',
      () async {
        final enableKey = await mp.enable('correcthorse');
        expect(await mp.verify('correcthorse'), isTrue);
        final derived = await mp.verifyAndDerive('correcthorse');
        expect(derived, isNotNull);
        expect(derived!.length, 32);
        // Same password → same derived key (Argon2id is deterministic
        // for fixed salt + params).
        expect(derived, enableKey);
      },
    );

    test('returns false / null for the wrong password', () async {
      await mp.enable('correcthorse');
      expect(await mp.verify('wrongpass'), isFalse);
      expect(await mp.verifyAndDerive('wrongpass'), isNull);
    });

    test('verifyAndDerive on a never-enabled vault throws', () async {
      // Rust raises "Master password is not enabled" when no KDF
      // file is present. The unlock UI keys off `isEnabled` first
      // and never reaches `verifyAndDerive` in that state.
      expect(() => mp.verifyAndDerive('anything'), throwsA(anything));
    });
  });

  group('changePassword', () {
    test('returns a fresh 32-byte key + verifies new password', () async {
      final originalKey = await mp.enable('old');
      final newKey = await mp.changePassword('old', 'new');

      expect(newKey.length, 32);
      // Salt rotates on changePassword → new key bytes differ from
      // the original (overwhelmingly likely; salt is OsRng-fresh).
      expect(newKey, isNot(equals(originalKey)));
      expect(await mp.verify('new'), isTrue);
    });

    test('throws on wrong old password', () async {
      await mp.enable('old');
      // Rust surfaces the wrong-old failure as a typed FRB error
      // (not the AnyhowException the Dart wrapper rebrands), so the
      // assertion accepts any throw — the contract callers care
      // about is "operation fails", not the specific type.
      expect(() => mp.changePassword('wrong-old', 'new'), throwsA(anything));
    });
  });

  group('disable', () {
    test('flips isEnabled back to false', () async {
      await mp.enable('old');
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
      await mp.enable('correcthorse');
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
        basePath: tmp.path,
        rateLimiter: limiter,
      );
      await mp2.enable('p');
      // Limiter is "locked" → unlockAttempt short-circuits.
      final outcome = await mp2.unlockAttempt('p');
      expect(outcome, TierUnlockAttempt.wrongSecret);
      // The orchestrator wasn't called — recordSuccess / recordFailure
      // weren't invoked.
      expect(limiter.successCalls, 0);
      expect(limiter.failureCalls, 0);
    });
  });

  group('MasterPasswordException', () {
    test('toString exposes the underlying message', () {
      const e = MasterPasswordException('something specific');
      expect(e.toString(), contains('something specific'));
    });
  });
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
