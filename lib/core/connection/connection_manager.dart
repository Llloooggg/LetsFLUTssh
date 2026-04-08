import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';
import 'connection.dart';

/// Factory for creating SSH connections — injectable for testing.
typedef SSHConnectionFactory =
    SSHConnection Function(SSHConfig config, KnownHostsManager knownHosts);

/// Optional callback invoked when the number of active (connected) sessions changes.
typedef ActiveCountCallback = void Function(int activeCount);

/// Manages active SSH connections lifecycle.
///
/// Tracks connections, associates them with tabs, notifies listeners.
class ConnectionManager {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();
  final KnownHostsManager knownHosts;
  final SSHConnectionFactory _connectionFactory;

  /// Called whenever the number of *connected* sessions changes.
  /// Used by [ForegroundServiceManager] on Android to start/stop the service.
  ActiveCountCallback? onActiveCountChanged;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  ConnectionManager({
    required this.knownHosts,
    SSHConnectionFactory? connectionFactory,
    this.onActiveCountChanged,
  }) : _connectionFactory =
           connectionFactory ??
           ((config, kh) => SSHConnection(config: config, knownHosts: kh));

  List<Connection> get connections => _connections.values.toList();

  Connection? get(String id) => _connections[id];

  /// Create a connection and start connecting in the background.
  /// Returns the Connection immediately (in `connecting` state).
  /// The connection transitions to `connected` or `disconnected` asynchronously.
  Connection connectAsync(
    SSHConfig config, {
    String? label,
    String? sessionId,
  }) {
    final id = _uuid.v4();
    final conn = Connection(
      id: id,
      label: label ?? config.displayName,
      sshConfig: config,
      sessionId: sessionId,
      knownHosts: knownHosts,
      state: SSHConnectionState.connecting,
    );
    _connections[id] = conn;
    _notify();
    AppLogger.instance.log(
      'Connecting to ${config.host}:${config.port} as ${config.user}',
      name: 'Connection',
    );

    // Start connection in background
    _doConnect(conn, config);
    return conn;
  }

  /// Connection timeout — applied at the transport level, not in UI.
  static const connectionTimeout = Duration(seconds: 30);

  /// Background connection logic.
  Future<void> _doConnect(Connection conn, SSHConfig config) async {
    final sshConn = _connectionFactory(config, knownHosts);
    sshConn.onDisconnect = () {
      conn.state = SSHConnectionState.disconnected;
      conn.sshConnection = null;
      _notify();
    };

    try {
      await sshConn
          .connect(onProgress: (step) => conn.addProgressStep(step))
          .timeout(connectionTimeout);
      conn.sshConnection = sshConn;
      conn.state = SSHConnectionState.connected;
      AppLogger.instance.log('Connected: ${conn.label}', name: 'Connection');
    } on TimeoutException {
      AppLogger.instance.log(
        'Connection timed out after ${connectionTimeout.inSeconds}s',
        name: 'Connection',
      );
      sshConn.disconnect();
      conn.state = SSHConnectionState.disconnected;
      conn.connectionError = TimeoutException(
        'Connection timed out',
        connectionTimeout,
      );
    } catch (e) {
      AppLogger.instance.log(
        'Connection failed: $e',
        name: 'Connection',
        error: e,
      );
      sshConn.disconnect();
      conn.state = SSHConnectionState.disconnected;
      conn.connectionError = e;
    } finally {
      conn.completeReady();
      _notify();
    }
  }

  /// Reconnect an existing connection.
  ///
  /// Resets progress stream, disconnects old SSH, and runs a fresh
  /// connection attempt in the background — same as [connectAsync] but
  /// reuses the existing [Connection] object so all tabs see the update.
  void reconnect(String id, {SSHConfig? updatedConfig}) {
    final conn = _connections[id];
    if (conn == null) return;

    // Tear down old SSH connection
    conn.sshConnection?.disconnect();
    conn.sshConnection = null;

    // Apply updated config if provided (e.g. session was edited)
    if (updatedConfig != null) conn.sshConfig = updatedConfig;

    // Reset for fresh progress
    conn.resetForReconnect();
    conn.state = SSHConnectionState.connecting;
    _notify();

    AppLogger.instance.log(
      'Reconnecting to ${conn.sshConfig.host}:${conn.sshConfig.port} '
      'as ${conn.sshConfig.user}',
      name: 'Connection',
    );

    _doConnect(conn, conn.sshConfig);
  }

  /// Disconnect a specific connection.
  void disconnect(String id) {
    final conn = _connections[id];
    if (conn == null) return;
    AppLogger.instance.log('Disconnected: ${conn.label}', name: 'Connection');
    conn.sshConnection?.disconnect();
    conn.state = SSHConnectionState.disconnected;
    conn.sshConnection = null;
    _connections.remove(id);
    _notify();
  }

  /// Disconnect all connections.
  void disconnectAll() {
    for (final conn in _connections.values) {
      conn.sshConnection?.disconnect();
    }
    _connections.clear();
    _notify();
  }

  bool _disposed = false;

  int _lastActiveCount = 0;

  void _notify() {
    if (!_disposed) {
      _controller.add(null);
      _notifyActiveCount();
    }
  }

  void _notifyActiveCount() {
    final count = _connections.values
        .where((c) => c.state == SSHConnectionState.connected)
        .length;
    if (count != _lastActiveCount) {
      _lastActiveCount = count;
      onActiveCountChanged?.call(count);
    }
  }

  void dispose() {
    disconnectAll();
    _disposed = true;
    _controller.close();
  }
}
