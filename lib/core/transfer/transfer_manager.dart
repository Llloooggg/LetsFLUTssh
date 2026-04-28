import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../src/rust/api/bus.dart' as rust_bus;
import '../../src/rust/api/path.dart' as rust_path;
import '../../src/rust/api/transfer.dart' as rust_transfer;
import '../../utils/logger.dart';
import '../bus/app_bus.dart';
import 'transfer_task.dart';

/// Thin Dart shim over the Rust transfer queue
/// (`lfs_core::transfer::TransferQueue` + `WorkerPool` +
/// `SftpTaskExecutor`). The Rust side owns scheduling, parallelism,
/// chunked SFTP streaming, cancellation tokens, and the canonical
/// per-task state; this shim mirrors a snapshot for the UI and
/// dispatches commands over FRB.
///
/// State refresh is event-driven: the Rust queue publishes
/// `TransferTask*` events on the `Transfer` bus topic after every
/// mutation. The shim subscribes once, debounces re-fetches, and
/// fires `onChange` so the existing Riverpod stream providers keep
/// rebuilding their consumers.
class TransferManager {
  final _historyCache = <HistoryEntry>[];
  final _activeCache = <ActiveEntry>[];
  String? _currentTransferInfo;
  int _running = 0;
  int _queued = 0;
  bool _disposed = false;

  final _controller = StreamController<void>.broadcast();
  StreamSubscription<rust_bus.BusEvent>? _busSub;

  /// Pending refresh consolidator — multiple bus events in the same
  /// microtask coalesce to a single `transferSnapshotAll` call.
  Future<void>? _pendingRefresh;

  /// Fires on any state change (queue/history update). Existing
  /// `transferHistoryProvider` / `transferStatusProvider` /
  /// `activeTransfersProvider` re-yield off this stream.
  Stream<void> get onChange => _controller.stream;

  TransferManager() {
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
        'TransferManager bus subscribe failed: $e',
        name: 'Transfer',
        level: LogLevel.warn,
      );
    }
    _scheduleRefresh();
  }

  List<HistoryEntry> get history => List.unmodifiable(_historyCache);
  List<ActiveEntry> get activeEntries => List.unmodifiable(_activeCache);
  String? get currentTransferInfo => _currentTransferInfo;
  int get runningCount => _running;
  int get queueLength => _queued;

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
    _historyCache.clear();
    _activeCache.clear();
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
          _activeCache.add(
            ActiveEntry(
              id: s.id,
              name: name,
              direction: dir,
              sourcePath: source,
              targetPath: target,
              status: TransferStatus.queued,
              percent: percent,
              message: 'Queued',
            ),
          );
        case rust_transfer.DbTransferState.running:
          running++;
          current = '$name ${percent.toStringAsFixed(0)}%';
          _activeCache.add(
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
          _historyCache.add(
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
          _historyCache.add(
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
          _historyCache.add(
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
    _running = running;
    _queued = queued;
    _currentTransferInfo = current;
    if (!_disposed) _controller.add(null);
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

  /// Routes through `lfs_core::path::basename` so the
  /// Windows-separator normalisation grammar lives one place;
  /// falls back to the inline cross-separator scan when the FRB
  /// native lib is not loaded.
  static String _displayName(String path) {
    try {
      return rust_path.pathBasename(path: path);
    } catch (_) {
      final unix = path.lastIndexOf('/');
      final win = path.lastIndexOf('\\');
      final idx = unix > win ? unix : win;
      if (idx < 0 || idx == path.length - 1) return path;
      return path.substring(idx + 1);
    }
  }

  void dispose() {
    _disposed = true;
    unawaited(_busSub?.cancel());
    _busSub = null;
    _controller.close();
  }
}
