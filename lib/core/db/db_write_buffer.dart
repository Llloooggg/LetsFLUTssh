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
/// Cap is a hard safety rail — 500 rows across all tables is enough for
/// the realistic auto-lock window (minutes) and small enough that the
/// RAM footprint stays bounded. Hitting the cap drops the oldest entry
/// (FIFO eviction) and logs a warning; write-loss is preferable to an
/// unbounded RAM-pressure build-up while the user is away from the
/// desk. A production-visible cap-hit is itself a signal that the
/// encrypted log sink (or whatever high-volume writer triggered it)
/// needs its own flush policy.
///
/// This class is intentionally storage-agnostic — it accepts `Future
/// Function(AppDatabase)` callbacks so the caller owns the exact
/// `INSERT … ` / `UPDATE …` it wants replayed. Drift already batches
/// operations inside `transaction` cleanly; the buffer is just a FIFO
/// that hands each queued closure to drift at replay time.
class DbWriteBuffer {
  DbWriteBuffer({int maxEntries = 500}) : _maxEntries = maxEntries;

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
  /// On any error the transaction rolls back and the queue is
  /// preserved for a follow-up retry; a permanent failure should not
  /// silently eat pending writes.
  Future<void> drain(AppDatabase db) async {
    if (_queue.isEmpty) return;
    final pending = List<Future<void> Function(AppDatabase)>.from(_queue);
    try {
      await db.transaction(() async {
        for (final op in pending) {
          await op(db);
        }
      });
      _queue.clear();
      AppLogger.instance.log(
        'DbWriteBuffer drained ${pending.length} queued writes',
        name: 'DbWriteBuffer',
      );
    } catch (e) {
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
