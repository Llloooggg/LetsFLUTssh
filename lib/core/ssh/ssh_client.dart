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

  /// Build identity list for key-based auth.
  /// Auth chain: key file → key text (same as LetsGOssh).
  Future<List<SSHKeyPair>> _buildIdentities() async {
    final identities = <SSHKeyPair>[];

    // Key from file
    if (config.keyPath.isNotEmpty) {
      try {
        final keyFile = File(config.keyPath);
        final keyData = await keyFile.readAsString();
        final pairs = SSHKeyPair.fromPem(
          keyData,
          config.passphrase.isNotEmpty ? config.passphrase : null,
        );
        identities.addAll(pairs);
      } catch (e) {
        throw AuthError('Failed to load key from file: ${config.keyPath}', e);
      }
    }

    // Key from PEM text
    if (config.keyData.isNotEmpty) {
      try {
        final pairs = SSHKeyPair.fromPem(
          config.keyData,
          config.passphrase.isNotEmpty ? config.passphrase : null,
        );
        identities.addAll(pairs);
      } catch (e) {
        throw AuthError('Failed to parse PEM key data', e);
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
