/// Ring buffer for log events generated during the app's bootstrap
/// window — the gap between process start and the moment the encrypted
/// DB is unlocked + the `app_logs` DAO is available.
///
/// The project's goal is that the *file* log target is active **only**
/// during bootstrap, never after the DB is unlocked. Bootstrap is
/// usually a couple of seconds; a short ring buffer is enough to hold
/// the events and makes sure nothing is lost on the hand-off to the
/// DB-backed [LogBatchQueue].
///
/// Semantics:
///   * [capacity] is a soft cap — the buffer discards the *oldest*
///     entry when a new one would overflow. Bootstrap should not
///     produce more than a few hundred events even in pathological
///     cases (retry loops, import-on-launch, etc.), and losing the
///     very first init line is strictly better than losing the crash
///     reason that surfaced seconds later.
///   * [drainTo] empties the buffer into the caller's sink in FIFO
///     order. Used once the DB-backed sink is live.
class BootstrapLogBuffer<T> {
  BootstrapLogBuffer({this.capacity = 512});

  final int capacity;
  final List<T> _ring = [];
  int _start = 0; // index of the oldest element
  int _count = 0;

  int get length => _count;
  bool get isEmpty => _count == 0;

  /// Append [event]. Drops the oldest entry when at [capacity].
  void add(T event) {
    if (_count < capacity) {
      _ring.add(event);
      _count++;
      return;
    }
    // At capacity — overwrite oldest, advance the ring head.
    _ring[(_start + _count) % capacity] = event;
    _start = (_start + 1) % capacity;
  }

  /// Hand every buffered event, in FIFO order, to [sink] and clear the
  /// buffer afterwards. Typically called once with the DB-backed
  /// [LogBatchQueue.add] so the bootstrap events land in the same
  /// `app_logs` table as every subsequent event.
  void drainTo(void Function(T event) sink) {
    for (var i = 0; i < _count; i++) {
      final idx = (_start + i) % _ring.length;
      sink(_ring[idx]);
    }
    _ring.clear();
    _start = 0;
    _count = 0;
  }
}
