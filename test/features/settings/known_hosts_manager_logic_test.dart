import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/known_hosts_manager_logic.dart';

void main() {
  group('filterKnownHostEntries', () {
    final fixture = {
      'github.com:22':
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl',
      'gitlab.com:22':
          'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDjN9TZSpXz...truncated',
      'bitbucket.org:22': 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA...truncated',
      '1.2.3.4:22022': 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...truncated',
    };

    test('empty filter returns every entry sorted by host:port', () {
      final result = filterKnownHostEntries(fixture, '');
      expect(result.map((e) => e.key).toList(), [
        '1.2.3.4:22022',
        'bitbucket.org:22',
        'github.com:22',
        'gitlab.com:22',
      ]);
      expect(result.length, fixture.length);
    });

    test('filter matches against the host:port key (case-insensitive)', () {
      expect(
        filterKnownHostEntries(fixture, 'Hub.com').map((e) => e.key).toList(),
        ['github.com:22'],
      );
      expect(
        filterKnownHostEntries(fixture, '22022').map((e) => e.key).toList(),
        ['1.2.3.4:22022'],
      );
    });

    test('filter matches against the key payload too', () {
      // ed25519 lines should match even when the host:port doesn't.
      final result = filterKnownHostEntries(fixture, 'ed25519');
      expect(result.map((e) => e.key).toSet(), {
        'github.com:22',
        '1.2.3.4:22022',
      });
    });

    test('filter with no matches returns empty list', () {
      expect(filterKnownHostEntries(fixture, 'nonexistent'), isEmpty);
    });

    test('output preserves the original sort even after filtering', () {
      final result = filterKnownHostEntries(fixture, 'rsa');
      expect(result.map((e) => e.key).toList(), [
        'bitbucket.org:22',
        'gitlab.com:22',
      ]);
    });

    test('empty input map returns empty list for any filter', () {
      expect(filterKnownHostEntries(const {}, ''), isEmpty);
      expect(filterKnownHostEntries(const {}, 'foo'), isEmpty);
    });
  });

  group('splitKnownHostValue', () {
    test('well-formed `<keyType> <keyData>` shape', () {
      final r = splitKnownHostValue('ssh-ed25519 AAAAC3NzaC1l');
      expect(r.keyType, 'ssh-ed25519');
      expect(r.keyData, 'AAAAC3NzaC1l');
    });

    test('extra trailing comments / fingerprints are dropped', () {
      // The function returns only the first two whitespace-separated
      // tokens — anything after that (comments, SHA256 fingerprint
      // suffix) belongs in a downstream parser, not in this split.
      final r = splitKnownHostValue('ssh-rsa AAAA1234 user@host SHA256:abcd');
      expect(r.keyType, 'ssh-rsa');
      expect(r.keyData, 'AAAA1234');
    });

    test('single token (degenerate input) yields empty key data', () {
      final r = splitKnownHostValue('ssh-ed25519');
      expect(r.keyType, 'ssh-ed25519');
      expect(r.keyData, isEmpty);
    });

    test('empty value yields two empty fields', () {
      final r = splitKnownHostValue('');
      expect(r.keyType, isEmpty);
      expect(r.keyData, isEmpty);
    });
  });
}
