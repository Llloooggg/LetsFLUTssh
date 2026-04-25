import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show VoidCallback;

import 'package:dartssh2/dartssh2.dart';

import '../../utils/logger.dart';
import '../connection/connection_step.dart';
import 'errors.dart';
import 'known_hosts.dart';
import 'ssh_config.dart';

/// Callback for reporting connection progress steps.
typedef ConnectionProgressCallback = void Function(ConnectionStep step);

/// Callback invoked when an encrypted SSH key needs a passphrase.
/// Returns the passphrase string, or null if the user cancelled.
typedef PassphraseCallback = Future<String?> Function(String host, int attempt);

/// Typedef for socket creation — injectable for testing.
typedef SSHSocketFactory =
    Future<SSHSocket> Function(String host, int port, {Duration? timeout});

/// Typedef for SSH client creation — injectable for testing.
typedef SSHClientFactory =
    SSHClient Function(
      SSHSocket socket, {
      required String username,
      String? Function()? onPasswordRequest,
      List<SSHKeyPair>? identities,
      FutureOr<bool> Function(String type, Uint8List fingerprint)?
      onVerifyHostKey,
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
  bool _disposed = false;
  bool _hostKeyRejected = false;

  /// Maximum number of passphrase prompt attempts before giving up.
  static const maxPassphraseAttempts = 3;

  VoidCallback? onDisconnect;

  /// Called when an encrypted key requires a passphrase not in config.
  /// Set by [ConnectionManager] before calling [connect].
  PassphraseCallback? onPassphraseRequired;

  SSHConnection({
    required this.config,
    required this.knownHosts,
    SSHSocketFactory? socketFactory,
    SSHClientFactory? clientFactory,
  }) : _socketFactory = socketFactory ?? _defaultSocketFactory,
       _clientFactory = clientFactory ?? _defaultClientFactory;

  static Future<SSHSocket> _defaultSocketFactory(
    String host,
    int port, {
    Duration? timeout,
  }) => SSHSocket.connect(host, port, timeout: timeout);

  static SSHClient _defaultClientFactory(
    SSHSocket socket, {
    required String username,
    String? Function()? onPasswordRequest,
    List<SSHKeyPair>? identities,
    FutureOr<bool> Function(String type, Uint8List fingerprint)?
    onVerifyHostKey,
    Duration? keepAliveInterval,
  }) => SSHClient(
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
  ///
  /// [onProgress] is called at each connection phase to report progress.
  ///
  /// [socketProvider] is the ProxyJump escape hatch. When non-null,
  /// `_connectSocket` is skipped and the socket comes from the
  /// provider — which is expected to be `bastion.client.forwardLocal(
  /// host, port)` wrapping an [SSHForwardChannel] (which implements
  /// [SSHSocket]). The provider is awaited fresh on every reconnect
  /// so the channel handle never outlives its bastion's transport.
  Future<void> connect({
    ConnectionProgressCallback? onProgress,
    Future<SSHSocket> Function()? socketProvider,
  }) async {
    if (_disposed) {
      throw ConnectError(
        'Connection disposed',
        null,
        config.host,
        config.effectivePort,
      );
    }

    final socket = socketProvider != null
        ? await socketProvider()
        : await _connectSocket(onProgress);
    await _authenticateClient(socket, onProgress);

    // Listen for disconnect — handle both normal close and errors.
    _client!.done.then(
      (_) {
        if (!_disposed) {
          _disposed = true;
          onDisconnect?.call();
        }
      },
      onError: (_) {
        if (!_disposed) {
          _disposed = true;
          onDisconnect?.call();
        }
      },
    );
  }

  Future<SSHSocket> _connectSocket(
    ConnectionProgressCallback? onProgress,
  ) async {
    onProgress?.call(
      const ConnectionStep(
        phase: ConnectionPhase.socketConnect,
        status: StepStatus.inProgress,
      ),
    );
    try {
      final socket = await _socketFactory(
        config.host,
        config.effectivePort,
        timeout: Duration(seconds: config.timeoutSec),
      );
      onProgress?.call(
        const ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.success,
        ),
      );
      return socket;
    } catch (e) {
      onProgress?.call(
        ConnectionStep(
          phase: ConnectionPhase.socketConnect,
          status: StepStatus.failed,
          detail: e.toString(),
        ),
      );
      throw ConnectError(
        'Failed to connect to ${config.host}:${config.effectivePort}',
        e,
        config.host,
        config.effectivePort,
      );
    }
  }

  Future<void> _authenticateClient(
    SSHSocket socket,
    ConnectionProgressCallback? onProgress,
  ) async {
    onProgress?.call(
      const ConnectionStep(
        phase: ConnectionPhase.hostKeyVerify,
        status: StepStatus.inProgress,
      ),
    );

    try {
      _client = _clientFactory(
        socket,
        username: config.user,
        onPasswordRequest: _onPasswordRequest,
        identities: await _buildIdentities(),
        onVerifyHostKey: _wrapVerifyCallback(onProgress),
        keepAliveInterval: config.keepAliveSec > 0
            ? Duration(seconds: config.keepAliveSec)
            : null,
      );

      // Wait for authentication to complete
      await _client!.authenticated;
      onProgress?.call(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.success,
        ),
      );
    } on SSHAuthFailError catch (e) {
      _cleanup();
      onProgress?.call(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
        ),
      );
      throw AuthError(
        'Authentication failed for ${config.user}@${config.host}',
        e,
        config.user,
        config.host,
      );
    } on SSHAuthAbortError catch (e) {
      _cleanup();
      if (_hostKeyRejected) {
        onProgress?.call(
          const ConnectionStep(
            phase: ConnectionPhase.hostKeyVerify,
            status: StepStatus.failed,
          ),
        );
        throw _hostKeyError(e);
      }
      onProgress?.call(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
        ),
      );
      throw AuthError('Authentication aborted', e, config.user, config.host);
    } catch (e) {
      _cleanup();
      if (_hostKeyRejected) {
        onProgress?.call(
          const ConnectionStep(
            phase: ConnectionPhase.hostKeyVerify,
            status: StepStatus.failed,
          ),
        );
        throw _hostKeyError(e);
      }
      onProgress?.call(
        const ConnectionStep(
          phase: ConnectionPhase.authenticate,
          status: StepStatus.failed,
        ),
      );
      throw ConnectError(
        'Connection failed to ${config.host}:${config.effectivePort}',
        e,
        config.host,
        config.effectivePort,
      );
    }
  }

  /// Wraps [_onVerifyHostKey] to emit progress steps for host key verification
  /// and authentication phases.
  FutureOr<bool> Function(String, Uint8List) _wrapVerifyCallback(
    ConnectionProgressCallback? onProgress,
  ) {
    return (type, fingerprint) async {
      final accepted = await _onVerifyHostKey(type, fingerprint);
      if (accepted) {
        onProgress?.call(
          const ConnectionStep(
            phase: ConnectionPhase.hostKeyVerify,
            status: StepStatus.success,
          ),
        );
        onProgress?.call(
          const ConnectionStep(
            phase: ConnectionPhase.authenticate,
            status: StepStatus.inProgress,
          ),
        );
      } else {
        _hostKeyRejected = true;
      }
      return accepted;
    };
  }

  /// Open PTY shell session.
  Future<SSHSession> openShell(int cols, int rows) async {
    if (_client == null) {
      throw ConnectError(
        'Not connected',
        null,
        config.host,
        config.effectivePort,
      );
    }

    try {
      _shell = await _client!.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: cols, height: rows),
      );
      return _shell!;
    } catch (e) {
      throw ConnectError(
        'Failed to open shell',
        e,
        config.host,
        config.effectivePort,
      );
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
    await _tryKeyTextAuth(identities);

    return identities;
  }

  /// Try loading SSH key from explicit file path.
  Future<void> _tryKeyFileAuth(List<SSHKeyPair> identities) async {
    if (config.keyPath.isEmpty) return;
    try {
      final keyFile = File(config.keyPath);
      final keyData = await keyFile.readAsString();
      final passphrase = await _resolvePassphrase(keyData);
      identities.addAll(SSHKeyPair.fromPem(keyData, passphrase));
    } catch (e) {
      AppLogger.instance.log('Failed to load key file: $e', name: 'SSH');
      throw AuthError(
        'Failed to load SSH key file',
        e,
        config.user,
        config.host,
      );
    }
  }

  /// Try parsing SSH key from PEM text.
  Future<void> _tryKeyTextAuth(List<SSHKeyPair> identities) async {
    if (config.keyData.isEmpty) return;
    try {
      final passphrase = await _resolvePassphrase(config.keyData);
      identities.addAll(SSHKeyPair.fromPem(config.keyData, passphrase));
    } catch (e) {
      throw AuthError(
        'Failed to parse PEM key data',
        e,
        config.user,
        config.host,
      );
    }
  }

  /// Resolve passphrase for a PEM key: try stored passphrase first,
  /// then interactively prompt up to [maxPassphraseAttempts] times.
  ///
  /// Returns passphrase string or null if the key is not encrypted.
  Future<String?> _resolvePassphrase(String pemData) async {
    if (config.passphrase.isNotEmpty) return config.passphrase;

    if (!_isKeyEncrypted(pemData)) return null;

    // No callback — can't prompt user.
    if (onPassphraseRequired == null) {
      throw AuthError(
        'Key is encrypted but no passphrase provided',
        null,
        config.user,
        config.host,
      );
    }

    return _promptForPassphrase(pemData);
  }

  /// Check whether the PEM key requires a passphrase.
  bool _isKeyEncrypted(String pemData) {
    try {
      SSHKeyPair.fromPem(pemData, null);
      return false;
    } on SSHKeyDecryptError {
      return true;
    } on ArgumentError catch (e) {
      // RSA keys: "passphrase is required for encrypted key"
      if (e.message.toString().contains('passphrase')) return true;
      rethrow;
    }
  }

  /// Prompt user up to [maxPassphraseAttempts] times for a valid passphrase.
  ///
  /// The loop body always exits via `return` (success) or `throw`
  /// (cancelled / max attempts reached); structured so the type system
  /// knows there is no fall-through and we don't need a sentinel
  /// `return ''` at the bottom.
  Future<String> _promptForPassphrase(String pemData) async {
    for (int attempt = 1; attempt <= maxPassphraseAttempts; attempt++) {
      final passphrase = await onPassphraseRequired!(config.host, attempt);
      if (passphrase == null) {
        throw AuthError(
          'Passphrase entry cancelled',
          null,
          config.user,
          config.host,
        );
      }

      if (_isValidPassphrase(pemData, passphrase)) return passphrase;

      if (attempt == maxPassphraseAttempts) {
        throw AuthError(
          'Invalid passphrase after $maxPassphraseAttempts attempts',
          null,
          config.user,
          config.host,
        );
      }
    }
    // Unreachable: the loop always exits via the `attempt == max` branch
    // above with a throw. Convert to an explicit StateError so any future
    // refactor that breaks the invariant fails loudly instead of silently
    // returning an empty passphrase.
    throw StateError('passphrase loop exited without return or throw');
  }

  /// Try to decrypt the PEM key with the given passphrase.
  bool _isValidPassphrase(String pemData, String passphrase) {
    try {
      SSHKeyPair.fromPem(pemData, passphrase);
      return true;
    } on SSHKeyDecryptError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  HostKeyError _hostKeyError(Object cause) => HostKeyError(
    'Host key rejected for ${config.host}:${config.effectivePort} — '
    'accept the host key or check known_hosts',
    cause,
    config.host,
    config.effectivePort,
  );

  // Host key verification callback for dartssh2.
  Future<bool> _onVerifyHostKey(String type, Uint8List fingerprint) async {
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
