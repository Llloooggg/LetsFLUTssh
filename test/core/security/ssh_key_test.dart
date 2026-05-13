import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';

SshKeyEntry _entry({
  String id = 'abc',
  String label = 'my-key',
  String privateKey = 'PRIV',
  String publicKey = 'PUB',
  String keyType = 'ssh-ed25519',
  bool isGenerated = false,
  DateTime? createdAt,
}) => SshKeyEntry(
  id: id,
  label: label,
  privateKey: privateKey,
  publicKey: publicKey,
  keyType: keyType,
  createdAt: createdAt ?? DateTime.utc(2024, 6, 15, 12, 30, 45),
  isGenerated: isGenerated,
);

void main() {
  group('SshKeyEntry.copyWith', () {
    test('label-only copy preserves every other field', () {
      final original = _entry(label: 'old');
      final renamed = original.copyWith(label: 'new');
      expect(renamed.label, 'new');
      expect(renamed.id, original.id);
      expect(renamed.privateKey, original.privateKey);
      expect(renamed.publicKey, original.publicKey);
      expect(renamed.keyType, original.keyType);
      expect(renamed.createdAt, original.createdAt);
      expect(renamed.isGenerated, original.isGenerated);
    });

    test('null label keeps the existing label', () {
      final original = _entry(label: 'unchanged');
      final copy = original.copyWith();
      expect(copy.label, 'unchanged');
    });
  });

  group('SshKeyEntry equality', () {
    test('equal when id + label + privateKey match', () {
      final a = _entry();
      final b = _entry();
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('different id breaks equality', () {
      expect(_entry(id: 'a') == _entry(id: 'b'), isFalse);
    });

    test('different label breaks equality', () {
      expect(_entry(label: 'x') == _entry(label: 'y'), isFalse);
    });

    test('different privateKey breaks equality', () {
      expect(_entry(privateKey: 'A') == _entry(privateKey: 'B'), isFalse);
    });

    test(
      'publicKey + keyType differences do NOT break equality (by design)',
      () {
        // Equality is intentionally narrow — two rows with the same
        // id + label + privateKey are the "same key" for dedup
        // purposes. Test pins that contract; widen here when it
        // changes.
        expect(_entry(publicKey: 'A') == _entry(publicKey: 'B'), isTrue);
        expect(
          _entry(keyType: 'ssh-rsa') == _entry(keyType: 'ssh-ed25519'),
          isTrue,
        );
      },
    );
  });

  group('SshKeyEntry certificate fields', () {
    test('CertValidity.isExpired reflects current clock vs to', () {
      final past = CertValidity(
        from: DateTime.utc(2020, 1, 1),
        to: DateTime.utc(2020, 1, 2),
      );
      final future = CertValidity(
        from: DateTime.now().add(const Duration(days: 1)),
        to: DateTime.now().add(const Duration(days: 30)),
      );
      expect(past.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });
  });

  group('KeyStoreException', () {
    test('toString includes the message', () {
      const e = KeyStoreException('cannot reach key store');
      expect(e.toString(), 'KeyStoreException: cannot reach key store');
    });

    test('cause is exposed but not embedded in toString', () {
      final e = KeyStoreException('outer', cause: ArgumentError('inner'));
      expect(e.cause, isA<ArgumentError>());
      // toString deliberately omits the cause — the orchestrator
      // logs both; surfacing the cause inline would leak FFI text
      // into UI toasts.
      expect(e.toString(), 'KeyStoreException: outer');
    });
  });

  group('SshKeyEntry FIDO2 hardware-bound fields', () {
    SshKeyEntry hardwareEntry({bool uv = false}) => SshKeyEntry(
      id: 'sk-id',
      label: 'YubiKey',
      privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
      publicKey: 'sk-ssh-ed25519@openssh.com AAAA',
      keyType: 'sk-ed25519',
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      credentialId: Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
      applicationString: 'ssh:',
      hasUserVerification: uv,
    );

    test('isHardwareBound reflects credentialId presence', () {
      expect(hardwareEntry().isHardwareBound, isTrue);
      expect(_entry().isHardwareBound, isFalse);
    });

    test('copyWith threads FIDO2 fields without touching unrelated fields', () {
      final base = hardwareEntry();
      final updated = base.copyWith(
        credentialId: Uint8List.fromList([0xFF]),
        applicationString: 'ssh:custom',
        hasUserVerification: true,
      );
      expect(updated.credentialId, [0xFF]);
      expect(updated.applicationString, 'ssh:custom');
      expect(updated.hasUserVerification, isTrue);
      // Identifier / label preserved.
      expect(updated.id, base.id);
      expect(updated.label, base.label);
    });
  });

  group('SshKeyType.isHardwareBound', () {
    test('sk-* variants are hardware-bound', () {
      expect(SshKeyType.skEd25519.isHardwareBound, isTrue);
      expect(SshKeyType.skEcdsaP256.isHardwareBound, isTrue);
    });

    test('software variants are not hardware-bound', () {
      expect(SshKeyType.ed25519.isHardwareBound, isFalse);
      expect(SshKeyType.rsa2048.isHardwareBound, isFalse);
      expect(SshKeyType.rsa4096.isHardwareBound, isFalse);
    });
  });
}
