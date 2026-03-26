import '../ssh/ssh_client.dart';
import '../ssh/ssh_config.dart';

/// SSH connection lifecycle state.
enum SSHConnectionState { disconnected, connecting, connected }

/// Represents a single SSH connection with its lifecycle state.
///
/// One connection can serve multiple tabs (terminal + SFTP).
class Connection {
  final String id;
  final String label;
  final SSHConfig sshConfig;

  SSHConnection? sshConnection;
  SSHConnectionState state;

  /// Error message from last connection attempt, null if no error.
  String? connectionError;

  Connection({
    required this.id,
    required this.label,
    required this.sshConfig,
    this.sshConnection,
    this.state = SSHConnectionState.disconnected,
    this.connectionError,
  });

  bool get isConnected => state == SSHConnectionState.connected;
  bool get isConnecting => state == SSHConnectionState.connecting;
}
