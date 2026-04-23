import 'dart:async';

import '../../utils/logger.dart';
import 'database.dart';

/// In-memory queue of deferred DB writes that accumulate while the app
/// is auto-locked.
///
/// Design: when the auto-lock timer fires and the database handle is
/// closed to evict the cipher state from RAM, any live SSH/SFTP session
/// isolate that tries to append a row (usage stat, log event once the
/// encrypted log sink lands, etc.) must not fail. Writers route their
/// operation through [append]; on unlock, [drain] replays the queued
/// operations inside a single transaction against the freshly re-opened
/// database.
///
/// Cap is a hard safety rail — 5000 rows across all tables is generous
/// for realistic auto-lock windows (minutes to tens of minutes) while
/// keeping the RAM footprint bounded. Hitting the cap drops the oldest
/// entry (FIFO eviction) and logs a warning; write-loss is preferable
/// to an unbounded RAM-pressure build-up while the user is away from
/// the desk. A production-visible cap-hit is itself a signal that the
/// encrypted log sink (or whatever high-volume writer triggered it)
/// needs its own flush policy.
///
/// Cap sizing history. The initial 500 was sized for usage-stat rows
/// accrued while the user was idle and assumed the buffer's only
/// consumer would be low-volume per-session telemetry. The intended
/// follow-on consumer is an encrypted log sink, which can burst well
/// past 500 entries/second during verbose SSH handshakes or stack
/// traces; at 500 cap and a few-hundred-ms drain window the FIFO
/// eviction silently ate a majority of log lines, which is exactly
/// the audit-trail outcome the sink exists to preserve. 5000 entries
/// × ~100 bytes per captured closure + arguments ≈ 500 KB headroom,
/// which fits comfortably inside the auto-lock RAM budget that already
/// holds xterm ring buffers and SFTP queues.
///
/// This class is intentionally storage-agnostic — it accepts `Future
/// Function(AppDatabase)` callbacks so the caller owns the exact
/// `INSERT … ` / `UPDATE …` it wants replayed. Drift already batches
/// operations inside `transaction` cleanly; the buffer is just a FIFO
/// that hands each queued closure to drift at replay time.
class DbWriteBuffer {
  DbWriteBuffer({int maxEntries = 5000}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final List<Future<void> Function(AppDatabase db)> _queue = [];

  /// Number of operations currently queued.
  int get length => _queue.length;

  /// True when the queue is empty (tests + the unlock replay short-
  /// circuit on this).
  bool get isEmpty => _queue.isEmpty;

  /// Queue a deferred write. [op] is invoked with the live database
  /// handle on the next [drain] call. Returns true when the op was
  /// accepted; false when the cap was hit and the oldest entry had to
  /// be dropped to make room.
  bool append(Future<void> Function(AppDatabase db) op) {
    if (_queue.length >= _maxEntries) {
      _queue.removeAt(0);
      _queue.add(op);
      AppLogger.instance.log(
        'DbWriteBuffer cap hit ($_maxEntries) — oldest entry dropped',
        name: 'DbWriteBuffer',
      );
      return false;
    }
    _queue.add(op);
    return true;
  }

  /// Replay every queued op against [db] inside a single transaction.
  /// On any error the transaction rolls back and the captured batch is
  /// prepended back onto the queue for a follow-up retry; a permanent
  /// failure should not silently eat pending writes.
  ///
  /// **Ordering invariant**: the queue is pulled to an empty state
  /// *before* the transaction opens. Any `append` that fires while the
  /// transaction awaits lands in the now-empty `_queue` and will be
  /// picked up by the next `drain`. A prior version snapshotted the
  /// queue and then called `_queue.clear()` after the commit, which
  /// silently dropped every op that arrived mid-drain (single-isolate
  /// Dart still interleaves at every `await` boundary). It also
  /// mis-handled the cap-eviction path: if a flood filled the queue
  /// past `_maxEntries` during the drain, `clear()` would wipe the
  /// evicted-but-rotated-in survivors that the append path had never
  /// meant to discard.
  Future<void> drain(AppDatabase db) async {
    if (_queue.isEmpty) return;
    final pending = List<Future<void> Function(AppDatabase)>.from(_queue);
    _queue.clear();
    try {
      await db.transaction(() async {
        for (final op in pending) {
          await op(db);
        }
      });
      AppLogger.instance.log(
        'DbWriteBuffer drained ${pending.length} queued writes',
        name: 'DbWriteBuffer',
      );
    } catch (e) {
      _queue.insertAll(0, pending);
      AppLogger.instance.log(
        'DbWriteBuffer drain failed, queue preserved: $e',
        name: 'DbWriteBuffer',
      );
      rethrow;
    }
  }

  /// Explicit reset — used by the unlock-failure path to discard
  /// writes that are bound to a DB the user will never re-open (e.g.
  /// master password cycled, old key gone).
  void clear() {
    _queue.clear();
  }
}
