import '../../src/rust/api/bus.dart' as rust_bus;
import '../ssh/ssh_config.dart';
import '../ssh/transport/ssh_transport.dart';
import 'connection.dart';
import 'connection_step.dart';

/// Map the FRB-mirrored phase enum to the Dart enum the UI
/// renders against. Lives in its own file so callers that don't
/// touch the FRB bus events (pure data tests / value-type
/// fixtures) can import `connection_step.dart` without pulling
/// in the FRB native-lib dependency.
ConnectionPhase mapBusPhase(rust_bus.BusConnectionPhase phase) {
  return switch (phase) {
    rust_bus.BusConnectionPhase.socketConnect => ConnectionPhase.socketConnect,
    rust_bus.BusConnectionPhase.hostKeyVerify => ConnectionPhase.hostKeyVerify,
    rust_bus.BusConnectionPhase.authenticate => ConnectionPhase.authenticate,
    rust_bus.BusConnectionPhase.openChannel => ConnectionPhase.openChannel,
  };
}

/// Map the FRB-mirrored step-status enum to the Dart enum.
StepStatus mapBusStatus(rust_bus.BusStepStatus status) {
  return switch (status) {
    rust_bus.BusStepStatus.inProgress => StepStatus.inProgress,
    rust_bus.BusStepStatus.success => StepStatus.success,
    rust_bus.BusStepStatus.failed => StepStatus.failed,
  };
}

/// Translate the Dart [SshAuthMethod] sealed family into the
/// FRB-mirrored bus connect-auth ref. Pure mapping — extracted
/// from `ConnectionsNotifier` so the per-tier auth-ref construction
/// lives alongside the phase / status mappers.
rust_bus.BusConnectAuthRef busAuthRef(SshAuthMethod auth) {
  return switch (auth) {
    SshAuthPasswordRef(:final passwordSecretId) =>
      rust_bus.BusConnectAuthRef.password(secretId: passwordSecretId),
    SshAuthPubkeyRef(:final keySecretId, :final passphraseSecretId) =>
      rust_bus.BusConnectAuthRef.pubkey(
        keySecretId: keySecretId,
        passphraseSecretId: passphraseSecretId,
      ),
    SshAuthPubkeyCertRef(
      :final keySecretId,
      :final certSecretId,
      :final passphraseSecretId,
    ) =>
      rust_bus.BusConnectAuthRef.pubkeyCert(
        keySecretId: keySecretId,
        certSecretId: certSecretId,
        passphraseSecretId: passphraseSecretId,
      ),
    SshAuthAgent() => const rust_bus.BusConnectAuthRef.agent(),
  };
}

/// Build the FRB-mirrored bus connect args from a [Connection] +
/// [SSHConfig] + resolved [SshAuthMethod]. Pure mapping — used by
/// `ConnectionsNotifier._doConnect` to feed the Rust connect actor.
rust_bus.BusConnectArgs busConnectArgs(
  Connection conn,
  SSHConfig config,
  SshAuthMethod auth,
) {
  return rust_bus.BusConnectArgs(
    label: conn.label,
    sessionId: conn.sessionId,
    host: config.host,
    port: config.port,
    user: config.user,
    auth: busAuthRef(auth),
    bastionId: conn.bastion?.id,
    internal: conn.internal,
  );
}
