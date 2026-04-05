/// Direction of a file transfer.
enum TransferDirection { upload, download }

/// Status of a transfer.
enum TransferStatus { queued, running, completed, failed, cancelled }

/// A single transfer task to be executed by the manager.
class TransferTask {
  final String name;
  final TransferDirection direction;
  final String sourcePath;
  final String targetPath;
  final int sizeBytes;
  final Future<void> Function(
    void Function(double percent, String message) update,
  )
  run;

  const TransferTask({
    required this.name,
    required this.direction,
    required this.sourcePath,
    required this.targetPath,
    this.sizeBytes = 0,
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
  final int sizeBytes;

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
    this.sizeBytes = 0,
  });

  Duration? get duration => startedAt != null && endedAt != null
      ? endedAt!.difference(startedAt!)
      : null;

  String get directionIcon => direction == TransferDirection.upload ? '↑' : '↓';
}

/// In-progress or queued transfer entry for UI display.
class ActiveEntry {
  final String id;
  final String name;
  final TransferDirection direction;
  final String sourcePath;
  final String targetPath;
  final TransferStatus status;
  final double percent;
  final String message;

  const ActiveEntry({
    required this.id,
    required this.name,
    required this.direction,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    this.percent = 0,
    this.message = '',
  });

  String get directionIcon => direction == TransferDirection.upload ? '↑' : '↓';
}
