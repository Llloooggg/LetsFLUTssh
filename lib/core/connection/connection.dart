import 'dart:async';

import '../ssh/known_hosts.dart';
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

  /// Known hosts manager — retained for reconnect after disconnect.
  final KnownHostsManager knownHosts;

  SSHConnection? sshConnection;
  SSHConnectionState state;

  /// Error message from last connection attempt, null if no error.
  String? connectionError;

  /// Completes when the connection leaves the `connecting` state
  /// (either connected or failed). Callers use [ready] instead of polling.
  final Completer<void> _readyCompleter = Completer<void>();

  Connection({
    required this.id,
    required this.label,
    required this.sshConfig,
    KnownHostsManager? knownHosts,
    this.sshConnection,
    this.state = SSHConnectionState.disconnected,
    this.connectionError,
  }) : knownHosts = knownHosts ?? KnownHostsManager();

  bool get isConnected => state == SSHConnectionState.connected;
  bool get isConnecting => state == SSHConnectionState.connecting;

  /// Future that completes when connection attempt finishes
  /// (success or failure). Safe to await multiple times.
  Future<void> get ready => _readyCompleter.future;

  /// Wait for connection to leave `connecting` state with a timeout.
  ///
  /// Sets [connectionError] on timeout. No-op if not currently connecting.
  /// Shared by desktop and mobile views to avoid duplicated wait logic.
  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 30)}) async {
    if (!isConnecting) return;
    try {
      await ready.timeout(timeout);
    } on TimeoutException {
      connectionError = 'Connection timed out after ${timeout.inSeconds} seconds';
    }
  }

  /// Mark connection attempt as resolved. Called by [ConnectionManager].
  void completeReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }
}
