/// Phases of an SSH connection attempt.
enum ConnectionPhase {
  /// Opening TCP socket to host:port.
  socketConnect,

  /// Verifying server host key (TOFU / known_hosts).
  hostKeyVerify,

  /// Authenticating (password / key).
  authenticate,

  /// Opening channel (shell or SFTP subsystem).
  openChannel,
}

/// Status of a single connection phase.
enum StepStatus {
  /// Phase has started but not yet completed.
  inProgress,

  /// Phase completed successfully.
  success,

  /// Phase failed.
  failed,
}

/// A single progress step emitted during SSH connection.
class ConnectionStep {
  final ConnectionPhase phase;
  final StepStatus status;

  /// Optional detail string — e.g. auth method, error message.
  final String? detail;

  const ConnectionStep({
    required this.phase,
    required this.status,
    this.detail,
  });

  @override
  String toString() => 'ConnectionStep($phase, $status, $detail)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStep &&
          phase == other.phase &&
          status == other.status &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(phase, status, detail);
}
