import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';

void main() {
  group('SshAuthMethod variants', () {
    test('SshAuthAgent is a const sealed-class case', () {
      const a = SshAuthAgent();
      const b = SshAuthAgent();
      expect(a, isA<SshAuthMethod>());
      // const-canonical: two const-constructed instances are
      // identical.
      expect(identical(a, b), isTrue);
    });

    test('SshAuthPasswordRef carries the SecretStore id', () {
      const auth = SshAuthPasswordRef('sess.password.s1');
      expect(auth, isA<SshAuthMethod>());
      expect(auth.passwordSecretId, 'sess.password.s1');
    });

    test('SshAuthPubkeyRef carries key id + optional passphrase id', () {
      const noPass = SshAuthPubkeyRef('key.priv.k1');
      expect(noPass.keySecretId, 'key.priv.k1');
      expect(noPass.passphraseSecretId, isNull);

      const withPass = SshAuthPubkeyRef(
        'key.priv.k1',
        passphraseSecretId: 'key.passphrase.k1',
      );
      expect(withPass.keySecretId, 'key.priv.k1');
      expect(withPass.passphraseSecretId, 'key.passphrase.k1');
    });

    test('SshAuthPubkeyCertRef carries key + cert + optional passphrase', () {
      const auth = SshAuthPubkeyCertRef('key.priv.k1', 'key.cert.k1');
      expect(auth.keySecretId, 'key.priv.k1');
      expect(auth.certSecretId, 'key.cert.k1');
      expect(auth.passphraseSecretId, isNull);

      const authWithPass = SshAuthPubkeyCertRef(
        'k',
        'c',
        passphraseSecretId: 'p',
      );
      expect(authWithPass.passphraseSecretId, 'p');
    });

    test('exhaustive switch over SshAuthMethod compiles', () {
      // Pattern-matching against the sealed family lets the analyzer
      // catch a future variant landing without callers updating.
      String describe(SshAuthMethod a) => switch (a) {
        SshAuthAgent() => 'agent',
        SshAuthPasswordRef() => 'password',
        SshAuthPubkeyRef() => 'pubkey',
        SshAuthPubkeyCertRef() => 'pubkey-cert',
        SshAuthPubkeySkRef() => 'pubkey-sk',
        SshAuthPubkeySkCertRef() => 'pubkey-sk-cert',
        SshAuthPubkeyPkcs11Ref() => 'pubkey-pkcs11',
        SshAuthPubkeyEnclaveRef() => 'pubkey-enclave',
        SshAuthPubkeyHelloRef() => 'pubkey-hello',
        SshAuthPubkeyTpmRef() => 'pubkey-tpm',
        SshAuthPubkeyKeystoreRef() => 'pubkey-keystore',
      };
      expect(describe(const SshAuthAgent()), 'agent');
      expect(describe(const SshAuthPasswordRef('x')), 'password');
      expect(describe(const SshAuthPubkeyRef('x')), 'pubkey');
      expect(describe(const SshAuthPubkeyCertRef('k', 'c')), 'pubkey-cert');
      expect(
        describe(
          SshAuthPubkeySkRef(
            publicOpenssh: 'sk-ssh-ed25519@openssh.com AAAA...',
            credentialId: Uint8List.fromList([0xCA, 0xFE]),
            application: 'ssh:',
            pinSecretId: 'key.pin.sk1',
          ),
        ),
        'pubkey-sk',
      );
      expect(
        describe(
          SshAuthPubkeySkCertRef(
            publicOpenssh: 'sk-ssh-ed25519@openssh.com AAAA...',
            credentialId: Uint8List.fromList([0xCA, 0xFE]),
            application: 'ssh:',
            certSecretId: 'key.cert.sk1',
            pinSecretId: 'key.pin.sk1',
          ),
        ),
        'pubkey-sk-cert',
      );
      expect(
        describe(
          SshAuthPubkeyEnclaveRef(
            publicOpenssh: 'ecdsa-sha2-nistp256 AAAA...',
            applicationTag: Uint8List.fromList([0xDE, 0xAD]),
          ),
        ),
        'pubkey-enclave',
      );
      expect(
        describe(
          const SshAuthPubkeyHelloRef(
            publicOpenssh: 'ecdsa-sha2-nistp256 AAAA...',
            credentialName: 'letsflutssh-ssh-abc-1234',
            keyType: 'ecdsa-sha2-nistp256',
          ),
        ),
        'pubkey-hello',
      );
      expect(
        describe(
          const SshAuthPubkeyTpmRef(
            publicOpenssh: 'ecdsa-sha2-nistp256 AAAA...',
            provider: 'tss-esapi',
            keyType: 'ecdsa-sha2-nistp256',
          ),
        ),
        'pubkey-tpm',
      );
      expect(
        describe(
          const SshAuthPubkeyKeystoreRef(
            publicOpenssh: 'ecdsa-sha2-nistp256 AAAA...',
            keystoreAlias: 'lfs-keystore-1234',
            keyType: 'ecdsa-sha2-nistp256',
          ),
        ),
        'pubkey-keystore',
      );
    });
  });

  group('SshShellEvent variants', () {
    test('SshShellOutput carries the byte payload', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final ev = SshShellOutput(bytes);
      expect(ev, isA<SshShellEvent>());
      expect(ev.bytes, equals(bytes));
    });

    test('SshShellExtendedOutput carries stderr bytes', () {
      final bytes = Uint8List.fromList([10, 20]);
      final ev = SshShellExtendedOutput(bytes);
      expect(ev.bytes, equals(bytes));
    });

    test('SshShellEof is a const marker case', () {
      const a = SshShellEof();
      const b = SshShellEof();
      expect(identical(a, b), isTrue);
      expect(a, isA<SshShellEvent>());
    });

    test('SshShellExitStatus carries the exit code', () {
      const ev = SshShellExitStatus(0);
      expect(ev.code, 0);
      const fail = SshShellExitStatus(127);
      expect(fail.code, 127);
    });

    test('SshShellExitSignal carries the signal name', () {
      const ev = SshShellExitSignal('TERM');
      expect(ev.signal, 'TERM');
    });

    test('exhaustive switch over SshShellEvent compiles', () {
      String describe(SshShellEvent e) => switch (e) {
        SshShellOutput() => 'out',
        SshShellExtendedOutput() => 'err',
        SshShellEof() => 'eof',
        SshShellExitStatus() => 'exit',
        SshShellExitSignal() => 'signal',
      };
      expect(describe(SshShellOutput(Uint8List(0))), 'out');
      expect(describe(SshShellExtendedOutput(Uint8List(0))), 'err');
      expect(describe(const SshShellEof()), 'eof');
      expect(describe(const SshShellExitStatus(0)), 'exit');
      expect(describe(const SshShellExitSignal('TERM')), 'signal');
    });
  });

  group('Exception classes', () {
    test('SshConnectError preserves + formats the message', () {
      const e = SshConnectError('connection refused');
      expect(e.message, 'connection refused');
      expect(e.toString(), 'SshConnectError: connection refused');
      expect(e, isA<Exception>());
    });

    test('SshAuthFailed has a fixed string form', () {
      const e = SshAuthFailed();
      expect(e.toString(), 'SshAuthFailed');
      expect(e, isA<Exception>());
    });

    test('SshHostKeyRejected carries the offending fingerprint', () {
      const fp = 'SHA256:abcdef';
      const e = SshHostKeyRejected(fp);
      expect(e.fingerprint, fp);
      expect(e.toString(), 'SshHostKeyRejected: $fp');
      expect(e, isA<Exception>());
    });
  });
}
