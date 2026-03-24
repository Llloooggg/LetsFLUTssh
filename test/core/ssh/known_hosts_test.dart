import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';

// Test the fingerprint algorithm and verify() logic by re-creating a minimal
// KnownHostsManager that doesn't depend on path_provider.
// The real KnownHostsManager uses getApplicationSupportDirectory() which isn't
// available in unit tests, so we test the verification algorithm directly.

void main() {
  group('known_hosts fingerprint algorithm', () {
    String fingerprint(List<int> keyBytes) {
      final digest = SHA256Digest();
      final hash = digest.process(Uint8List.fromList(keyBytes));
      return 'SHA256:${base64Encode(hash)}';
    }

    test('produces SHA256: prefix', () {
      final fp = fingerprint([1, 2, 3, 4]);
      expect(fp, startsWith('SHA256:'));
    });

    test('same bytes produce same fingerprint', () {
      final bytes = [10, 20, 30, 40, 50];
      expect(fingerprint(bytes), fingerprint(bytes));
    });

    test('different bytes produce different fingerprint', () {
      expect(fingerprint([1, 2, 3]), isNot(fingerprint([4, 5, 6])));
    });

    test('empty bytes produce valid fingerprint', () {
      final fp = fingerprint([]);
      expect(fp, startsWith('SHA256:'));
      // SHA256 of empty input is a known value
      expect(fp, 'SHA256:${base64Encode(SHA256Digest().process(Uint8List(0)))}');
    });
  });

  group('known_hosts file format parsing', () {
    // Test the parsing logic that KnownHostsManager.load() uses
    Map<String, String> parseKnownHosts(String content) {
      final hosts = <String, String>{};
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split(' ');
        if (parts.length >= 3) {
          hosts[parts[0]] = '${parts[1]} ${parts[2]}';
        }
      }
      return hosts;
    }

    test('parses host:port keytype base64key', () {
      const content = 'example.com:22 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5\n';
      final hosts = parseKnownHosts(content);
      expect(hosts['example.com:22'], 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5');
    });

    test('skips empty lines', () {
      const content = '\n\nexample.com:22 ssh-rsa AAAA\n\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });

    test('skips comment lines', () {
      const content = '# comment\nexample.com:22 ssh-rsa AAAA\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });

    test('multiple hosts', () {
      const content = 'a.com:22 ssh-rsa KEY1\nb.com:2222 ssh-ed25519 KEY2\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 2);
      expect(hosts['a.com:22'], 'ssh-rsa KEY1');
      expect(hosts['b.com:2222'], 'ssh-ed25519 KEY2');
    });

    test('ignores lines with fewer than 3 parts', () {
      const content = 'bad line\nexample.com:22 ssh-rsa AAAA\n';
      final hosts = parseKnownHosts(content);
      expect(hosts.length, 1);
    });
  });

  group('known_hosts verify logic', () {
    // Inline reimplementation of verify() to test the algorithm without I/O.
    late Map<String, String> hosts;
    late List<String> unknownHostCalls;
    late List<String> keyChangedCalls;
    late bool acceptUnknown;
    late bool acceptChanged;

    setUp(() {
      hosts = {};
      unknownHostCalls = [];
      keyChangedCalls = [];
      acceptUnknown = true;
      acceptChanged = false;
    });

    Future<bool> verify(
      String host, int port, String keyType, List<int> keyBytes, {
      bool hasUnknownCallback = true,
      bool hasChangedCallback = true,
    }) async {
      final hostPort = '$host:$port';
      final keyData = base64Encode(keyBytes);
      final keyString = '$keyType $keyData';
      final existing = hosts[hostPort];

      if (existing != null) {
        if (existing == keyString) return true;
        // Key changed
        if (hasChangedCallback) {
          keyChangedCalls.add(hostPort);
          if (acceptChanged) {
            hosts[hostPort] = keyString;
            return true;
          }
        }
        return false;
      }

      // Unknown host
      if (hasUnknownCallback) {
        unknownHostCalls.add(hostPort);
        if (acceptUnknown) {
          hosts[hostPort] = keyString;
          return true;
        }
        return false;
      }

      // No callback — reject (require explicit user confirmation)
      return false;
    }

    test('unknown host with callback — accepted', () async {
      acceptUnknown = true;
      final result = await verify('example.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, ['example.com:22']);
      expect(hosts.containsKey('example.com:22'), isTrue);
    });

    test('unknown host with callback — rejected', () async {
      acceptUnknown = false;
      final result = await verify('example.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isFalse);
      expect(hosts.containsKey('example.com:22'), isFalse);
    });

    test('unknown host without callback — rejected', () async {
      final result = await verify(
        'example.com', 22, 'ssh-rsa', [1, 2, 3],
        hasUnknownCallback: false,
      );
      expect(result, isFalse);
      expect(unknownHostCalls, isEmpty);
      expect(hosts.containsKey('example.com:22'), isFalse);
    });

    test('known host with matching key — accepted silently', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      final result = await verify('server', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, isEmpty);
      expect(keyChangedCalls, isEmpty);
    });

    test('known host with changed key — rejected by default', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      acceptChanged = false;
      final result = await verify('server', 22, 'ssh-rsa', [4, 5, 6]);
      expect(result, isFalse);
      expect(keyChangedCalls, ['server:22']);
    });

    test('known host with changed key — accepted when callback approves', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      acceptChanged = true;
      final result = await verify('server', 22, 'ssh-rsa', [4, 5, 6]);
      expect(result, isTrue);
      // Key should be updated
      expect(hosts['server:22'], 'ssh-rsa ${base64Encode([4, 5, 6])}');
    });

    test('known host with changed key — rejected when no callback', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      final result = await verify(
        'server', 22, 'ssh-rsa', [4, 5, 6],
        hasChangedCallback: false,
      );
      expect(result, isFalse);
    });

    test('different ports are different hosts', () async {
      hosts['server:22'] = 'ssh-rsa ${base64Encode([1, 2, 3])}';
      acceptUnknown = true;
      final result = await verify('server', 2222, 'ssh-rsa', [1, 2, 3]);
      expect(result, isTrue);
      expect(unknownHostCalls, ['server:2222']);
      expect(hosts.length, 2);
    });
  });

  group('known_hosts file I/O', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('known_hosts_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('write and read back known_hosts file', () async {
      final file = File('${tempDir.path}/known_hosts');
      final entries = {
        'host1.com:22': 'ssh-rsa AAAA',
        'host2.com:2222': 'ssh-ed25519 BBBB',
      };

      // Write
      final sb = StringBuffer();
      for (final e in entries.entries) {
        sb.writeln('${e.key} ${e.value}');
      }
      await file.writeAsString(sb.toString());

      // Read back
      final lines = await file.readAsLines();
      final parsed = <String, String>{};
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(' ');
        if (parts.length >= 3) {
          parsed[parts[0]] = '${parts[1]} ${parts[2]}';
        }
      }

      expect(parsed, entries);
    });

    test('append to known_hosts file', () async {
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString('host1:22 ssh-rsa KEY1\n');
      await file.writeAsString('host2:22 ssh-rsa KEY2\n', mode: FileMode.append);

      final lines = await file.readAsLines();
      expect(lines.length, 2);
    });
  });
}
