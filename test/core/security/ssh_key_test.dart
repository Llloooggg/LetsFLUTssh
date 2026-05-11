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

  group('SshKeyEntry JSON round-trip', () {
    test('full round-trip preserves every field', () {
      final original = _entry(isGenerated: true);
      final restored = SshKeyEntry.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.label, original.label);
      expect(restored.privateKey, original.privateKey);
      expect(restored.publicKey, original.publicKey);
      expect(restored.keyType, original.keyType);
      expect(restored.createdAt, original.createdAt);
      expect(restored.isGenerated, isTrue);
    });

    test('toJson uses snake_case keys for the persistence layer', () {
      final json = _entry().toJson();
      // The DB / archive consumers index on these keys; renaming
      // any of them is a wire-format change.
      expect(
        json.keys,
        containsAll(<String>{
          'id',
          'label',
          'private_key',
          'public_key',
          'key_type',
          'created_at',
          'is_generated',
        }),
      );
    });

    test('toJson serialises createdAt as ISO-8601', () {
      final json = _entry(
        createdAt: DateTime.utc(2025, 1, 2, 3, 4, 5),
      ).toJson();
      expect(json['created_at'], '2025-01-02T03:04:05.000Z');
    });

    test('fromJson defaults missing optional fields', () {
      // Older archive formats may omit fields the model added later
      // — fromJson must tolerate the absence and fall back to
      // sensible defaults rather than throw.
      final restored = SshKeyEntry.fromJson({'id': 'only-id'});
      expect(restored.id, 'only-id');
      expect(restored.label, isEmpty);
      expect(restored.privateKey, isEmpty);
      expect(restored.publicKey, isEmpty);
      expect(restored.keyType, isEmpty);
      expect(restored.isGenerated, isFalse);
    });

    test(
      'fromJson tolerates an unparseable createdAt by falling back to now',
      () {
        final before = DateTime.now();
        final restored = SshKeyEntry.fromJson({
          'id': 'x',
          'created_at': 'not-an-iso-date',
        });
        final after = DateTime.now();
        expect(
          restored.createdAt.isAfter(
            before.subtract(const Duration(seconds: 1)),
          ),
          isTrue,
        );
        expect(
          restored.createdAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      },
    );
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
    test('fromJson defaults to no certificate when fields are absent', () {
      final restored = SshKeyEntry.fromJson({'id': 'a'});
      expect(restored.certificate, isNull);
      expect(restored.validity, isNull);
      expect(restored.principals, isEmpty);
      expect(restored.criticalOptions, isEmpty);
    });

    test('toJson omits certificate fields when no cert is attached', () {
      // Keys without a cert (the common case) must round-trip
      // without flooding the wire format with empty defaults — the
      // archive consumer expects optional keys to be absent.
      final json = _entry().toJson();
      expect(json.containsKey('certificate'), isFalse);
      expect(json.containsKey('valid_from'), isFalse);
      expect(json.containsKey('valid_to'), isFalse);
      expect(json.containsKey('principals'), isFalse);
      expect(json.containsKey('critical_options'), isFalse);
    });

    test('JSON round-trip with cert fields preserves every value', () {
      final original = _entry().copyWith(
        certificate: Uint8List.fromList(const [0xDE, 0xAD, 0xBE, 0xEF]),
        validity: CertValidity(
          from: DateTime.utc(2025, 1, 1),
          to: DateTime.utc(2026, 1, 1),
        ),
        principals: const ['alice', 'root'],
        criticalOptions: const {'force-command': 'echo hi'},
      );
      final restored = SshKeyEntry.fromJson(original.toJson());
      expect(restored.certificate, original.certificate);
      expect(restored.validity, original.validity);
      expect(restored.principals, original.principals);
      expect(restored.criticalOptions, original.criticalOptions);
    });

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

    test('JSON round-trip preserves credentialId / application / UV', () {
      final original = hardwareEntry(uv: true);
      final restored = SshKeyEntry.fromJson(original.toJson());
      expect(restored.credentialId, equals(original.credentialId));
      expect(restored.applicationString, 'ssh:');
      expect(restored.hasUserVerification, isTrue);
      expect(restored.isHardwareBound, isTrue);
    });

    test('toJson omits FIDO2 fields for software keys', () {
      // Software-key rows must not bloat the manifest with null
      // FIDO2 fields — peer / older builds may not understand them.
      final json = _entry().toJson();
      expect(json.containsKey('credential_id'), isFalse);
      expect(json.containsKey('application_string'), isFalse);
      expect(json.containsKey('has_user_verification'), isFalse);
    });

    test('toJson omits has_user_verification when false', () {
      // The flag is the most common-false of the three FIDO fields;
      // emitting `false` would add wire noise on touch-only keys.
      final json = hardwareEntry(uv: false).toJson();
      expect(json.containsKey('has_user_verification'), isFalse);
      expect(json['credential_id'], isA<List<dynamic>>());
      expect(json['application_string'], 'ssh:');
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
