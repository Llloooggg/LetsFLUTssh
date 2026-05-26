import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/ssh_keys/pkcs11_import_dialog_logic.dart';

void main() {
  group('pkcs11NextStep', () {
    test('module → token', () {
      expect(
        pkcs11NextStep(Pkcs11WizardStep.module, protectedAuthPath: false),
        Pkcs11WizardStep.token,
      );
    });

    test('token → pin when no PIN pad', () {
      expect(
        pkcs11NextStep(Pkcs11WizardStep.token, protectedAuthPath: false),
        Pkcs11WizardStep.pin,
      );
    });

    test('token → key when token has built-in PIN pad', () {
      // CKF_PROTECTED_AUTHENTICATION_PATH — the in-app PIN field is
      // useless because the reader's own keypad answers the prompt.
      expect(
        pkcs11NextStep(Pkcs11WizardStep.token, protectedAuthPath: true),
        Pkcs11WizardStep.key,
      );
    });

    test('pin → key', () {
      expect(
        pkcs11NextStep(Pkcs11WizardStep.pin, protectedAuthPath: false),
        Pkcs11WizardStep.key,
      );
    });

    test('key → save', () {
      expect(
        pkcs11NextStep(Pkcs11WizardStep.key, protectedAuthPath: false),
        Pkcs11WizardStep.save,
      );
    });

    test('save is terminal', () {
      expect(
        pkcs11NextStep(Pkcs11WizardStep.save, protectedAuthPath: false),
        Pkcs11WizardStep.save,
      );
    });
  });

  group('pkcs11PrevStep', () {
    test('module is anchor', () {
      expect(
        pkcs11PrevStep(Pkcs11WizardStep.module, protectedAuthPath: false),
        Pkcs11WizardStep.module,
      );
    });

    test('token → module', () {
      expect(
        pkcs11PrevStep(Pkcs11WizardStep.token, protectedAuthPath: false),
        Pkcs11WizardStep.module,
      );
    });

    test('key → pin when no PIN pad', () {
      expect(
        pkcs11PrevStep(Pkcs11WizardStep.key, protectedAuthPath: false),
        Pkcs11WizardStep.pin,
      );
    });

    test('key → token when token has built-in PIN pad', () {
      // Mirrors the forward-skip rule so Back retraces the same
      // path. Without the mirror, a Back from `key` on a PIN-pad
      // token would drop into a hidden `pin` step.
      expect(
        pkcs11PrevStep(Pkcs11WizardStep.key, protectedAuthPath: true),
        Pkcs11WizardStep.token,
      );
    });

    test('save → key', () {
      expect(
        pkcs11PrevStep(Pkcs11WizardStep.save, protectedAuthPath: false),
        Pkcs11WizardStep.key,
      );
    });
  });

  group('pkcs11ShouldSkipPinStep', () {
    test('true when protectedAuthPath is true', () {
      expect(pkcs11ShouldSkipPinStep(protectedAuthPath: true), isTrue);
    });

    test('false otherwise', () {
      expect(pkcs11ShouldSkipPinStep(protectedAuthPath: false), isFalse);
    });
  });

  group('pkcs11KeyRowEnabled', () {
    test('RSA enabled', () {
      expect(
        pkcs11KeyRowEnabled(sshKeyType: 'rsa', disabledReason: ''),
        isTrue,
      );
    });

    test('ECDSA enabled', () {
      expect(
        pkcs11KeyRowEnabled(sshKeyType: 'ecdsa-p256', disabledReason: ''),
        isTrue,
      );
    });

    test('Ed25519 enabled', () {
      expect(
        pkcs11KeyRowEnabled(sshKeyType: 'ed25519', disabledReason: ''),
        isTrue,
      );
    });

    test('GOST disabled — empty sshKeyType + reason', () {
      expect(
        pkcs11KeyRowEnabled(
          sshKeyType: '',
          disabledReason: 'gost-not-supported',
        ),
        isFalse,
      );
    });

    test('empty sshKeyType always disabled', () {
      // Belt-and-braces: even a non-empty disabledReason with a
      // usable type still gates off the empty-type case so an
      // unrecognised future tag never silently flips to selectable.
      expect(pkcs11KeyRowEnabled(sshKeyType: '', disabledReason: ''), isFalse);
    });

    test('non-empty disabledReason disables regardless of type', () {
      expect(
        pkcs11KeyRowEnabled(sshKeyType: 'rsa', disabledReason: 'broken'),
        isFalse,
      );
    });
  });

  group('pkcs11AlgoDetail', () {
    test('rsa', () {
      final r = pkcs11AlgoDetail('rsa');
      expect(r.algo, 'RSA');
      expect(r.detail, '');
    });

    test('ecdsa variants carry curve', () {
      expect(pkcs11AlgoDetail('ecdsa-p256').detail, 'P-256');
      expect(pkcs11AlgoDetail('ecdsa-p384').detail, 'P-384');
      expect(pkcs11AlgoDetail('ecdsa-p521').detail, 'P-521');
    });

    test('ed25519', () {
      final r = pkcs11AlgoDetail('ed25519');
      expect(r.algo, 'Ed25519');
      expect(r.detail, '');
    });

    test('unknown returns empty pair', () {
      final r = pkcs11AlgoDetail('quantum-blockchain');
      expect(r.algo, '');
      expect(r.detail, '');
    });
  });
}
