import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../utils/logger.dart';
import '../ssh/known_hosts.dart';
import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';
import 'connection.dart';

/// Factory for creating SSH connections — injectable for testing.
typedef SSHConnectionFactory = SSHConnection Function(
  SSHConfig config,
  KnownHostsManager knownHosts,
);

/// Manages active SSH connections lifecycle.
///
/// Tracks connections, associates them with tabs, notifies listeners.
class ConnectionManager {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();
  final KnownHostsManager knownHosts;
  final SSHConnectionFactory _connectionFactory;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  ConnectionManager({
    required this.knownHosts,
    SSHConnectionFactory? connectionFactory,
  }) : _connectionFactory = connectionFactory ??
            ((config, kh) => SSHConnection(config: config, knownHosts: kh));

  List<Connection> get connections => _connections.values.toList();

  Connection? get(String id) => _connections[id];

  /// Create a connection and start connecting in the background.
  /// Returns the Connection immediately (in `connecting` state).
  /// The connection transitions to `connected` or `disconnected` asynchronously.
  Connection connectAsync(SSHConfig config, {String? label}) {
    final id = _uuid.v4();
    final conn = Connection(
      id: id,
      label: label ?? config.displayName,
      sshConfig: config,
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

  /// Background connection logic.
  Future<void> _doConnect(Connection conn, SSHConfig config) async {
    final sshConn = _connectionFactory(config, knownHosts);
    sshConn.onDisconnect = () {
      conn.state = SSHConnectionState.disconnected;
      conn.sshConnection = null;
      _notify();
    };

    try {
      await sshConn.connect();
      conn.sshConnection = sshConn;
      conn.state = SSHConnectionState.connected;
      AppLogger.instance.log('Connected: ${conn.label}', name: 'Connection');
      conn.completeReady();
      _notify();
    } catch (e) {
      AppLogger.instance.log('Connection failed: $e', name: 'Connection', error: e);
      conn.state = SSHConnectionState.disconnected;
      conn.connectionError = e.toString();
      conn.completeReady();
      _notify();
    }
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

  void _notify() {
    if (!_disposed) {
      _controller.add(null);
    }
  }

  void dispose() {
    disconnectAll();
    _disposed = true;
    _controller.close();
  }
}
