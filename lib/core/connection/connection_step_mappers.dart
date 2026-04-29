import '../../src/rust/api/bus.dart' as rust_bus;
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
