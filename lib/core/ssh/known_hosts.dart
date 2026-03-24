import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// TOFU (Trust On First Use) host key verification + persistent storage.
///
/// Stores keys in OpenSSH-like format: `host:port keytype base64key`
class KnownHostsManager {
  final Map<String, String> _hosts = {};
  late final String _filePath;
  bool _loaded = false;

  /// Callback invoked when an unknown host is encountered.
  /// Return true to accept the key, false to reject.
  /// If null, unknown hosts are auto-accepted (TOFU).
  Future<bool> Function(String host, int port, String fingerprint)?
      onUnknownHost;

  /// Initialize and load known_hosts from app support directory.
  Future<void> load() async {
    if (_loaded) return;
    final dir = await getApplicationSupportDirectory();
    _filePath = p.join(dir.path, 'known_hosts');
    final file = File(_filePath);
    if (await file.exists()) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        // Format: host:port keytype base64key
        final parts = trimmed.split(' ');
        if (parts.length >= 3) {
          final hostPort = parts[0];
          final keyType = parts[1];
          final keyData = parts[2];
          _hosts[hostPort] = '$keyType $keyData';
        }
      }
    }
    _loaded = true;
  }

  /// Verify host key. Returns true if accepted.
  ///
  /// - Known host, key matches → accept
  /// - Known host, key changed → reject (HostKeyError)
  /// - Unknown host → ask via callback or auto-accept (TOFU)
  Future<bool> verify(
    String host,
    int port,
    String keyType,
    List<int> keyBytes,
  ) async {
    await load();
    final hostPort = '$host:$port';
    final keyData = base64Encode(keyBytes);
    final keyString = '$keyType $keyData';
    final existing = _hosts[hostPort];

    if (existing != null) {
      if (existing == keyString) {
        return true; // Known and matches
      }
      return false; // Key changed — potential MITM
    }

    // Unknown host
    if (onUnknownHost != null) {
      final fingerprint = _fingerprint(keyBytes);
      final accepted = await onUnknownHost!(host, port, fingerprint);
      if (accepted) {
        await _addHost(hostPort, keyString);
        return true;
      }
      return false;
    }

    // Auto-TOFU
    await _addHost(hostPort, keyString);
    return true;
  }

  Future<void> _addHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '$hostPort $keyString\n',
      mode: FileMode.append,
    );
  }

  String _fingerprint(List<int> keyBytes) {
    // Simple hex fingerprint of first 16 bytes
    final bytes = keyBytes.length > 16 ? keyBytes.sublist(0, 16) : keyBytes;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }
}
