import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;

void main() {
  group('mapBusPhase', () {
    test('every Rust phase variant has a Dart twin', () {
      const cases = {
        rust_bus.BusConnectionPhase.socketConnect:
            ConnectionPhase.socketConnect,
        rust_bus.BusConnectionPhase.hostKeyVerify:
            ConnectionPhase.hostKeyVerify,
        rust_bus.BusConnectionPhase.authenticate: ConnectionPhase.authenticate,
        rust_bus.BusConnectionPhase.openChannel: ConnectionPhase.openChannel,
      };
      for (final entry in cases.entries) {
        expect(
          mapBusPhase(entry.key),
          entry.value,
          reason: '${entry.key} → ${entry.value}',
        );
      }
    });

    test('exhaustive — every BusConnectionPhase value is covered', () {
      // Pin the contract: any new variant on the Rust side must
      // come with a matching arm; otherwise this test crashes on
      // the unhandled enum (the switch is exhaustive at compile
      // time, but the iteration here surfaces the gap as a clear
      // test failure).
      for (final p in rust_bus.BusConnectionPhase.values) {
        expect(mapBusPhase(p), isA<ConnectionPhase>());
      }
    });
  });

  group('mapBusStatus', () {
    test('every status variant has a Dart twin', () {
      const cases = {
        rust_bus.BusStepStatus.inProgress: StepStatus.inProgress,
        rust_bus.BusStepStatus.success: StepStatus.success,
        rust_bus.BusStepStatus.failed: StepStatus.failed,
      };
      for (final entry in cases.entries) {
        expect(mapBusStatus(entry.key), entry.value);
      }
    });
  });

  group('busAuthRef', () {
    test('agent variant', () {
      final ref = busAuthRef(const SshAuthAgent());
      expect(ref, isA<rust_bus.BusConnectAuthRef_Agent>());
    });

    test('password variant carries the secret id', () {
      final ref = busAuthRef(const SshAuthPasswordRef('pwd-123'));
      expect(ref, isA<rust_bus.BusConnectAuthRef_Password>());
      final pwd = ref as rust_bus.BusConnectAuthRef_Password;
      expect(pwd.secretId, 'pwd-123');
    });

    test('pubkey variant without passphrase', () {
      final ref = busAuthRef(const SshAuthPubkeyRef('key-1'));
      expect(ref, isA<rust_bus.BusConnectAuthRef_Pubkey>());
      final pk = ref as rust_bus.BusConnectAuthRef_Pubkey;
      expect(pk.keySecretId, 'key-1');
      expect(pk.passphraseSecretId, isNull);
    });

    test('pubkey variant carries an optional passphrase secret id', () {
      final ref = busAuthRef(
        const SshAuthPubkeyRef('key-2', passphraseSecretId: 'passphrase-99'),
      );
      final pk = ref as rust_bus.BusConnectAuthRef_Pubkey;
      expect(pk.keySecretId, 'key-2');
      expect(pk.passphraseSecretId, 'passphrase-99');
    });

    test('pubkeyCert variant carries key + cert + optional passphrase', () {
      final ref = busAuthRef(
        const SshAuthPubkeyCertRef(
          'key-3',
          'cert-3',
          passphraseSecretId: 'pass-3',
        ),
      );
      final pkc = ref as rust_bus.BusConnectAuthRef_PubkeyCert;
      expect(pkc.keySecretId, 'key-3');
      expect(pkc.certSecretId, 'cert-3');
      expect(pkc.passphraseSecretId, 'pass-3');
    });

    test('pubkeyCert variant null passphrase passes through', () {
      final ref = busAuthRef(const SshAuthPubkeyCertRef('k', 'c'));
      final pkc = ref as rust_bus.BusConnectAuthRef_PubkeyCert;
      expect(pkc.passphraseSecretId, isNull);
    });

    test('pubkeySk variant carries every FIDO2 field', () {
      // FIDO2 hardware-bound `sk-*` dispatch — every field on the
      // ref must reach the bus envelope verbatim, otherwise the
      // Rust connect driver can't reconstruct the credential.
      final credentialId = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      final ref = busAuthRef(
        SshAuthPubkeySkRef(
          publicOpenssh: 'sk-ssh-ed25519@openssh.com AAAA...',
          credentialId: credentialId,
          application: 'ssh:',
          pinSecretId: 'key.pin.sk1',
        ),
      );
      expect(ref, isA<rust_bus.BusConnectAuthRef_PubkeySk>());
      final sk = ref as rust_bus.BusConnectAuthRef_PubkeySk;
      expect(sk.publicOpenssh, 'sk-ssh-ed25519@openssh.com AAAA...');
      expect(sk.credentialId, equals(credentialId));
      expect(sk.application, 'ssh:');
      expect(sk.pinSecretId, 'key.pin.sk1');
    });

    test('pubkeySk variant null pinSecretId passes through (touch-only)', () {
      // Touch-only credentials skip PIN staging — the ref carries
      // `null`, and the Rust connect path drives a touch-only
      // assertion on the device.
      final ref = busAuthRef(
        SshAuthPubkeySkRef(
          publicOpenssh: 'sk-ssh-ed25519@openssh.com AAAA...',
          credentialId: Uint8List.fromList([1]),
          application: 'ssh:',
        ),
      );
      final sk = ref as rust_bus.BusConnectAuthRef_PubkeySk;
      expect(sk.pinSecretId, isNull);
    });
  });
}
