import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:dartssh2/dartssh2.dart';

import '../../utils/logger.dart';
import 'errors.dart';
import 'known_hosts.dart';
import 'ssh_config.dart';

/// Typedef for socket creation — injectable for testing.
typedef SSHSocketFactory = Future<SSHSocket> Function(
  String host,
  int port, {
  Duration? timeout,
});

/// Typedef for SSH client creation — injectable for testing.
typedef SSHClientFactory = SSHClient Function(
  SSHSocket socket, {
  required String username,
  String? Function()? onPasswordRequest,
  List<SSHKeyPair>? identities,
  FutureOr<bool> Function(String type, Uint8List fingerprint)? onVerifyHostKey,
  Duration? keepAliveInterval,
});

/// SSH connection wrapper over dartssh2.
///
/// Lifecycle: create → connect() → openShell() → use → disconnect()
class SSHConnection {
  final SSHConfig config;
  final KnownHostsManager knownHosts;

  /// Optional factories for testing — defaults to real dartssh2 implementations.
  final SSHSocketFactory _socketFactory;
  final SSHClientFactory _clientFactory;

  SSHClient? _client;
  SSHSession? _shell;
  Timer? _keepAliveTimer;
  bool _disposed = false;
  bool _hostKeyRejected = false;

  VoidCallback? onDisconnect;

  SSHConnection({
    required this.config,
    required this.knownHosts,
    SSHSocketFactory? socketFactory,
    SSHClientFactory? clientFactory,
  })  : _socketFactory = socketFactory ?? _defaultSocketFactory,
        _clientFactory = clientFactory ?? _defaultClientFactory;

  static Future<SSHSocket> _defaultSocketFactory(
    String host,
    int port, {
    Duration? timeout,
  }) =>
      SSHSocket.connect(host, port, timeout: timeout);

  static SSHClient _defaultClientFactory(
    SSHSocket socket, {
    required String username,
    String? Function()? onPasswordRequest,
    List<SSHKeyPair>? identities,
    FutureOr<bool> Function(String type, Uint8List fingerprint)? onVerifyHostKey,
    Duration? keepAliveInterval,
  }) =>
      SSHClient(
        socket,
        username: username,
        onPasswordRequest: onPasswordRequest,
        identities: identities,
        onVerifyHostKey: onVerifyHostKey,
        keepAliveInterval: keepAliveInterval,
      );

  bool get isConnected => _client != null && !_disposed;

  /// Underlying SSH client (for SFTP subsystem, etc.).
  SSHClient? get client => _client;

  /// Connect to SSH server with auth chain.
  Future<void> connect() async {
    if (_disposed) throw const ConnectError('Connection disposed');

    final SSHSocket socket;
    try {
      socket = await _socketFactory(
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
      _client = _clientFactory(
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
      if (_hostKeyRejected) {
        throw HostKeyError(
          'Host key rejected for ${config.host}:${config.effectivePort} — '
          'accept the host key or check known_hosts',
          e,
        );
      }
      throw AuthError('Authentication aborted', e);
    } catch (e) {
      _cleanup();
      if (_hostKeyRejected) {
        throw HostKeyError(
          'Host key rejected for ${config.host}:${config.effectivePort} — '
          'accept the host key or check known_hosts',
          e,
        );
      }
      throw ConnectError('Connection failed to ${config.host}:${config.effectivePort}', e);
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
  /// Auth chain: key file → key text. Keys must be provided explicitly.
  Future<List<SSHKeyPair>> _buildIdentities() async {
    final identities = <SSHKeyPair>[];

    await _tryKeyFileAuth(identities);
    _tryKeyTextAuth(identities);

    return identities;
  }

  /// Try loading SSH key from explicit file path.
  Future<void> _tryKeyFileAuth(List<SSHKeyPair> identities) async {
    if (config.keyPath.isEmpty) return;
    final passphrase = config.passphrase.isNotEmpty ? config.passphrase : null;
    try {
      final keyFile = File(config.keyPath);
      final keyData = await keyFile.readAsString();
      identities.addAll(SSHKeyPair.fromPem(keyData, passphrase));
    } catch (e) {
      AppLogger.instance.log('Failed to load key file: $e', name: 'SSH');
      throw AuthError('Failed to load SSH key file', e);
    }
  }

  /// Try parsing SSH key from PEM text.
  void _tryKeyTextAuth(List<SSHKeyPair> identities) {
    if (config.keyData.isEmpty) return;
    final passphrase = config.passphrase.isNotEmpty ? config.passphrase : null;
    try {
      identities.addAll(SSHKeyPair.fromPem(config.keyData, passphrase));
    } catch (e) {
      throw AuthError('Failed to parse PEM key data', e);
    }
  }


  // Host key verification callback for dartssh2.
  Future<bool> _onVerifyHostKey(
    String type,
    Uint8List fingerprint,
  ) async {
    final accepted = await knownHosts.verify(
      config.host,
      config.effectivePort,
      type,
      fingerprint,
    );
    if (!accepted) _hostKeyRejected = true;
    return accepted;
  }
}
