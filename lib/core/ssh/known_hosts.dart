import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';

/// TOFU (Trust On First Use) host key verification + persistent storage.
///
/// Stores keys in OpenSSH-like format: `host:port keytype base64key`
class KnownHostsManager {
  final Map<String, String> _hosts = {};
  late final String _filePath;

  /// Cached load future — ensures concurrent calls to [load] don't race.
  Future<void>? _loadFuture;

  /// Sequential write lock — prevents concurrent file writes from corrupting
  /// the known_hosts file.
  Future<void> _pendingWrite = Future.value();

  /// Callback invoked when an unknown host is encountered.
  /// Return true to accept the key, false to reject.
  /// If null, unknown hosts are auto-accepted (TOFU).
  Future<bool> Function(
    String host,
    int port,
    String keyType,
    String fingerprint,
  )?
  onUnknownHost;

  /// Callback invoked when a known host's key has changed (potential MITM).
  /// Return true to accept the new key, false to reject.
  /// If null, changed keys are always rejected.
  Future<bool> Function(
    String host,
    int port,
    String keyType,
    String fingerprint,
  )?
  onHostKeyChanged;

  /// Initialize and load known_hosts from app support directory.
  ///
  /// Safe to call concurrently — the first call does the actual I/O,
  /// subsequent calls await the same future.
  Future<void> load() => _loadFuture ??= _doLoad();

  Future<void> _doLoad() async {
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
    AppLogger.instance.log(
      'Loaded ${_hosts.length} known hosts from $_filePath',
      name: 'KnownHosts',
    );
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
        AppLogger.instance.log(
          'Host key verified: $hostPort',
          name: 'KnownHosts',
        );
        return true; // Known and matches
      }
      // Key changed — potential MITM
      AppLogger.instance.log(
        'Host key CHANGED for $hostPort ($keyType) — potential MITM',
        name: 'KnownHosts',
      );
      if (onHostKeyChanged != null) {
        final fingerprint = _fingerprint(keyBytes);
        final accepted = await onHostKeyChanged!(
          host,
          port,
          keyType,
          fingerprint,
        );
        if (accepted) {
          AppLogger.instance.log(
            'Changed host key accepted: $hostPort',
            name: 'KnownHosts',
          );
          await _updateHost(hostPort, keyString);
          return true;
        }
      }
      AppLogger.instance.log(
        'Changed host key rejected: $hostPort',
        name: 'KnownHosts',
      );
      return false;
    }

    // Unknown host
    AppLogger.instance.log(
      'Unknown host: $hostPort ($keyType)',
      name: 'KnownHosts',
    );
    if (onUnknownHost != null) {
      final fingerprint = _fingerprint(keyBytes);
      final accepted = await onUnknownHost!(host, port, keyType, fingerprint);
      if (accepted) {
        AppLogger.instance.log(
          'Unknown host accepted (TOFU): $hostPort',
          name: 'KnownHosts',
        );
        await _addHost(hostPort, keyString);
        return true;
      }
      AppLogger.instance.log(
        'Unknown host rejected: $hostPort',
        name: 'KnownHosts',
      );
      return false;
    }

    // No callback — reject unknown host (require explicit user confirmation)
    AppLogger.instance.log(
      'Unknown host rejected (no callback): $hostPort',
      name: 'KnownHosts',
    );
    return false;
  }

  Future<void> _addHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    await _withWriteLock(() async {
      final file = File(_filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString('$hostPort $keyString\n', mode: FileMode.append);
      restrictFilePermissions(file.path);
    });
  }

  Future<void> _updateHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    await _saveAll();
  }

  Future<void> _saveAll() => _withWriteLock(() async {
    final sb = StringBuffer();
    for (final entry in _hosts.entries) {
      sb.writeln('${entry.key} ${entry.value}');
    }
    await writeFileAtomic(_filePath, sb.toString());
  });

  /// Serialize file writes — each write waits for the previous one.
  Future<void> _withWriteLock(Future<void> Function() fn) {
    _pendingWrite = _pendingWrite.then((_) => fn(), onError: (_) => fn());
    return _pendingWrite;
  }

  String _fingerprint(List<int> keyBytes) {
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(keyBytes));
    return 'SHA256:${base64Encode(hash)}';
  }
}
