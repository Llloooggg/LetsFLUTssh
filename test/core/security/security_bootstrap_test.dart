import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // canOfferBiometricModifier, mapWizardChoice, the value-type
  // contract + JSON round-trip groups all route through `lfs_core`
  // — bootstrap FRB so the canonical Rust grammar is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SecurityCapabilities.canOfferBiometricModifier', () {
    test('non-Linux: only the platform biometric flag matters', () {
      const caps = SecurityCapabilities(biometricAvailable: true);
      expect(caps.canOfferBiometricModifier, isTrue);
    });

    test('non-Linux: false when biometric unavailable', () {
      const caps = SecurityCapabilities(biometricAvailable: false);
      expect(caps.canOfferBiometricModifier, isFalse);
    });

    test('Linux: either biometric or fprintd suffices', () {
      expect(
        const SecurityCapabilities(
          isLinuxHost: true,
          fprintdAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(
        const SecurityCapabilities(
          isLinuxHost: true,
          biometricAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(
        const SecurityCapabilities(isLinuxHost: true).canOfferBiometricModifier,
        isFalse,
      );
    });
  });

  group('mapWizardChoice', () {
    test('plaintext → plaintext tier, no secret fields populated', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.plaintext,
        password: false,
        biometric: false,
      );
      expect(mapped.tier, SecurityTier.plaintext);
      expect(mapped.masterPassword, isNull);
      expect(mapped.shortPassword, isNull);
      expect(mapped.pin, isNull);
    });

    test('keychain without password → plain keychain tier', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.keychain,
        password: false,
        biometric: false,
      );
      expect(mapped.tier, SecurityTier.keychain);
      expect(mapped.shortPassword, isNull);
      expect(mapped.modifiers.password, isFalse);
    });

    test(
      'keychain + password → keychainWithPassword with shortPassword set',
      () {
        final mapped = mapWizardChoice(
          chosen: WizardTier.keychain,
          password: true,
          biometric: false,
          typedSecret: 'hunter2',
        );
        expect(mapped.tier, SecurityTier.keychain);
        expect(mapped.shortPassword, 'hunter2');
        expect(mapped.modifiers.password, isTrue);
      },
    );

    test('keychain + password + biometric → flags stay on modifiers', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.keychain,
        password: true,
        biometric: true,
        typedSecret: 'hunter2',
      );
      expect(mapped.tier, SecurityTier.keychain);
      expect(mapped.modifiers.password, isTrue);
      expect(mapped.modifiers.biometric, isTrue);
    });

    test('hardware → hardware tier with pin populated from typedSecret', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.hardware,
        password: true,
        biometric: false,
        typedSecret: 'verylong_pass',
      );
      expect(mapped.tier, SecurityTier.hardware);
      expect(mapped.pin, 'verylong_pass');
      expect(mapped.modifiers.password, isTrue);
    });

    test('paranoid → paranoid tier with masterPassword populated', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.paranoid,
        password: true,
        biometric: false,
        typedSecret: 'correct horse battery staple',
      );
      expect(mapped.tier, SecurityTier.paranoid);
      expect(mapped.masterPassword, 'correct horse battery staple');
    });
  });

  group('SecurityTierModifiers bank-style fields', () {
    test('defaults leave password + biometric off', () {
      const m = SecurityTierModifiers.defaults;
      expect(m.password, isFalse);
      expect(m.biometric, isFalse);
    });

    test('JSON round-trip preserves the bank-style modifier fields', () {
      const m = SecurityTierModifiers(password: true, biometric: true);
      final round = SecurityTierModifiers.fromJson(m.toJson());
      expect(round, m);
    });

    test('legacy biometric_shortcut / pin_length JSON keys are ignored', () {
      // ConfigV3ToV4 strips these from disk on first read; if a
      // hand-edited config still carries them, the runtime decoder
      // must silently drop them rather than blow up.
      final m = SecurityTierModifiers.fromJson(const {
        'password': true,
        'biometric': false,
        'biometric_shortcut': true,
        'pin_length': 6,
      });
      expect(m.password, isTrue);
      expect(m.biometric, isFalse);
    });
  });

  group('SecurityCapabilities value-type contract', () {
    test('default constructor uses the "nothing detected" defaults', () {
      const caps = SecurityCapabilities();
      expect(caps.keychainAvailable, isFalse);
      expect(caps.hardwareVaultAvailable, isFalse);
      expect(caps.biometricAvailable, isFalse);
      expect(caps.fprintdAvailable, isFalse);
      expect(caps.isLinuxHost, isFalse);
      expect(caps.keychainProbe, KeyringProbeResult.probeFailed);
      expect(caps.hardwareProbeCode, 'unknown');
    });

    test('copyWith replaces only the named fields', () {
      const base = SecurityCapabilities(
        keychainAvailable: true,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      final copy = base.copyWith(
        hardwareVaultAvailable: true,
        biometricAvailable: true,
      );
      expect(copy.keychainAvailable, isTrue, reason: 'untouched stays true');
      expect(copy.isLinuxHost, isTrue);
      expect(copy.keychainProbe, KeyringProbeResult.available);
      expect(copy.hardwareProbeCode, 'available');
      expect(copy.hardwareVaultAvailable, isTrue);
      expect(copy.biometricAvailable, isTrue);
    });

    test('== + hashCode agree on field-by-field equality', () {
      const a = SecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      const b = SecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == b.copyWith(fprintdAvailable: true),
        isFalse,
        reason: 'any field diff must flip equality',
      );
    });

    test(
      'JSON round-trip preserves every field; invalid payloads return null',
      () {
        const caps = SecurityCapabilities(
          keychainAvailable: true,
          hardwareVaultAvailable: false,
          biometricAvailable: true,
          fprintdAvailable: true,
          isLinuxHost: true,
          keychainProbe: KeyringProbeResult.linuxNoSecretService,
          hardwareProbeCode: 'available',
        );
        final round = SecurityCapabilities.fromJson(caps.toJson())!;
        expect(round, caps);
        expect(SecurityCapabilities.fromJson(null), isNull);
        // Missing keychain_probe → treated as corrupt cache (null).
        expect(SecurityCapabilities.fromJson(<String, dynamic>{}), isNull);
        // Non-string keychain_probe → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 42,
            'hardware_probe_code': 'available',
          }),
          isNull,
        );
        // Unknown enum value for keychain_probe → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 'nonsense',
            'hardware_probe_code': 'available',
          }),
          isNull,
        );
        // Non-string hardware_probe_code → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 'available',
            'hardware_probe_code': 7,
          }),
          isNull,
        );
      },
    );
  });

  // probeCapabilities itself is no longer unit-tested here: the
  // function is now a thin async wrapper around
  // `lfs_core::security::capabilities_orchestrator::run`. The
  // orchestrator runs platform probes against the real host
  // (Secret Service / TPM2 / fprintd / etc.) under prompt
  // listeners that flutter_test cannot drive without a live FRB
  // runtime + plugin set. End-to-end coverage lives in
  // `lfs_core::security::capabilities_orchestrator::tests` and the
  // integration_test suite that runs against real probes.
}
