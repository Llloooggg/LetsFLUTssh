import 'dart:async';

import '../../utils/logger.dart';
import 'connection.dart';
import 'connection_step.dart';

/// Per-consumer progress tracker that merges shared [Connection] transport
/// steps with consumer-local channel steps (e.g. "Opening shell" or
/// "Opening SFTP channel").
///
/// Each terminal pane or SFTP tab creates its own [ProgressTracker].
/// Shared transport steps (socket, host-key, auth) flow through
/// [Connection.progressStream]; channel-specific steps stay local and
/// never pollute the shared stream.
class ProgressTracker {
  final Connection connection;

  final _mergedHistory = <ConnectionStep>[];
  final _controller = StreamController<ConnectionStep>.broadcast();
  StreamSubscription<ConnectionStep>? _connectionSub;

  ProgressTracker(this.connection) {
    // Replay existing shared history (handles late subscription)
    for (final step in connection.progressHistory) {
      _mergedHistory.add(step);
      _logStep(step);
    }
    // Listen for new shared steps
    _connectionSub = connection.progressStream.listen((step) {
      _mergedHistory.add(step);
      _logStep(step);
      if (!_controller.isClosed) _controller.add(step);
    });
  }

  /// All steps seen so far (shared + local), in order.
  List<ConnectionStep> get history => List.unmodifiable(_mergedHistory);

  /// Merged stream of shared + local steps.
  Stream<ConnectionStep> get stream => _controller.stream;

  /// Add a consumer-local step (e.g. "Opening SFTP channel").
  /// Does NOT propagate to [Connection.progressStream].
  void addLocalStep(ConnectionStep step) {
    _mergedHistory.add(step);
    _logStep(step);
    if (!_controller.isClosed) _controller.add(step);
  }

  void _logStep(ConnectionStep step) {
    final status = '${step.phase.name}: ${step.status.name}';
    AppLogger.instance.log('[${connection.id}] $status', name: 'Progress');
  }

  void dispose() {
    _connectionSub?.cancel();
    if (!_controller.isClosed) _controller.close();
  }
}
