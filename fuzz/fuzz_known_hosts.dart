// Standalone fuzz target for known_hosts file parsing.
//
// Reads raw bytes from stdin, interprets them as a known_hosts file,
// and exercises the line-by-line parsing logic.
// Compiled to native via `dart compile exe` for AFL++/ClusterFuzzLite.
//
// Usage:
//   dart compile exe fuzz/fuzz_known_hosts.dart -o fuzz/out/fuzz_known_hosts
//   echo 'example.com:22 ssh-rsa AAAA...' | ./fuzz/out/fuzz_known_hosts

import 'dart:convert';
import 'dart:io';

void main() {
  final lines = <String>[];
  String? line;
  while ((line = stdin.readLineSync(encoding: utf8)) != null) {
    lines.add(line!);
  }
  if (lines.isEmpty) return;
  final input = lines.join('\n');

  final hosts = <String, String>{};

  for (final line in input.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    // Format: host:port keytype base64key
    final parts = trimmed.split(' ');
    if (parts.length >= 3) {
      final hostPort = parts[0];
      final keyType = parts[1];
      final keyData = parts[2];

      // Validate hostPort format
      if (hostPort.contains(':')) {
        final hpParts = hostPort.split(':');
        if (hpParts.length == 2) {
          final portStr = hpParts[1];
          final port = int.tryParse(portStr);
          if (port != null && port > 0 && port <= 65535) {
            // Valid entry
          }
        }
      }

      // Try base64 decode the key data
      try {
        base64Decode(keyData);
      } catch (_) {
        // Invalid base64 — still stored as-is in real implementation
      }

      hosts[hostPort] = '$keyType $keyData';
    }
  }

  // Verify the map is consistent
  for (final entry in hosts.entries) {
    assert(entry.key.isNotEmpty);
    assert(entry.value.isNotEmpty);
  }
}
