/// Shared test fixture — common provider overrides for tests that
/// need to construct a [ProviderContainer] without spinning up real
/// path_provider / flutter_secure_storage / platform channels.
///
/// Usage:
///
/// ```dart
/// test('my controller does X', () {
///   final container = makeTestProviderContainer();
///   addTearDown(container.dispose);
///   // Grab the fakes back out by name when you need to assert on
///   // them:
///   final mpm = container.read(masterPasswordProvider)
///       as FakeMasterPasswordManager;
///   expect(mpm.enabled, isFalse);
/// });
/// ```
///
/// The factory ships sensible defaults for every Riverpod provider
/// the security / session / main-shell paths touch. Defaults are
/// no-op friendly (nothing stored, nothing available, verify
/// returns false). Tests that need richer behaviour pass a
/// preconfigured `FakeXxx()` into the corresponding named parameter.
///
/// Design principle — default overrides never hit the filesystem or
/// a platform channel. Tests that genuinely need real persistence
/// pass an `openTestDatabase()` handle via the corresponding
/// `setDatabase` store override after construction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/biometric_key_vault.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/keychain_password_gate.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import 'fake_security.dart';
import 'fake_session_store.dart';

/// Construct a [ProviderContainer] with the most common overrides
/// already applied.
///
/// Accepts optional positional [extraOverrides] so the caller can
/// tack on scenario-specific mocks (keychain gate returns isConfigured
/// true / hardware vault isStored false / etc.) without repeating
/// the baseline each time.
///
/// Every named param accepts a preconfigured fake; omit to get the
/// no-op default that does not touch disk or platform channels.
ProviderContainer makeTestProviderContainer({
  SessionStore? sessionStore,
  MasterPasswordManager? masterPassword,
  SecureKeyStorage? secureKeyStorage,
  HardwareTierVault? hardwareVault,
  KeychainPasswordGate? keychainGate,
  BiometricAuth? biometricAuth,
  BiometricKeyVault? biometricVault,
  List<Override> extraOverrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      masterPasswordProvider.overrideWithValue(
        masterPassword ?? FakeMasterPasswordManager(),
      ),
      secureKeyStorageProvider.overrideWithValue(
        secureKeyStorage ?? FakeSecureKeyStorage(),
      ),
      hardwareTierVaultProvider.overrideWithValue(
        hardwareVault ?? FakeHardwareTierVault(),
      ),
      keychainPasswordGateProvider.overrideWithValue(
        keychainGate ?? FakeKeychainPasswordGate(),
      ),
      biometricAuthProvider.overrideWithValue(
        biometricAuth ?? FakeBiometricAuth(),
      ),
      biometricKeyVaultProvider.overrideWithValue(
        biometricVault ?? FakeBiometricKeyVault(),
      ),
      ...extraOverrides,
    ],
  );
}
