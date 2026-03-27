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

  /// Per-task progress data for UI, keyed by task ID.
  final _activeProgress = <String, _ActiveProgressData>{};

  /// Active timeout timers — cancelled on dispose.
  final _timeoutTimers = <String, Timer>{};

  /// IDs of tasks that have been cancelled — checked during execution.
  final _cancelledIds = <String>{};

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

  /// Active + queued entries for UI display.
  List<ActiveEntry> get activeEntries {
    return _activeProgress.entries.map((e) {
      final d = e.value;
      final isRunning = _activeTransfers.containsKey(e.key);
      return ActiveEntry(
        id: e.key,
        name: d.task.name,
        direction: d.task.direction,
        sourcePath: d.task.sourcePath,
        targetPath: d.task.targetPath,
        status: isRunning ? TransferStatus.running : TransferStatus.queued,
        percent: d.percent,
        message: d.message,
      );
    }).toList();
  }

  /// Enqueue a transfer task. Returns task ID.
  String enqueue(TransferTask task) {
    _counter++;
    final id = 'tr-$_counter';
    final entry = _QueueEntry(id: id, task: task, createdAt: DateTime.now());
    _queue.add(entry);
    _activeProgress[id] = _ActiveProgressData(task: task, createdAt: DateTime.now());
    AppLogger.instance.log('Enqueued: ${task.name} (${task.direction.name})', name: 'Transfer');
    _notify();
    _processQueue();
    return id;
  }

  /// Cancel a queued or running transfer by ID.
  /// Queued tasks are removed immediately. Running tasks are marked for
  /// cancellation — the next progress callback check will abort them.
  bool cancel(String id) {
    // Try removing from queue first
    final qIdx = _queue.indexWhere((e) => e.id == id);
    if (qIdx >= 0) {
      final entry = _queue.removeAt(qIdx);
      _activeProgress.remove(id);
      AppLogger.instance.log('Cancelled (queued): ${entry.task.name}', name: 'Transfer');
      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.cancelled,
        createdAt: entry.createdAt,
        endedAt: DateTime.now(),
      ));
      _notify();
      return true;
    }

    // Mark running task for cancellation
    if (_activeTransfers.containsKey(id)) {
      _cancelledIds.add(id);
      AppLogger.instance.log('Cancel requested: $id', name: 'Transfer');
      return true;
    }

    return false;
  }

  /// Cancel all queued and running transfers.
  void cancelAll() {
    // Cancel all queued
    for (final entry in _queue) {
      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.cancelled,
        createdAt: entry.createdAt,
        endedAt: DateTime.now(),
      ));
    }
    _queue.clear();

    // Mark all running for cancellation
    _cancelledIds.addAll(_activeTransfers.keys);

    // Clean up queued progress (running ones are cleaned in _executeTask finally)
    _activeProgress.removeWhere((id, _) => !_activeTransfers.containsKey(id));

    _notify();
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
        // Check cancellation on each progress callback
        if (_cancelledIds.contains(entry.id)) {
          throw const _CancelledException();
        }
        lastPercent = percent;
        lastMessage = message;
        _activeTransfers[entry.id] = '${entry.task.name} ${percent.toStringAsFixed(0)}%';
        final progress = _activeProgress[entry.id];
        if (progress != null) {
          progress.percent = percent;
          progress.message = message;
        }
        _notify();
      });

      await _awaitWithTimeout(taskFuture, entry.id);

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
    } on _CancelledException {
      AppLogger.instance.log('Cancelled: ${entry.task.name}', name: 'Transfer');
      _addHistory(HistoryEntry(
        id: entry.id,
        name: entry.task.name,
        direction: entry.task.direction,
        sourcePath: entry.task.sourcePath,
        targetPath: entry.task.targetPath,
        status: TransferStatus.cancelled,
        lastPercent: lastPercent,
        lastMessage: 'Cancelled',
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
      _cancelledIds.remove(entry.id);
      _timeoutTimers.remove(entry.id)?.cancel();
      _running--;
      _activeTransfers.remove(entry.id);
      _activeProgress.remove(entry.id);
      _notify();
      _processQueue();
    }
  }

  Future<void> _awaitWithTimeout(Future<void> taskFuture, String entryId) async {
    if (taskTimeout <= Duration.zero) {
      await taskFuture;
      return;
    }
    final completer = Completer<void>();
    final timer = Timer(taskTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(
          'Transfer timed out after ${taskTimeout.inMinutes} minutes',
          taskTimeout,
        ));
      }
    });
    _timeoutTimers[entryId] = timer;
    unawaited(taskFuture.then(
      (_) { if (!completer.isCompleted) completer.complete(); },
      onError: (Object e) { if (!completer.isCompleted) completer.completeError(e); },
    ));
    await completer.future;
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
    return e.toString().replaceAll(RegExp(r'(?:[/\\][^\s/\\]+)+'), '<path>');
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

/// Internal exception thrown when a running task detects cancellation.
class _CancelledException implements Exception {
  const _CancelledException();
}

/// Progress data for an active transfer, tracked internally.
class _ActiveProgressData {
  final TransferTask task;
  final DateTime createdAt;
  double percent = 0;
  String message = 'Queued';

  _ActiveProgressData({required this.task, required this.createdAt});
}
