/// In-memory fakes for the `core/security` classes used across the
/// app startup / unlock / first-launch flows. Every fake is a
/// subclass that overrides the async surface with deterministic,
/// filesystem-free defaults; tests that need richer behaviour pass
/// a `FakeXxx()..someField = ...` to the `test_providers`
/// factory or swap in a hand-rolled mock.
///
/// Keep the defaults no-op friendly:
/// - `isStored` / `isConfigured` / `isAvailable` → false
/// - `store` / `write` → true (success)
/// - `read` → null (nothing stored)
/// - `verify` → false (wrong password)
/// - `clear` / `delete` → void no-op
///
/// This way a test that does not override a method cannot be
/// surprised by a branch it did not opt into.
library;

import 'dart:typed_data';

import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/tier_unlock_attempt.dart';
import 'package:letsflutssh/src/rust/api/security_capabilities.dart'
    show DbKeyringProbeResult;
import 'package:letsflutssh/providers/auto_lock_provider.dart';

class FakeMasterPasswordManager extends MasterPasswordManager {
  bool enabled;
  Uint8List? derivedKey;
  bool verifyResult;

  /// Queued outcomes for [unlockAttempt]. Each call dequeues one;
  /// the queue running dry returns [TierUnlockAttempt.error] so
  /// callers that didn't pre-stage anything fail loud rather than
  /// silently accept. Records every supplied password into
  /// [unlockAttemptCalls] so tests assert on the exact value the
  /// dialog handed in.
  final List<TierUnlockAttempt> unlockOutcomes;
  final List<Uint8List> unlockAttemptCalls = [];

  /// Static rate-limit status returned by [rateLimitStatus]. Tests
  /// that need a state machine (e.g. "lock after the next failed
  /// attempt") swap [statusAfterFailure] in or assign [_status]
  /// directly between operations.
  RateLimitStatus _status;
  final RateLimitStatus? statusAfterFailure;

  FakeMasterPasswordManager({
    this.enabled = false,
    this.derivedKey,
    this.verifyResult = false,
    List<TierUnlockAttempt>? unlockOutcomes,
    RateLimitStatus initialStatus = const RateLimitStatus(
      failureCount: 0,
      cooldownRemaining: Duration.zero,
    ),
    this.statusAfterFailure,
  }) : unlockOutcomes = unlockOutcomes ?? [],
       _status = initialStatus,
       super(basePath: '/tmp/fake-master-password');

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> verify(Uint8List password) async => verifyResult;

  @override
  Future<Uint8List?> verifyAndDerive(Uint8List password) async =>
      verifyResult ? (derivedKey ?? Uint8List(32)) : null;

  @override
  Future<Uint8List> enable(Uint8List password) async {
    enabled = true;
    return derivedKey ?? Uint8List(32);
  }

  @override
  Future<Uint8List> changePassword(Uint8List oldPwd, Uint8List newPwd) async =>
      derivedKey ?? Uint8List(32);

  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  Future<void> reset() async {
    enabled = false;
  }

  @override
  RateLimitStatus rateLimitStatus() => _status;

  /// Override the limiter snapshot — tests that drive a dialog
  /// through "first attempt clean, second attempt locked" mutate
  /// this directly between submits.
  void setStatus(RateLimitStatus status) {
    _status = status;
  }

  @override
  Future<TierUnlockAttempt> unlockAttempt(Uint8List password) async {
    unlockAttemptCalls.add(password);
    final next = unlockOutcomes.isNotEmpty
        ? unlockOutcomes.removeAt(0)
        : TierUnlockAttempt.error;
    if (next == TierUnlockAttempt.wrongSecret && statusAfterFailure != null) {
      _status = statusAfterFailure!;
    }
    return next;
  }
}

class FakeSecureKeyStorage extends SecureKeyStorage {
  Uint8List? storedKey;
  Uint8List? biometricKey;
  DbKeyringProbeResult probeResult;
  bool available;
  bool writeKeySucceeds;

  FakeSecureKeyStorage({
    this.storedKey,
    this.biometricKey,
    this.probeResult = DbKeyringProbeResult.available,
    this.available = true,
    this.writeKeySucceeds = true,
  });

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<DbKeyringProbeResult> probe() async => probeResult;

  @override
  Future<bool> writeKeyFromSecret(String secretId) async {
    if (!writeKeySucceeds) return false;
    storedKey = Uint8List(32);
    return true;
  }

  @override
  Future<bool> readKeyToSecret(String secretId) async => storedKey != null;

