import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

void main() {
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
        expect(mapped.tier, SecurityTier.keychainWithPassword);
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
      expect(mapped.tier, SecurityTier.keychainWithPassword);
      expect(mapped.modifiers.password, isTrue);
      expect(mapped.modifiers.biometric, isTrue);
      // Legacy alias must stay in sync.
      expect(mapped.modifiers.biometricShortcut, isTrue);
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

  group('SecurityTierModifiers additive fields', () {
    test('defaults leave password + biometric off', () {
      const m = SecurityTierModifiers.defaults;
      expect(m.password, isFalse);
      expect(m.biometric, isFalse);
      expect(m.biometricShortcut, isFalse);
    });

    test('JSON round-trip preserves the new fields', () {
      const m = SecurityTierModifiers(
        password: true,
        biometric: true,
        biometricShortcut: true,
        pinLength: 4,
      );
      final round = SecurityTierModifiers.fromJson(m.toJson());
      expect(round, m);
    });

    test('legacy JSON (biometric_shortcut only) backfills biometric', () {
      final m = SecurityTierModifiers.fromJson(const {
        'biometric_shortcut': true,
        'pin_length': 6,
      });
      expect(
        m.biometric,
        isTrue,
        reason:
            'biometric must default to biometric_shortcut on legacy configs',
      );
      expect(m.biometricShortcut, isTrue);
      expect(m.password, isFalse);
    });

    test('out-of-range pin_length clamps to the default', () {
      final m = SecurityTierModifiers.fromJson(const {'pin_length': 99});
      expect(m.pinLength, SecurityTierModifiers.defaults.pinLength);
    });
  });
}
