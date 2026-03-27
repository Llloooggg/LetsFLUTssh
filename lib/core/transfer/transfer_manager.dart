import 'dart:async';

import '../../utils/logger.dart';
import 'transfer_task.dart';

/// Transfer queue manager with configurable parallel workers.
class TransferManager {
  final int parallelism;
  final int maxHistory;
  final Duration taskTimeout;

  final _queue = <_QueueEntry>[];
  final _history = <HistoryEntry>[];
  int _running = 0;
  int _counter = 0;
  bool _disposed = false;

  final _controller = StreamController<void>.broadcast();

  /// Fires on any state change (queue/history update).
  Stream<void> get onChange => _controller.stream;

  /// Per-task active transfer info, keyed by task ID.
  final _activeTransfers = <String, String>{};

  /// Active timeout timers — cancelled on dispose.
  final _timeoutTimers = <String, Timer>{};

  /// Current active transfer info (name + percent) for status bar.
  /// Shows the most recently updated active transfer.
  String? get currentTransferInfo =>
      _activeTransfers.isNotEmpty ? _activeTransfers.values.last : null;

  TransferManager({
    this.parallelism = 2,
    this.maxHistory = 500,
    this.taskTimeout = const Duration(minutes: 30),
  });

  List<HistoryEntry> get history => List.unmodifiable(_history);

  int get queueLength => _queue.length;
  int get runningCount => _running;

  /// Enqueue a transfer task. Returns task ID.
  String enqueue(TransferTask task) {
    _counter++;
    final id = 'tr-$_counter';
    final entry = _QueueEntry(id: id, task: task, createdAt: DateTime.now());
    _queue.add(entry);
    AppLogger.instance.log('Enqueued: ${task.name} (${task.direction.name})', name: 'Transfer');
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
    AppLogger.instance.log('Started: ${entry.task.name}', name: 'Transfer');

    try {
      final taskFuture = entry.task.run((percent, message) {
        lastPercent = percent;
        lastMessage = message;
        _activeTransfers[entry.id] = '${entry.task.name} ${percent.toStringAsFixed(0)}%';
        _notify();
      });

      // When taskTimeout > Duration.zero, race the task against a timer.
      if (taskTimeout > Duration.zero) {
        final completer = Completer<void>();
        final timer = Timer(taskTimeout, () {
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException(
              'Transfer timed out after ${taskTimeout.inMinutes} minutes',
              taskTimeout,
            ));
          }
        });
        _timeoutTimers[entry.id] = timer;
        unawaited(taskFuture.then(
          (_) { if (!completer.isCompleted) completer.complete(); },
          onError: (Object e) { if (!completer.isCompleted) completer.completeError(e); },
        ));
        await completer.future;
      } else {
        await taskFuture;
      }

      AppLogger.instance.log('Completed: ${entry.task.name}', name: 'Transfer');
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
      AppLogger.instance.log('Failed: ${entry.task.name}: $e', name: 'Transfer', error: e);
      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.failed,
        error: _sanitizeError(e),
        lastPercent: lastPercent,
        lastMessage: lastMessage,
        createdAt: entry.createdAt,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        sizeBytes: entry.task.sizeBytes,
      ));
    } finally {
      _timeoutTimers.remove(entry.id)?.cancel();
      _running--;
      _activeTransfers.remove(entry.id);
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

  /// Strip absolute file paths from error messages to avoid leaking
  /// directory structure in UI.
  String _sanitizeError(Object e) {
    return e.toString().replaceAll(RegExp(r'[/\\]\S+'), '<path>');
  }

  void _notify() {
    if (!_disposed) {
      _controller.add(null);
    }
  }

  void dispose() {
    _disposed = true;
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();
    _controller.close();
  }
}

class _QueueEntry {
  final String id;
  final TransferTask task;
  final DateTime createdAt;

  _QueueEntry({required this.id, required this.task, required this.createdAt});
}
