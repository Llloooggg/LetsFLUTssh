import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/bus/app_bus.dart';
import '../core/transfer/transfer_task.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/path.dart' as rust_path;
import '../src/rust/api/transfer.dart' as rust_transfer;
import '../utils/logger.dart';

/// Combined snapshot of every transfer slice the UI consumes — history
/// list, active queue/running rows, and the rolled-up status counters.
/// Held inside the [TransfersNotifier] so a single state update fans
/// out to every selector in lockstep.
class TransfersState {
  const TransfersState({
    this.history = const [],
    this.active = const [],
    this.status = const ActiveTransferState(),
  });

  final List<HistoryEntry> history;
  final List<ActiveEntry> active;
  final ActiveTransferState status;
}

/// Snapshot of active transfer state (running/queued counts + a
/// human-readable summary for the panel header).
class ActiveTransferState {
  final int running;
  final int queued;
  final String? currentInfo;

  const ActiveTransferState({
    this.running = 0,
    this.queued = 0,
    this.currentInfo,
  });

  bool get hasActive => running > 0 || queued > 0;
}

/// Single source of truth for the SFTP transfer queue. Owns the bus
/// subscription, the FRB enqueue/cancel/clear pipeline, and the
/// derived view of `lfs_core::transfer::TransferQueue`.
///
/// Replaces the prior two-tier `Provider<TransferManager>` +
/// three `StreamProvider`s. The Rust side still owns scheduling,
/// concurrency, chunked SFTP streaming, and cancellation tokens —
/// this Notifier mirrors a snapshot for the UI and dispatches
/// commands over FRB.
final transfersProvider = NotifierProvider<TransfersNotifier, TransfersState>(
  TransfersNotifier.new,
);

/// Reactive transfer history (selector over [transfersProvider]).
final transferHistoryProvider = Provider<List<HistoryEntry>>(
  (ref) => ref.watch(transfersProvider).history,
);

/// Reactive active/queued transfer entries for UI display.
final activeTransfersProvider = Provider<List<ActiveEntry>>(
  (ref) => ref.watch(transfersProvider).active,
);

/// Reactive transfer status (running count, queue length, current info).
final transferStatusProvider = Provider<ActiveTransferState>(
  (ref) => ref.watch(transfersProvider).status,
);

class TransfersNotifier extends Notifier<TransfersState> {
  StreamSubscription<rust_bus.BusEvent>? _busSub;
  Future<void>? _pendingRefresh;
  bool _disposed = false;

