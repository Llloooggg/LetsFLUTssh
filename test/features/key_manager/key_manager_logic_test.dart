import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/features/key_manager/key_manager_logic.dart';

SshKeyMetadata _meta({
  required String id,
  required String label,
  required String keyType,
}) => SshKeyMetadata(
  id: id,
  label: label,
  publicKey: 'pub-$id',
  keyType: keyType,
  createdAt: DateTime(2024, 1, 1),
  isGenerated: false,
  privateFingerprint: 'priv-$id',
  publicFingerprint: 'pub-$id',
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
}
