import 'dart:async';

import 'transfer_task.dart';

/// Transfer queue manager with configurable parallel workers.
class TransferManager {
  final int parallelism;
  final int maxHistory;

  final _queue = <_QueueEntry>[];
  final _history = <HistoryEntry>[];
  int _running = 0;
  int _counter = 0;

  final _controller = StreamController<void>.broadcast();

  /// Fires on any state change (queue/history update).
  Stream<void> get onChange => _controller.stream;

  /// Current active transfer info (name + percent) for status bar.
  String? currentTransferInfo;

  TransferManager({this.parallelism = 2, this.maxHistory = 500});

  List<HistoryEntry> get history => List.unmodifiable(_history);

  int get queueLength => _queue.length;
  int get runningCount => _running;

  /// Enqueue a transfer task. Returns task ID.
  String enqueue(TransferTask task) {
    _counter++;
    final id = 'tr-$_counter';
    final entry = _QueueEntry(id: id, task: task, createdAt: DateTime.now());
    _queue.add(entry);
    _notify();
    _processQueue();
    return id;
  }

  void clearHistory() {
    _history.clear();
    _notify();
  }

  void deleteHistory(List<String> ids) {
    _history.removeWhere((e) => ids.contains(e.id));
    _notify();
  }

  Future<void> _processQueue() async {
    while (_running < parallelism && _queue.isNotEmpty) {
      final entry = _queue.removeAt(0);
      _running++;
      _notify();
      _executeTask(entry);
    }
  }

  Future<void> _executeTask(_QueueEntry entry) async {
    final startedAt = DateTime.now();
    var lastPercent = 0.0;
    var lastMessage = '';

    try {
      await entry.task.run((percent, message) {
        lastPercent = percent;
        lastMessage = message;
        currentTransferInfo = '${entry.task.name} ${percent.toStringAsFixed(0)}%';
        _notify();
      });

      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.completed,
        lastPercent: 100,
        lastMessage: 'Done',
        createdAt: entry.createdAt,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        sizeBytes: entry.task.sizeBytes,
      ));
    } catch (e) {
      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.failed,
        error: e.toString(),
        lastPercent: lastPercent,
        lastMessage: lastMessage,
        createdAt: entry.createdAt,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        sizeBytes: entry.task.sizeBytes,
      ));
    } finally {
      _running--;
      currentTransferInfo = null;
      _notify();
      _processQueue();
    }
  }

  void _addHistory(HistoryEntry entry) {
    _history.insert(0, entry); // newest first
    if (_history.length > maxHistory) {
      _history.removeRange(maxHistory, _history.length);
    }
  }

  void _notify() {
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

class _QueueEntry {
  final String id;
  final TransferTask task;
  final DateTime createdAt;

  _QueueEntry({required this.id, required this.task, required this.createdAt});
}
