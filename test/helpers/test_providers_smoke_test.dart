import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import 'fake_security.dart';
import 'fake_session_store.dart';
import 'test_providers.dart';

void main() {
  group('makeTestProviderContainer', () {
    // Smoke tests for the shared fixture. The real payoff is tests
    // downstream (SecurityInitController, import_flow, settings
    // widgets) that lean on this factory — if the factory itself
    // broke they would all fail with cryptic provider-not-found
    // errors. Pinning the fixture shape here catches the breakage
    // at its source.

    test(
      'default container returns no-op fakes for every overridden provider',
      () {
        final c = makeTestProviderContainer();
        addTearDown(c.dispose);

        expect(c.read(sessionStoreProvider), isA<FakeSessionStore>());
        expect(
          c.read(masterPasswordProvider),
          isA<FakeMasterPasswordManager>(),
        );
        expect(c.read(secureKeyStorageProvider), isA<FakeSecureKeyStorage>());
        expect(c.read(hardwareTierVaultProvider), isA<FakeHardwareTierVault>());
        expect(
          c.read(keychainPasswordGateProvider),
          isA<FakeKeychainPasswordGate>(),
        );
        expect(c.read(biometricAuthProvider), isA<FakeBiometricAuth>());
        expect(c.read(biometricKeyVaultProvider), isA<FakeBiometricKeyVault>());
      },
    );

    test(
      'preconfigured master-password fake flows through the factory',
      () async {
        final mpm = FakeMasterPasswordManager(
          enabled: true,
          verifyResult: true,
        );
        final c = makeTestProviderContainer(masterPassword: mpm);
        addTearDown(c.dispose);

        final resolved = c.read(masterPasswordProvider);
        expect(resolved, same(mpm));
        expect(await resolved.isEnabled(), isTrue);
        expect(await resolved.verify('anything'), isTrue);
      },
    );

    test(
      'keychain gate fake honours verify against the stored password',
      () async {
        final gate = FakeKeychainPasswordGate();
        final c = makeTestProviderContainer(keychainGate: gate);
        addTearDown(c.dispose);

        expect(await gate.isConfigured(), isFalse);
        await gate.setPassword('hunter2');
        expect(await gate.isConfigured(), isTrue);
        expect(await gate.verify('hunter2'), isTrue);
        expect(await gate.verify('wrong'), isFalse);
        await gate.clear();
        expect(await gate.isConfigured(), isFalse);
      },
    );

    test('biometric vault stores + reads through a single fake', () async {
      final vault = FakeBiometricKeyVault();
      final c = makeTestProviderContainer(biometricVault: vault);
      addTearDown(c.dispose);

      expect(await vault.isStored(), isFalse);
      expect(await vault.read(), isNull);
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      await vault.store(key);
      expect(await vault.isStored(), isTrue);
      expect(await vault.read(), key);
    });

    test('hardware vault fake honours isStored gate on read', () async {
      final vault = FakeHardwareTierVault();
      final c = makeTestProviderContainer(hardwareVault: vault);
      addTearDown(c.dispose);

      final key = Uint8List.fromList(List.generate(32, (i) => i));
      expect(await vault.read(null), isNull);
      await vault.store(dbKey: key);
      expect(await vault.isStored(), isTrue);
      expect(await vault.read(null), key);
      await vault.clear();
      expect(await vault.isStored(), isFalse);
      expect(await vault.read(null), isNull);
    });
  });
}
