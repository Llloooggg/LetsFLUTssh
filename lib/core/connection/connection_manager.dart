import 'dart:async';

import 'package:uuid/uuid.dart';

import '../ssh/known_hosts.dart';
import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';
import 'connection.dart';

/// Manages active SSH connections lifecycle.
///
/// Tracks connections, associates them with tabs, notifies listeners.
class ConnectionManager {
  final _connections = <String, Connection>{};
  final _uuid = const Uuid();
  final KnownHostsManager knownHosts;

  final _controller = StreamController<void>.broadcast();

  /// Stream that fires on any connection state change.
  Stream<void> get onChange => _controller.stream;

  ConnectionManager({required this.knownHosts});

  List<Connection> get connections => _connections.values.toList();

  Connection? get(String id) => _connections[id];

  /// Connect to an SSH server. Returns the connection.
  Future<Connection> connect(SSHConfig config, {String? label}) async {
    final id = _uuid.v4();
    final conn = Connection(
      id: id,
      label: label ?? config.displayName,
      sshConfig: config,
      state: SSHConnectionState.connecting,
    );
    _connections[id] = conn;
    _notify();

    final sshConn = SSHConnection(
      config: config,
      knownHosts: knownHosts,
    );
    sshConn.onDisconnect = () {
      conn.state = SSHConnectionState.disconnected;
      conn.sshConnection = null;
      _notify();
    };

    try {
      await sshConn.connect();
      conn.sshConnection = sshConn;
      conn.state = SSHConnectionState.connected;
      _notify();
      return conn;
    } catch (e) {
      conn.state = SSHConnectionState.disconnected;
      _connections.remove(id);
      _notify();
      rethrow;
    }
  }

  /// Disconnect a specific connection.
  void disconnect(String id) {
    final conn = _connections[id];
    if (conn == null) return;
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
