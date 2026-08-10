import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart'
    show WizardTier;
import 'package:letsflutssh/widgets/security/security_setup_dialog_logic.dart';

void main() {
  group('wizardBiometricToggleEnabled', () {
    test('host with no biometric capability blocks every tier', () {
      for (final tier in WizardTier.values) {
        for (final pw in [true, false]) {
          expect(
            wizardBiometricToggleEnabled(
              selected: tier,
              password: pw,
              canOfferBiometric: false,
            ),
            isFalse,
            reason: 'tier=$tier pw=$pw caps=false',
          );
        }
      }
    });

    test('plaintext + paranoid never expose biometric', () {
      for (final tier in [WizardTier.plaintext, WizardTier.paranoid]) {
        expect(
          wizardBiometricToggleEnabled(
            selected: tier,
            password: true,
            canOfferBiometric: true,
          ),
          isFalse,
          reason: 'tier=$tier',
        );
      }
    });

    test('keychain / hardware require the password modifier', () {
      for (final tier in [WizardTier.keychain, WizardTier.hardware]) {
        expect(
          wizardBiometricToggleEnabled(
            selected: tier,
            password: false,
            canOfferBiometric: true,
          ),
          isFalse,
          reason: '$tier without password → biometric locked',
        );
        expect(
          wizardBiometricToggleEnabled(
            selected: tier,
            password: true,
            canOfferBiometric: true,
          ),
          isTrue,
          reason: '$tier with password + caps → biometric unlocked',
        );
      }
    });
  });

  group('wizardPasswordToggleEnabled', () {
    test('paranoid has a mandatory password — toggle locked', () {
      expect(wizardPasswordToggleEnabled(WizardTier.paranoid), isFalse);
    });

    test('hardware lets the user pick — toggle enabled', () {
      // T2 password is optional (TPM/SE/StrongBox provides hardware
      // binding); the toggle lets the user opt in.
      expect(wizardPasswordToggleEnabled(WizardTier.hardware), isTrue);
    });

    test('plaintext has nothing to gate — toggle locked', () {
      expect(wizardPasswordToggleEnabled(WizardTier.plaintext), isFalse);
    });

    test('keychain lets the user pick', () {
      expect(wizardPasswordToggleEnabled(WizardTier.keychain), isTrue);
    });
  });

  group('wizardNeedsSecretInput', () {
    test('paranoid always asks for the master password', () {
      expect(
        wizardNeedsSecretInput(selected: WizardTier.paranoid, password: true),
        isTrue,
      );
      expect(
        wizardNeedsSecretInput(selected: WizardTier.paranoid, password: false),
        isTrue,
        reason: 'paranoid asks regardless of the modifier flag',
      );
    });

    test('plaintext never asks', () {
      expect(
        wizardNeedsSecretInput(selected: WizardTier.plaintext, password: true),
        isFalse,
      );
      expect(
        wizardNeedsSecretInput(selected: WizardTier.plaintext, password: false),
        isFalse,
      );
    });

    test('keychain asks only when password modifier is on', () {
      expect(
        wizardNeedsSecretInput(selected: WizardTier.keychain, password: false),
        isFalse,
        reason: 'passwordless keychain skips the secret input',
      );
      expect(
        wizardNeedsSecretInput(selected: WizardTier.keychain, password: true),
        isTrue,
        reason: 'keychain+password requires the bank-style secret',
      );
    });

    test('hardware asks only when password modifier is on', () {
      // T2 password is optional (TPM/SE/StrongBox provides hardware
      // binding); the wizard follows the modifier flag.
      expect(
        wizardNeedsSecretInput(selected: WizardTier.hardware, password: true),
        isTrue,
        reason: 'hardware+password requires the secret input',
      );
      expect(
        wizardNeedsSecretInput(selected: WizardTier.hardware, password: false),
        isFalse,
        reason: 'passwordless hardware skips the secret input',
      );
    });
  });

  group('wizardCanSubmit', () {
    test(
      'plaintext requires explicit acknowledgement before Continue lights up',
      () {
        expect(
          wizardCanSubmit(
            selected: WizardTier.plaintext,
            plaintextAcknowledged: false,
          ),
          isFalse,
        );
        expect(
          wizardCanSubmit(
            selected: WizardTier.plaintext,
            plaintextAcknowledged: true,
          ),
          isTrue,
        );
      },
    );

    test('every other tier ignores the plaintext-acknowledge flag', () {
      for (final tier in [
        WizardTier.keychain,
        WizardTier.hardware,
        WizardTier.paranoid,
      ]) {
        expect(
          wizardCanSubmit(selected: tier, plaintextAcknowledged: false),
          isTrue,
          reason: '$tier should always submit',
        );
      }
    });
  });

  group('resolveBiometricInvariant', () {
    test('biometric demoted to false whenever password is off', () {
      expect(
        resolveBiometricInvariant(password: false, biometric: true),
        isFalse,
      );
      expect(
        resolveBiometricInvariant(password: false, biometric: false),
        isFalse,
      );
    });

    test('biometric kept verbatim when password is on', () {
      expect(
        resolveBiometricInvariant(password: true, biometric: true),
        isTrue,
      );
      expect(
        resolveBiometricInvariant(password: true, biometric: false),
        isFalse,
      );
    });
  });
}
