import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection_step.dart';
import 'package:letsflutssh/core/connection/connection_step_mappers.dart';
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
  });
}
