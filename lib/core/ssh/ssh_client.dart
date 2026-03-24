import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:dartssh2/dartssh2.dart';

import 'errors.dart';
import 'known_hosts.dart';
import 'ssh_config.dart';

/// SSH connection wrapper over dartssh2.
///
/// Lifecycle: create → connect() → openShell() → use → disconnect()
class SSHConnection {
  final SSHConfig config;
  final KnownHostsManager knownHosts;

  SSHClient? _client;
  SSHSession? _shell;
  Timer? _keepAliveTimer;
  bool _disposed = false;

  VoidCallback? onDisconnect;

  SSHConnection({
    required this.config,
    required this.knownHosts,
  });

  bool get isConnected => _client != null && !_disposed;

  /// Underlying SSH client (for SFTP subsystem, etc.).
  SSHClient? get client => _client;

  /// Connect to SSH server with auth chain.
  Future<void> connect() async {
    if (_disposed) throw const ConnectError('Connection disposed');

    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(
        config.host,
        config.effectivePort,
        timeout: Duration(seconds: config.timeoutSec),
      );
    } catch (e) {
      throw ConnectError(
        'Failed to connect to ${config.host}:${config.effectivePort}',
        e,
      );
    }

    try {
      _client = SSHClient(
        socket,
        username: config.user,
        onPasswordRequest: _onPasswordRequest,
        identities: await _buildIdentities(),
        onVerifyHostKey: _onVerifyHostKey,
        keepAliveInterval:
            config.keepAliveSec > 0
                ? Duration(seconds: config.keepAliveSec)
                : null,
      );

      // Wait for authentication to complete
      await _client!.authenticated;
    } on SSHAuthFailError catch (e) {
      _cleanup();
      throw AuthError('Authentication failed for ${config.user}@${config.host}', e);
    } on SSHAuthAbortError catch (e) {
      _cleanup();
      throw AuthError('Authentication aborted', e);
    } catch (e) {
      _cleanup();
      throw ConnectError('Connection failed', e);
    }

    // Listen for disconnect
    _client!.done.then((_) {
      if (!_disposed) {
        _disposed = true;
        _keepAliveTimer?.cancel();
        onDisconnect?.call();
      }
    });
  }

  /// Open PTY shell session.
  Future<SSHSession> openShell(int cols, int rows) async {
    if (_client == null) throw const ConnectError('Not connected');

    try {
      _shell = await _client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: cols,
          height: rows,
        ),
      );
      return _shell!;
    } catch (e) {
      throw ConnectError('Failed to open shell', e);
    }
  }

  /// Resize PTY terminal.
  void resizeTerminal(int cols, int rows) {
    _shell?.resizeTerminal(cols, rows);
  }

  /// Disconnect and cleanup.
  void disconnect() {
    _disposed = true;
    _cleanup();
  }

  void _cleanup() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _shell?.close();
    _shell = null;
    _client?.close();
    _client = null;
  }

  /// Password auth callback for dartssh2.
  String? _onPasswordRequest() {
    if (config.password.isNotEmpty) return config.password;
    return null;
  }

  /// Standard SSH key file names, tried in order (same as OpenSSH).
  static const _defaultKeyNames = [
    'id_ed25519',
    'id_ecdsa',
    'id_rsa',
    'id_dsa',
  ];

  /// Build identity list for key-based auth.
  /// Auth chain: key file → key text → default ~/.ssh/ keys (same as OpenSSH).
  Future<List<SSHKeyPair>> _buildIdentities() async {
    final identities = <SSHKeyPair>[];
    final passphrase = config.passphrase.isNotEmpty ? config.passphrase : null;

    // Key from explicit file path
    if (config.keyPath.isNotEmpty) {
      try {
        final keyFile = File(config.keyPath);
        final keyData = await keyFile.readAsString();
        identities.addAll(SSHKeyPair.fromPem(keyData, passphrase));
      } catch (e) {
        throw AuthError('Failed to load key from file: ${config.keyPath}', e);
      }
    }

    // Key from PEM text
    if (config.keyData.isNotEmpty) {
      try {
        identities.addAll(SSHKeyPair.fromPem(config.keyData, passphrase));
      } catch (e) {
        throw AuthError('Failed to parse PEM key data', e);
      }
    }

    // Auto-detect keys from ~/.ssh/ (like OpenSSH) if no explicit key provided
    if (identities.isEmpty) {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        final sshDir = Directory('$home/.ssh');
        if (await sshDir.exists()) {
          for (final name in _defaultKeyNames) {
            final keyFile = File('${sshDir.path}/$name');
            if (await keyFile.exists()) {
              try {
                final keyData = await keyFile.readAsString();
                identities.addAll(SSHKeyPair.fromPem(keyData, null));
              } catch (_) {
                // Skip keys that can't be parsed (encrypted without passphrase, etc.)
              }
            }
          }
        }
      }
    }

    return identities;
  }

  // Host key verification callback for dartssh2.
  Future<bool> _onVerifyHostKey(
    String type,
    Uint8List fingerprint,
  ) async {
    return knownHosts.verify(
      config.host,
      config.effectivePort,
      type,
      fingerprint,
    );
  }
}
