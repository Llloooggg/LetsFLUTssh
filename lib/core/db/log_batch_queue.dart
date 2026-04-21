import 'dart:async';

/// Batched queue for log-event records destined for the encrypted DB's
/// `app_logs` table.
///
/// Two flush triggers, whichever comes first:
///   * size — 100 events queued (configurable via [maxBatchSize]);
///   * time — 500 ms since the first event of the current batch
///     (configurable via [flushInterval]).
///
/// The class is storage-agnostic — the caller hands it a
/// `Future<void> Function(List<T> batch)` flush callback. The file
/// writer in [AppLogger] wires this to the drift DAO once the DB is
/// unlocked; before the DB is unlocked, events land in
/// [BootstrapLogBuffer] instead (see companion file).
///
/// The queue does NOT itself talk to drift so it stays testable in pure
/// Dart and is safe to drive from any isolate.
class LogBatchQueue<T> {
  LogBatchQueue({
    required Future<void> Function(List<T> batch) flush,
    this.maxBatchSize = 100,
    this.flushInterval = const Duration(milliseconds: 500),
  }) : _flush = flush;

  final Future<void> Function(List<T> batch) _flush;
  final int maxBatchSize;
  final Duration flushInterval;

  final List<T> _buffer = [];
  Timer? _timer;
  bool _flushing = false;
  bool _disposed = false;

  /// Number of events currently waiting to be flushed.
  int get length => _buffer.length;

  /// Add [event] to the current batch. Fires an immediate flush when
  /// [maxBatchSize] is reached, otherwise arms the time-based trigger
  /// if it is not already running.
  void add(T event) {
    if (_disposed) return;
    _buffer.add(event);
    if (_buffer.length >= maxBatchSize) {
      // Cancel the pending time-based flush — we are beating it.
      _timer?.cancel();
      _timer = null;
      unawaited(_drain());
      return;
    }
    _timer ??= Timer(flushInterval, () {
      _timer = null;
      unawaited(_drain());
    });
  }

  /// Force an immediate flush of the current batch. Safe to call from
  /// shutdown / `dispose()` paths — returns the same future the
  /// internal flush would have returned.
  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;
    return _drain();
  }

  /// Stop accepting new events, flush the last batch, and drop the
  /// reference to the flush callback. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await flushNow();
  }

  Future<void> _drain() async {
    if (_buffer.isEmpty) return;
    if (_flushing) return; // serialise overlapping calls
    _flushing = true;
    final batch = List<T>.from(_buffer);
    _buffer.clear();
    try {
      await _flush(batch);
    } catch (_) {
      // On flush failure put the batch back at the front of the queue
      // so the next trigger retries it.
      _buffer.insertAll(0, batch);
      rethrow;
    } finally {
      _flushing = false;
    }
  }
}