  @override
  Future<void> deleteKey() async {
    storedKey = null;
  }

  @override
  Future<void> deleteBiometricKey() async {
    biometricKey = null;
  }
}

class FakeHardwareTierVault extends HardwareTierVault {
  bool stored;
  Uint8List? dbKey;
  bool available;
  String probeCode;
  bool storeSucceeds;

  FakeHardwareTierVault({
    this.stored = false,
    this.dbKey,
    this.available = false,
    this.probeCode = 'unknown',
    this.storeSucceeds = true,
  });

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> probeDetail() async => probeCode;

  @override
  Future<bool> isStored() async => stored;

  @override
  Future<bool> store({required Uint8List dbKey, String? pin}) async {
    if (!storeSucceeds) return false;
    stored = true;
    this.dbKey = dbKey;
    return true;
  }

  @override
  Future<Uint8List?> read(String? pin) async => stored ? dbKey : null;

  @override
  Future<void> clear() async {
    stored = false;
    dbKey = null;
  }
}

class FakeKeychainPasswordGate extends KeychainPasswordGate {
  bool configured;
  Uint8List? expectedPassword;

  FakeKeychainPasswordGate({this.configured = false, this.expectedPassword});

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<void> setPassword(Uint8List password) async {
    configured = true;
    expectedPassword = password;
  }

  @override
  Future<bool> verify(Uint8List password) async {
    if (!configured) return false;
    final expected = expectedPassword;
    if (expected == null || expected.length != password.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (expected[i] != password[i]) return false;
    }
    return true;
  }

  @override
  Future<PasswordRateLimiter?> rateLimiter() async => null;

  @override
  Future<void> clear() async {
    configured = false;
    expectedPassword = null;
  }
}

class FakeBiometricAuth extends BiometricAuth {
  bool available;
  bool authenticateResult;

  /// When non-null, [isAvailable] returns `false` on the first N calls
  /// and then flips to [available]. Lets tests drive the rare shape
  /// where the pre-dialog biometric branch must be skipped but the
  /// in-dialog biometric closure's probe should still succeed —
  /// otherwise the two share provider state and fire identically.
  int? skipFirstNAvailableCalls;
  int _availableCalls = 0;

  FakeBiometricAuth({
    this.available = false,
    this.authenticateResult = false,
    this.skipFirstNAvailableCalls,
  });

  @override
  Future<bool> isAvailable() async {
    _availableCalls++;
    final skip = skipFirstNAvailableCalls;
    if (skip != null && _availableCalls <= skip) return false;
    return available;
  }

  @override
  Future<bool> authenticate(String reason) async => authenticateResult;
}

class FakeBiometricKeyVault extends BiometricKeyVault {
  bool stored;

  /// When non-null, [isStored] throws with this error ONLY after the
  /// first N successful calls. Lets tests drive the in-dialog
  /// `_biometricUnlockForTierDialog` catch arm without breaking the
  /// pre-dialog biometric probe that reads the same fake instance.
  Object? isStoredThrows;
  int throwAfterNCalls;
  int _isStoredCalls = 0;

  FakeBiometricKeyVault({
    this.stored = false,
    this.isStoredThrows,
    this.throwAfterNCalls = 0,
  });

  @override
  Future<bool> isStored() async {
    _isStoredCalls++;
    final e = isStoredThrows;
    if (e != null && _isStoredCalls > throwAfterNCalls) throw e;
    return stored;
  }

  @override
  Future<bool> storeFromActive() async {
    stored = true;
    return true;
  }

  @override
  Future<bool> storeFromSecret(String secretId) async {
    stored = true;
    return true;
  }

  @override
  Future<bool> readToActive() async => stored;

  @override
  Future<void> clear() async {
    stored = false;
  }
}

/// In-memory [AutoLockMinutesNotifier] that never touches the DB.
///
/// The real notifier reads / writes through `lfs_core.db`; tests that
/// drive `_markSecurityReady` (which calls `autoLockMinutesProvider
/// .load`) would otherwise hit FRB and fail. Overriding with this
/// fake keeps the minutes in `state` so the load path is decoupled
/// from the FRB native lib.
class FakeAutoLockNotifier extends AutoLockMinutesNotifier {
  FakeAutoLockNotifier({this.initialMinutes = 0});

  final int initialMinutes;

  @override
  int build() => initialMinutes;

  @override
  Future<void> load() async {
    state = initialMinutes;
  }

  @override
  Future<void> set(int minutes) async {
    state = minutes;
  }
}
