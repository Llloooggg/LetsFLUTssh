/// Direction of a file transfer.
enum TransferDirection { upload, download }

/// Status of a transfer.
enum TransferStatus { queued, running, completed, failed }

/// A single transfer task to be executed by the manager.
class TransferTask {
  final String name;
  final TransferDirection direction;
  final String sourcePath;
  final String targetPath;
  final Future<void> Function(void Function(double percent, String message) update) run;

  const TransferTask({
    required this.name,
    required this.direction,
    required this.sourcePath,
    required this.targetPath,
    required this.run,
  });
}

/// Completed/failed transfer history entry.
class HistoryEntry {
  final String id;
  final String name;
  final TransferDirection direction;
  final String sourcePath;
  final String targetPath;
  final TransferStatus status;
  final String? error;
  final double lastPercent;
  final String lastMessage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  const HistoryEntry({
    required this.id,
    required this.name,
    required this.direction,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    this.error,
    this.lastPercent = 0,
    this.lastMessage = '',
    required this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  Duration? get duration =>
      startedAt != null && endedAt != null
          ? endedAt!.difference(startedAt!)
          : null;

  String get directionIcon => direction == TransferDirection.upload ? '↑' : '↓';
}
