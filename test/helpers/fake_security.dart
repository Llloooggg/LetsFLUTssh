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

import 'package:letsflutssh/core/security/auto_lock_store.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/password_rate_limiter.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';

class FakeMasterPasswordManager extends MasterPasswordManager {
  bool enabled;
  Uint8List? derivedKey;
  bool verifyResult;

  FakeMasterPasswordManager({
    this.enabled = false,
    this.derivedKey,
    this.verifyResult = false,
  });

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<Uint8List> deriveKey(String password) async =>
      derivedKey ?? Uint8List(32);

  @override
  Future<bool> verify(String password) async => verifyResult;

  @override
  Future<Uint8List?> verifyAndDerive(
    String password, {
    bool useRateLimit = false,
  }) async => verifyResult ? (derivedKey ?? Uint8List(32)) : null;

  @override
  Future<Uint8List> enable(String password) async {
    enabled = true;
    return derivedKey ?? Uint8List(32);
  }

  @override
  Future<Uint8List> changePassword(String oldPwd, String newPwd) async =>
      derivedKey ?? Uint8List(32);

  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  Future<void> reset() async {
    enabled = false;
  }
}

class FakeSecureKeyStorage extends SecureKeyStorage {
  Uint8List? storedKey;
  Uint8List? biometricKey;
  KeyringProbeResult probeResult;
  bool available;
  bool writeKeySucceeds;

  FakeSecureKeyStorage({
    this.storedKey,
    this.biometricKey,
    this.probeResult = KeyringProbeResult.available,
    this.available = true,
    this.writeKeySucceeds = true,
  });

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<KeyringProbeResult> probe() async => probeResult;

  @override
  Future<Uint8List?> readKey() async => storedKey;

  @override
  Future<bool> writeKey(Uint8List key) async {
    if (!writeKeySucceeds) return false;
    storedKey = key;
    return true;
  }

  @override
  Future<void> deleteKey() async {
    storedKey = null;
  }

  @override
  Future<bool> writeBiometricKey(Uint8List key) async {
    biometricKey = key;
    return true;
  }

  @override
  Future<Uint8List?> readBiometricKey() async => biometricKey;

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
  String? expectedPassword;

  FakeKeychainPasswordGate({this.configured = false, this.expectedPassword});

  @override
  Future<bool> isConfigured() async => configured;

  @override
  Future<void> setPassword(String password) async {
    configured = true;
    expectedPassword = password;
  }

  @override
  Future<bool> verify(String password) async =>
      configured && password == expectedPassword;

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

  FakeBiometricAuth({this.available = false, this.authenticateResult = false});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async => authenticateResult;
}

class FakeBiometricKeyVault extends BiometricKeyVault {
  bool stored;
  Uint8List? key;

  FakeBiometricKeyVault({this.stored = false, this.key});

  @override
  Future<bool> isStored() async => stored;

  @override
  Future<bool> store(Uint8List key) async {
    stored = true;
    this.key = key;
    return true;
  }

  @override
  Future<Uint8List?> read() async => stored ? key : null;
}

/// In-memory AutoLockStore that never touches a DB.
///
/// The real store reads / writes through `AppDatabase.configDao`;
/// tests that drive `_markSecurityReady` (which calls
/// `autoLockMinutesProvider.load` → `AutoLockStore.load`) fail with
/// "Can't re-open a database" when the controller closed the last
/// DB the store was pointed at. Overriding with this fake keeps the
/// minutes as a Dart field so `setDatabase` is a no-op and the load
/// path is decoupled from the drift handle lifecycle.
class FakeAutoLockStore extends AutoLockStore {
  int minutes;

  FakeAutoLockStore({this.minutes = 0});

  @override
  Future<int> load() async => minutes;

  @override
  Future<void> save(int value) async {
    minutes = value;
  }
}
