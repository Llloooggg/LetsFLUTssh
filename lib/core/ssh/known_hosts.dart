import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../utils/file_utils.dart';
import '../../utils/logger.dart';
import '../security/aes_gcm.dart';
import '../security/security_level.dart';

/// TOFU (Trust On First Use) host key verification + persistent storage.
///
/// Stores keys in OpenSSH-like format: `host:port keytype base64key`.
/// Supports three security levels:
/// - [SecurityLevel.plaintext]: `known_hosts` in cleartext.
/// - [SecurityLevel.keychain] / [SecurityLevel.masterPassword]:
///   `known_hosts.enc` encrypted with AES-256-GCM.
class KnownHostsManager {
  static const _plaintextFileName = 'known_hosts';
  static const _encryptedFileName = 'known_hosts.enc';

  final Map<String, String> _hosts = {};
  String? _basePath;

  SecurityLevel _level = SecurityLevel.plaintext;
  Uint8List? _encryptionKey;

  /// Current security level.
  SecurityLevel get securityLevel => _level;

  /// Read-only view of all known host entries.
  ///
  /// Keys are `host:port`, values are `keytype base64key`.
  Map<String, String> get entries => Map.unmodifiable(_hosts);

  /// Number of known hosts.
  int get count => _hosts.length;

  /// Set the encryption key (from keychain or master password).
  void setEncryptionKey(Uint8List key, SecurityLevel level) {
    _encryptionKey = key;
    _level = level;
  }

  /// Clear the encryption key (revert to plaintext).
  void clearEncryptionKey() {
    _encryptionKey = null;
    _level = SecurityLevel.plaintext;
  }

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

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Initialize and load known_hosts from app support directory.
  ///
  /// Safe to call concurrently — the first call does the actual I/O,
  /// subsequent calls await the same future.
  Future<void> load() => _loadFuture ??= _doLoad();

  Future<void> _doLoad() async {
    final basePath = await _getBasePath();

    // Try encrypted file first, then plaintext.
    String? content;
    if (_encryptionKey != null) {
      final encFile = File(p.join(basePath, _encryptedFileName));
      if (await encFile.exists()) {
        try {
          final encData = await encFile.readAsBytes();
          content = AesGcm.decrypt(encData, _encryptionKey!);
        } catch (e) {
          AppLogger.instance.log(
            'Failed to decrypt known_hosts: $e',
            name: 'KnownHosts',
            error: e,
          );
        }
      }
    }

    // Fallback to plaintext (or plaintext mode).
    if (content == null) {
      final textFile = File(p.join(basePath, _plaintextFileName));
      if (await textFile.exists()) {
        content = await textFile.readAsString();
      }
    }

    if (content != null) {
      _parseContent(content);
    }

    AppLogger.instance.log(
      'Loaded ${_hosts.length} known hosts',
      name: 'KnownHosts',
    );
  }

  void _parseContent(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(' ');
      if (parts.length >= 3) {
        _hosts[parts[0]] = '${parts[1]} ${parts[2]}';
      }
    }
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
        return true;
      }
      AppLogger.instance.log(
        'Host key CHANGED for $hostPort ($keyType) — potential MITM',
        name: 'KnownHosts',
      );
      if (onHostKeyChanged != null) {
        final fp = _fingerprint(keyBytes);
        final accepted = await onHostKeyChanged!(host, port, keyType, fp);
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
      final fp = _fingerprint(keyBytes);
      final accepted = await onUnknownHost!(host, port, keyType, fp);
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

    AppLogger.instance.log(
      'Unknown host rejected (no callback): $hostPort',
      name: 'KnownHosts',
    );
    return false;
  }

  Future<void> _addHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    await _saveAll();
  }

  Future<void> _updateHost(String hostPort, String keyString) async {
    _hosts[hostPort] = keyString;
    await _saveAll();
  }

  Future<void> _saveAll() => _withWriteLock(() async {
    final basePath = await _getBasePath();
    final content = _serializeContent();

    if (_encryptionKey != null) {
      final encData = AesGcm.encrypt(content, _encryptionKey!);
      await writeBytesAtomic(p.join(basePath, _encryptedFileName), encData);
    } else {
      final filePath = p.join(basePath, _plaintextFileName);
      await writeFileAtomic(filePath, content);
      await restrictFilePermissions(filePath);
    }
  });

  String _serializeContent() {
    final sb = StringBuffer();
    for (final entry in _hosts.entries) {
      sb.writeln('${entry.key} ${entry.value}');
    }
    return sb.toString();
  }

  /// Serialize file writes — each write waits for the previous one.
  Future<void> _withWriteLock(Future<void> Function() fn) {
    _pendingWrite = _pendingWrite.then((_) => fn(), onError: (_) => fn());
    return _pendingWrite;
  }

  /// Re-encrypt all data with a new key and security level.
  Future<void> reEncrypt(Uint8List? newKey, SecurityLevel newLevel) async {
    final basePath = await _getBasePath();

    _encryptionKey = newKey;
    _level = newLevel;
    if (_hosts.isNotEmpty) {
      await _saveAll();
    }

    // Clean up opposite format file.
    if (newKey != null) {
      final textFile = File(p.join(basePath, _plaintextFileName));
      if (await textFile.exists()) await textFile.delete();
    } else {
      final encFile = File(p.join(basePath, _encryptedFileName));
      if (await encFile.exists()) await encFile.delete();
    }
  }

  /// Remove a single known host entry.
  Future<void> removeHost(String hostPort) async {
    await load();
    if (_hosts.remove(hostPort) != null) {
      await _saveAll();
      AppLogger.instance.log(
        'Removed known host: $hostPort',
        name: 'KnownHosts',
      );
    }
  }

  /// Remove multiple known host entries.
  Future<void> removeMultiple(Set<String> hostPorts) async {
    await load();
    var removed = 0;
    for (final hp in hostPorts) {
      if (_hosts.remove(hp) != null) removed++;
    }
    if (removed > 0) {
      await _saveAll();
      AppLogger.instance.log(
        'Removed $removed known hosts',
        name: 'KnownHosts',
      );
    }
  }

  /// Remove all known host entries.
  Future<void> clearAll() async {
    await load();
    if (_hosts.isEmpty) return;
    final count = _hosts.length;
    _hosts.clear();
    await _saveAll();
    AppLogger.instance.log(
      'Cleared all $count known hosts',
      name: 'KnownHosts',
    );
  }

  /// Import entries from an OpenSSH-format known_hosts file.
  ///
  /// Returns the number of new entries added (existing hosts are skipped).
  Future<int> importFromFile(String path) async {
    await load();
    final file = File(path);
    if (!await file.exists()) return 0;

    final content = await file.readAsString();
    var added = 0;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(' ');
      if (parts.length >= 3) {
        final hostPort = parts[0];
        final keyString = '${parts[1]} ${parts[2]}';
        if (!_hosts.containsKey(hostPort)) {
          _hosts[hostPort] = keyString;
          added++;
        }
      }
    }

    if (added > 0) {
      await _saveAll();
      AppLogger.instance.log(
        'Imported $added known hosts from $path',
        name: 'KnownHosts',
      );
    }
    return added;
  }

  /// Export all entries to OpenSSH known_hosts format.
  String exportToString() => _serializeContent();

  /// Compute SHA256 fingerprint of host key bytes.
  static String fingerprint(List<int> keyBytes) {
    final digest = SHA256Digest();
    final hash = digest.process(Uint8List.fromList(keyBytes));
    return 'SHA256:${base64Encode(hash)}';
  }

  String _fingerprint(List<int> keyBytes) => fingerprint(keyBytes);
}
