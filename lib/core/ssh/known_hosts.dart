import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

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
  Future<bool> Function(String host, int port, String keyType, String fingerprint)?
      onUnknownHost;

  /// Callback invoked when a known host's key has changed (potential MITM).
  /// Return true to accept the new key, false to reject.
  /// If null, changed keys are always rejected.
  Future<bool> Function(String host, int port, String keyType, String fingerprint)?
      onHostKeyChanged;

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
      // Key changed — potential MITM
      if (onHostKeyChanged != null) {
        final fingerprint = _fingerprint(keyBytes);
        final accepted = await onHostKeyChanged!(host, port, keyType, fingerprint);
        if (accepted) {
          await _updateHost(hostPort, keyString);
          return true;
        }
      }
      return false;
    }

    // Unknown host
    if (onUnknownHost != null) {
      final fingerprint = _fingerprint(keyBytes);
      final accepted = await onUnknownHost!(host, port, keyType, fingerprint);
      if (accepted) {
        await _addHost(hostPort, keyString);
        return true;
      }
      return false;
    }

    // No callback — reject unknown host (require explicit user confirmation)
    return false;
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

  Future<void> _updateHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    await _saveAll();
  }

  Future<void> _saveAll() async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    final sb = StringBuffer();
    for (final entry in _hosts.entries) {
      sb.writeln('${entry.key} ${entry.value}');
    }
    await file.writeAsString(sb.toString());
  }

  String _fingerprint(List<int> keyBytes) {
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(keyBytes));
    return 'SHA256:${base64Encode(hash)}';
  }
}
