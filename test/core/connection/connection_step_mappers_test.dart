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

    test('pubkeySkCert variant carries every FIDO2 + cert field', () {
      final credentialId = Uint8List.fromList([0xDE, 0xAD]);
      final ref = busAuthRef(
        SshAuthPubkeySkCertRef(
          publicOpenssh: 'sk-cert AAAA',
          credentialId: credentialId,
          application: 'ssh:',
          certSecretId: 'cert.sk',
          pinSecretId: 'pin.sk',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeySkCert;
      expect(r.publicOpenssh, 'sk-cert AAAA');
      expect(r.credentialId, equals(credentialId));
      expect(r.application, 'ssh:');
      expect(r.certSecretId, 'cert.sk');
      expect(r.pinSecretId, 'pin.sk');
    });

    test('pubkeyPkcs11 variant carries module + token + CKA_ID', () {
      final ckaId = Uint8List.fromList([0x01, 0x02]);
      final ref = busAuthRef(
        SshAuthPubkeyPkcs11Ref(
          publicOpenssh: 'pkcs11 AAAA',
          modulePath: '/usr/lib/opensc-pkcs11.so',
          tokenSerial: 'serial-7',
          ckaId: ckaId,
          keyType: 'ecdsa-sha2-nistp256',
          pinSecretId: 'pin.p11',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyPkcs11;
      expect(r.publicOpenssh, 'pkcs11 AAAA');
      expect(r.modulePath, '/usr/lib/opensc-pkcs11.so');
      expect(r.tokenSerial, 'serial-7');
      expect(r.ckaId, equals(ckaId));
      expect(r.keyType, 'ecdsa-sha2-nistp256');
      expect(r.pinSecretId, 'pin.p11');
    });

    test('pubkeyPkcs11 variant null pinSecretId passes through (PIN-pad)', () {
      final ref = busAuthRef(
        SshAuthPubkeyPkcs11Ref(
          publicOpenssh: 'p',
          modulePath: '/m',
          tokenSerial: 's',
          ckaId: Uint8List.fromList([0]),
          keyType: 'k',
        ),
      );
      expect(
        (ref as rust_bus.BusConnectAuthRef_PubkeyPkcs11).pinSecretId,
        isNull,
      );
    });

    test('pubkeyEnclave variant carries the application tag', () {
      final tag = Uint8List.fromList([0xAB, 0xCD]);
      final ref = busAuthRef(
        SshAuthPubkeyEnclaveRef(publicOpenssh: 'se AAAA', applicationTag: tag),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyEnclave;
      expect(r.publicOpenssh, 'se AAAA');
      expect(r.applicationTag, equals(tag));
    });

    test('pubkeyHello variant carries credential name + key type', () {
      final ref = busAuthRef(
        const SshAuthPubkeyHelloRef(
          publicOpenssh: 'hello AAAA',
          credentialName: 'cng-key-1',
          keyType: 'ecdsa-sha2-nistp256',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyHello;
      expect(r.publicOpenssh, 'hello AAAA');
      expect(r.credentialName, 'cng-key-1');
      expect(r.keyType, 'ecdsa-sha2-nistp256');
    });

    test('pubkeyTpm variant carries provider + blob + key type', () {
      // Linux ESAPI shape — `blob` is the lookup surface, `cngKeyName`
      // is null (that slot is the Windows PCP variant).
      final blob = Uint8List.fromList([0x10, 0x20]);
      final ref = busAuthRef(
        SshAuthPubkeyTpmRef(
          publicOpenssh: 'tpm AAAA',
          provider: 'tss-esapi',
          blob: blob,
          keyType: 'ecdsa-sha2-nistp256',
          pinSecretId: 'pin.tpm',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyTpm;
      expect(r.publicOpenssh, 'tpm AAAA');
      expect(r.provider, 'tss-esapi');
      expect(r.blob, equals(blob));
      expect(r.cngKeyName, isNull);
      expect(r.keyType, 'ecdsa-sha2-nistp256');
      expect(r.pinSecretId, 'pin.tpm');
    });

    test('pubkeyTpm variant carries the Windows PCP cngKeyName slot', () {
      final ref = busAuthRef(
        const SshAuthPubkeyTpmRef(
          publicOpenssh: 'tpm AAAA',
          provider: 'cng-pcp',
          cngKeyName: 'pcp-key-9',
          keyType: 'rsa-2048',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyTpm;
      expect(r.provider, 'cng-pcp');
      expect(r.cngKeyName, 'pcp-key-9');
      expect(r.blob, isNull);
      expect(r.pinSecretId, isNull);
    });

    test('pubkeyKeystore variant carries alias + key type', () {
      final ref = busAuthRef(
        const SshAuthPubkeyKeystoreRef(
          publicOpenssh: 'ks AAAA',
          keystoreAlias: 'android-alias',
          keyType: 'ssh-ed25519',
        ),
      );
      final r = ref as rust_bus.BusConnectAuthRef_PubkeyKeystore;
      expect(r.publicOpenssh, 'ks AAAA');
      expect(r.keystoreAlias, 'android-alias');
      expect(r.keyType, 'ssh-ed25519');
    });

    test('every SshAuthMethod subtype maps to a BusConnectAuthRef', () {
      // Exhaustiveness guard — `busAuthRef`'s switch is compile-time
      // exhaustive, but enumerating every concrete subtype here makes
      // a future unmapped variant fail as a clear test miss rather
      // than only at the call site.
      final methods = <SshAuthMethod>[
        const SshAuthAgent(),
        const SshAuthPasswordRef('p'),
        const SshAuthPubkeyRef('k'),
        const SshAuthPubkeyCertRef('k', 'c'),
        SshAuthPubkeySkRef(
          publicOpenssh: 'p',
          credentialId: Uint8List.fromList([1]),
          application: 'ssh:',
        ),
        SshAuthPubkeySkCertRef(
          publicOpenssh: 'p',
          credentialId: Uint8List.fromList([1]),
          application: 'ssh:',
          certSecretId: 'c',
        ),
        SshAuthPubkeyPkcs11Ref(
          publicOpenssh: 'p',
          modulePath: '/m',
          tokenSerial: 's',
          ckaId: Uint8List.fromList([1]),
          keyType: 'k',
        ),
        SshAuthPubkeyEnclaveRef(
          publicOpenssh: 'p',
          applicationTag: Uint8List.fromList([1]),
        ),
        const SshAuthPubkeyHelloRef(
          publicOpenssh: 'p',
          credentialName: 'n',
          keyType: 'k',
        ),
        const SshAuthPubkeyTpmRef(
          publicOpenssh: 'p',
          provider: 'tss-esapi',
          keyType: 'k',
        ),
        const SshAuthPubkeyKeystoreRef(
          publicOpenssh: 'p',
          keystoreAlias: 'a',
          keyType: 'k',
        ),
      ];
      for (final m in methods) {
        expect(busAuthRef(m), isA<rust_bus.BusConnectAuthRef>());
      }
    });
  });
}
