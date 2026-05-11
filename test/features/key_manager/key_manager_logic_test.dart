import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/features/key_manager/key_manager_logic.dart';

SshKeyMetadata _meta({
  required String id,
  required String label,
  required String keyType,
  CertValidity? validity,
  List<String> principals = const [],
  Map<String, String> criticalOptions = const {},
  String certFingerprint = '',
}) => SshKeyMetadata(
  id: id,
  label: label,
  publicKey: 'pub-$id',
  keyType: keyType,
  createdAt: DateTime(2024, 1, 1),
  isGenerated: false,
  privateFingerprint: 'priv-$id',
  publicFingerprint: 'pub-$id',
  validity: validity,
  principals: principals,
  criticalOptions: criticalOptions,
  certFingerprint: certFingerprint,
);

const _labels = CertRowLabels(
  principals: 'Principals',
  validTo: 'Valid until',
  criticalOptions: 'Critical options',
  localizedDate: '2026-01-01',
);

void main() {
  final fixture = [
    _meta(id: '1', label: 'Production', keyType: 'ssh-ed25519'),
    _meta(id: '2', label: 'Staging', keyType: 'ssh-rsa'),
    _meta(id: '3', label: 'Personal Laptop', keyType: 'ecdsa-sha2-nistp256'),
  ];

  group('filterSshKeys', () {
    test('empty filter returns the full list verbatim', () {
      expect(filterSshKeys(fixture, ''), fixture);
    });

    test('whitespace-only filter is treated as empty', () {
      // A stray leading or trailing space in the search box must not
      // hide every entry — that's user-hostile.
      expect(filterSshKeys(fixture, '   '), fixture);
      expect(filterSshKeys(fixture, '\t'), fixture);
    });

    test('label match is case-insensitive', () {
      final r = filterSshKeys(fixture, 'PROD');
      expect(r.length, 1);
      expect(r.single.label, 'Production');
    });

    test('keyType match is case-insensitive', () {
      // Only the rsa row matches "rsa".
      final r = filterSshKeys(fixture, 'rsa');
      expect(r.map((k) => k.id).toList(), ['2']);
    });

    test('matches across both columns when one query hits both', () {
      // "ed25519" matches the keyType of one entry — the label match
      // is empty so the result is exactly the type-matching row.
      final r = filterSshKeys(fixture, 'ed25519');
      expect(r.map((k) => k.id).toList(), ['1']);
    });

    test('no match returns empty list (UI shows the no-results state)', () {
      expect(filterSshKeys(fixture, 'nonexistent'), isEmpty);
    });

    test('public key / fingerprints are NOT searched', () {
      // The body intentionally limits matching to label + keyType.
      // Searching the binary blob would surface noise; this test
      // pins that contract so a future "search everything" tweak
      // surfaces explicitly.
      expect(filterSshKeys(fixture, 'pub-1'), isEmpty);
      expect(filterSshKeys(fixture, 'priv-2'), isEmpty);
    });

    test('empty input list is a no-op for any filter', () {
      expect(filterSshKeys(const [], ''), isEmpty);
      expect(filterSshKeys(const [], 'anything'), isEmpty);
    });
  });

  group('buildCertTertiary', () {
    test('returns null for a metadata row without a cert attached', () {
      // The row renders without a tertiary slot when no cert is
      // paired; `null` is the contract `AppDataRow` expects.
      final entry = _meta(id: '1', label: 'no-cert', keyType: 'ssh-ed25519');
      expect(buildCertTertiary(entry, _labels), isNull);
    });

    test(
      'renders principals + validity + critical-options separated by bullets',
      () {
        final entry = _meta(
          id: '1',
          label: 'with-cert',
          keyType: 'ssh-ed25519',
          certFingerprint: 'SHA256:abc',
          validity: CertValidity(
            from: DateTime.utc(2025, 1, 1),
            to: DateTime.utc(2026, 1, 1),
          ),
          principals: const ['alice', 'root'],
          criticalOptions: const {'force-command': 'echo hi'},
        );
        final out = buildCertTertiary(entry, _labels);
        expect(out, isNotNull);
        expect(out, contains('Principals: alice, root'));
        expect(out, contains('Valid until 2026-01-01'));
        expect(out, contains('Critical options: 1'));
      },
    );

    test('clips principals at three visible entries with a +N tail', () {
      // The principals list can be arbitrarily long; the row is one
      // line so the helper must clip to keep the chip layout
      // readable. Cliff at three visible entries + numeric overflow
      // is the documented contract.
      final entry = _meta(
        id: '1',
        label: 'long',
        keyType: 'ssh-ed25519',
        certFingerprint: 'SHA256:abc',
        principals: const ['a', 'b', 'c', 'd', 'e'],
      );
      final out = buildCertTertiary(entry, _labels)!;
      expect(out, contains('Principals: a, b, c +2'));
    });

    test('omits the critical-options segment when none are attached', () {
      // Critical options are uncommon; the tertiary line should not
      // carry a `: 0` tail when none are set.
      final entry = _meta(
        id: '1',
        label: 'simple',
        keyType: 'ssh-ed25519',
        certFingerprint: 'SHA256:abc',
        principals: const ['alice'],
        validity: CertValidity(
          from: DateTime.utc(2025, 1, 1),
          to: DateTime.utc(2026, 1, 1),
        ),
      );
      final out = buildCertTertiary(entry, _labels)!;
      expect(out.contains('Critical options'), isFalse);
    });
  });
}