  @override
  TransfersState build() {
    try {
      _busSub = AppBus.instance.subscribe(rust_bus.BusTopic.transfer).listen((
        event,
      ) {
        if (event is rust_bus.BusEvent_TransferTaskAdded ||
            event is rust_bus.BusEvent_TransferTaskState ||
            event is rust_bus.BusEvent_TransferTaskProgress ||
            event is rust_bus.BusEvent_TransferTaskError) {
          _scheduleRefresh();
        }
      });
    } catch (e) {
      AppLogger.instance.log(
        'TransfersNotifier bus subscribe failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
    }
    ref.onDispose(() {
      _disposed = true;
      unawaited(_busSub?.cancel());
      _busSub = null;
    });
    _scheduleRefresh();
    return const TransfersState();
  }

  /// Enqueue a download from `remotePath` on the SFTP session bound
  /// to `connectionId` to `localPath`. Returns the assigned task id
  /// so callers can track / cancel later.
  Future<String> enqueueDownload({
    required String connectionId,
    required String name,
    required String remotePath,
    required String localPath,
    int sizeBytes = 0,
  }) async {
    final id = const Uuid().v4();
    AppLogger.instance.log(
      'Enqueue download: $remotePath → $localPath',
      name: 'Transfer',
    );
    try {
      await rust_transfer.transferEnqueue(
        id: id,
        kind: rust_transfer.DbTransferKind.download,
        sessionId: connectionId,
        remotePath: remotePath,
        localPath: localPath,
        bytesTotal: BigInt.from(sizeBytes),
      );
    } catch (e) {
      AppLogger.instance.log(
        'transferEnqueue download failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
    }
    return id;
  }

  /// Enqueue an upload from `localPath` to `remotePath` on the SFTP
  /// session bound to `connectionId`. Same shape as
  /// [enqueueDownload].
  Future<String> enqueueUpload({
    required String connectionId,
    required String name,
    required String localPath,
    required String remotePath,
    int sizeBytes = 0,
  }) async {
    final id = const Uuid().v4();
    AppLogger.instance.log(
      'Enqueue upload: $localPath → $remotePath',
      name: 'Transfer',
    );
    try {
      await rust_transfer.transferEnqueue(
        id: id,
        kind: rust_transfer.DbTransferKind.upload,
        sessionId: connectionId,
        remotePath: remotePath,
        localPath: localPath,
        bytesTotal: BigInt.from(sizeBytes),
      );
    } catch (e) {
      AppLogger.instance.log(
        'transferEnqueue upload failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
    }
    return id;
  }

  /// Cancel a running / queued task by id. Idempotent on a missing
  /// id (already finished).
  Future<bool> cancel(String id) async {
    try {
      return await rust_transfer.transferCancel(taskId: id);
    } catch (e) {
      AppLogger.instance.log(
        'transferCancel failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
      return false;
    }
  }

  /// Cancel every active task. Walks the snapshot and cancels each
  /// non-terminal entry one-shot.
  void cancelAll() {
    unawaited(_cancelAllAsync());
  }

  Future<void> _cancelAllAsync() async {
    final snapshots = await _safeSnapshot();
    for (final s in snapshots) {
      if (_isActive(s.state)) {
        unawaited(cancel(s.id));
      }
    }
  }

  /// Drop every terminal (Completed / Failed / Cancelled) entry
  /// from the registry.
  Future<void> clearHistory() async {
    try {
      await rust_transfer.transferClearHistory();
    } catch (e) {
      AppLogger.instance.log(
        'transferClearHistory failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
    }
  }

  /// Drop a specific set of terminal tasks. Used by the panel's
  /// per-row delete action.
  Future<void> deleteHistory(List<String> ids) async {
    for (final id in ids) {
      try {
        await rust_transfer.transferDropTerminal(taskId: id);
      } catch (e) {
        AppLogger.instance.log(
          'transferDropTerminal($id) failed: $e',
          name: 'Transfer',
          level: LogLevel.warn,
        );
      }
    }
  }

  /// Schedule a refresh for the next microtask. Multiple events in
  /// the same tick coalesce to one snapshot call so a download
  /// progress storm doesn't fan out into N FRB round-trips.
  void _scheduleRefresh() {
    if (_disposed) return;
    if (_pendingRefresh != null) return;
    _pendingRefresh = Future.microtask(() async {
      _pendingRefresh = null;
      await _doRefresh();
    });
  }

  Future<void> _doRefresh() async {
    if (_disposed) return;
    final snapshots = await _safeSnapshot();
    if (_disposed) return;
    final history = <HistoryEntry>[];
    final active = <ActiveEntry>[];
    var running = 0;
    var queued = 0;
    String? current;
    for (final s in snapshots) {
      final dir = s.kind == rust_transfer.DbTransferKind.upload
          ? TransferDirection.upload
          : TransferDirection.download;
      final source = dir == TransferDirection.upload
          ? s.localPath
          : s.remotePath;
      final target = dir == TransferDirection.upload
          ? s.remotePath
          : s.localPath;
      final name = _displayName(target);
      final percent = s.bytesTotal > BigInt.zero
          ? (s.bytesDone.toDouble() / s.bytesTotal.toDouble()) * 100.0
          : 0.0;
      switch (s.state) {
        case rust_transfer.DbTransferState.queued:
          queued++;
          active.add(
            ActiveEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.queued,
              percent: percent,
              // Localised label is resolved at render time off the
              // status enum; carrying an English-only literal here
              // would leak through to RTL / non-EN locales.
              message: '',
            ),
          );
        case rust_transfer.DbTransferState.running:
          running++;
          current = '$name ${percent.toStringAsFixed(0)}%';
          active.add(
            ActiveEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.running,
              percent: percent,
              message: '${s.bytesDone.toString()}/${s.bytesTotal.toString()}',
            ),
          );
        case rust_transfer.DbTransferState.completed:
          history.add(
            HistoryEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.completed,
              lastPercent: 100,
              lastMessage: 'Done',
              createdAt: DateTime.now(),
              sizeBytes: s.bytesTotal.toInt(),
            ),
          );
        case rust_transfer.DbTransferState.failed:
          history.add(
            HistoryEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.failed,
              error: s.error ?? 'failed',
              lastPercent: percent,
              lastMessage: s.error ?? 'failed',
              createdAt: DateTime.now(),
              sizeBytes: s.bytesTotal.toInt(),
            ),
          );
        case rust_transfer.DbTransferState.cancelled:
          history.add(
            HistoryEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.cancelled,
              lastPercent: percent,
              lastMessage: 'Cancelled',
              createdAt: DateTime.now(),
              sizeBytes: s.bytesTotal.toInt(),
            ),
          );
      }
    }
    if (_disposed) return;
    state = TransfersState(
      history: List.unmodifiable(history),
      active: List.unmodifiable(active),
      status: ActiveTransferState(
        running: running,
        queued: queued,
        currentInfo: current,
      ),
    );
  }

  Future<List<rust_transfer.DbTransferSnapshot>> _safeSnapshot() async {
    try {
      return await rust_transfer.transferSnapshotAll();
    } catch (e) {
      AppLogger.instance.log(
        'transferSnapshotAll failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
      return const [];
    }
  }

  bool _isActive(rust_transfer.DbTransferState s) =>
      s == rust_transfer.DbTransferState.queued ||
      s == rust_transfer.DbTransferState.running;

  /// Extract the filename portion of [path], normalising Windows
  /// separators via `lfs_core::path::basename`.
  static String _displayName(String path) => rust_path.pathBasename(path: path);
}
