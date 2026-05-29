/// End-to-end transfer-queue tests against the russh + russh-sftp
/// fixture.
///
/// Coverage:
///   * single upload completes + the file lands on disk
///   * single download completes + the local file matches the seed
///   * batch of uploads — every task ends in `completed`
///   * cancel mid-flight on a sized payload
///
/// The Rust worker pool drives the actual SFTP I/O and publishes
/// `BusEvent::TransferTaskState` / `Progress` / `Error`. The test
/// listens for terminal-state events on the per-task id and waits
/// for completion before asserting against the on-disk view through
/// `dart:io` (the fixture's SFTP root is the same inode the SFTP
/// server writes to, so the two views are consistent).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/bus/app_bus.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/bus.dart' as rust_bus;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;
import 'package:letsflutssh/src/rust/api/transfer.dart' as rust_transfer;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;
  late Directory sftpRoot;
  late ProviderContainer container;
  late Connection conn;
  late _TerminalWatcher watcher;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);

    // Subscribe to terminal-state events *before* any task is
    // enqueued. A tiny upload on localhost loopback can settle in
    // `completed` between `enqueueUpload` returning and a per-call
    // `.listen()` attaching — the terminal event would be lost and
    // the wait would sit out its full timeout. A single long-lived
    // subscription that buffers terminal states per task id closes
    // that window: a wait either finds the state already recorded
    // or is woken by the event when it arrives.
    watcher = _TerminalWatcher()..start();

    serverInfo = await rust_test.testSshServerStart();
    sftpRoot = Directory(serverInfo.sftpRoot);
    await rust_db.dbKnownHostsUpsertByHostPort(
      host: '127.0.0.1',
      port: serverInfo.port,
      keyType: serverInfo.hostPubkeyAlgorithm,
      keyBase64: serverInfo.hostPubkeyB64,
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    container = ProviderContainer();
    final notifier = container.read(connectionsProvider.notifier);
    conn = notifier.connectAsync(
      SSHConfig(
        server: ServerAddress(
          host: '127.0.0.1',
          port: serverInfo.port,
          user: 'u',
        ),
        auth: SshAuth(password: serverInfo.password),
      ),
      label: 'transfer-test',
    );
    await conn.waitUntilReady();
    await conn.transportReady;
    expect(conn.state, SSHConnectionState.connected);
  });

  tearDownAll(() async {
    await watcher.stop();
    container.read(connectionsProvider.notifier).disconnect(conn.id);
    container.dispose();
    rust_test.testSshServerStopAll();
    await rust_app.dbClose();
  });

  setUp(() async {
    for (final entry in sftpRoot.listSync()) {
      if (entry is Directory) {
        entry.deleteSync(recursive: true);
      } else {
        entry.deleteSync();
      }
    }
    // Default the per-write delay to 0 so a leftover from a prior
    // test (e.g. the cancel-mid-flight one below) does not slow
    // every other test down.
    rust_test.testSshServerSetSftpWriteDelayMs(delayMs: 0);
  });

  /// Wait for a task to reach a terminal state (`completed` /
  /// `failed` / `cancelled`). Delegates to the long-lived
  /// `_TerminalWatcher` so a state that already fired before this
  /// call cannot be missed.
  Future<rust_bus.BusTaskState> waitForTaskTerminal(
    String taskId, {
    Duration timeout = const Duration(seconds: 30),
  }) => watcher.wait(taskId, timeout: timeout);

  group('Transfer queue', () {
    test('single upload completes + remote file lands on disk', () async {
      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-xfer-up-${DateTime.now().microsecondsSinceEpoch}',
      );
      const payload = 'transfer-queue-upload-payload';
      await localTmp.writeAsString(payload);
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      final notifier = container.read(transfersProvider.notifier);
      final taskId = await notifier.enqueueUpload(
        connectionId: conn.id,
        name: 'upload.txt',
        localPath: localTmp.path,
        remotePath: '/upload.txt',
        sizeBytes: payload.length,
      );

      final terminalState = await waitForTaskTerminal(taskId);
      expect(terminalState, rust_bus.BusTaskState.completed);
      expect(File('${sftpRoot.path}/upload.txt').readAsStringSync(), payload);
    });

    test('single download completes + local file matches remote seed', () async {
      const payload = 'transfer-queue-download-payload';
      File('${sftpRoot.path}/seed.txt').writeAsStringSync(payload);

      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-xfer-down-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      final notifier = container.read(transfersProvider.notifier);
      final taskId = await notifier.enqueueDownload(
        connectionId: conn.id,
        name: 'seed.txt',
        remotePath: '/seed.txt',
        localPath: localTmp.path,
        sizeBytes: payload.length,
      );

      final terminalState = await waitForTaskTerminal(taskId);
      expect(terminalState, rust_bus.BusTaskState.completed);
      expect(localTmp.readAsStringSync(), payload);
    });

    test('batch of three uploads — every task reaches `completed`', () async {
      final files = <File>[];
      final taskIds = <String>[];
      addTearDown(() async {
        for (final f in files) {
          if (await f.exists()) await f.delete();
        }
      });

      final notifier = container.read(transfersProvider.notifier);
      for (var i = 0; i < 3; i++) {
        final f = File(
          '${Directory.systemTemp.path}/lfs-xfer-batch-$i-${DateTime.now().microsecondsSinceEpoch}',
        );
        await f.writeAsString('batch-$i');
        files.add(f);
        final id = await notifier.enqueueUpload(
          connectionId: conn.id,
          name: 'batch-$i.txt',
          localPath: f.path,
          remotePath: '/batch-$i.txt',
          sizeBytes: 7,
        );
        taskIds.add(id);
      }

      // Wait for every task to land terminal in parallel — order
      // is irrelevant, just that each one finishes.
      final terminals = await Future.wait(taskIds.map(waitForTaskTerminal));
      for (final t in terminals) {
        expect(t, rust_bus.BusTaskState.completed);
      }
      for (var i = 0; i < 3; i++) {
        expect(
          File('${sftpRoot.path}/batch-$i.txt').readAsStringSync(),
          'batch-$i',
        );
      }
    });

    test('cancel on an unknown id returns false without throwing', () async {
      // Spec: `transferCancel` walks the registry by id; a missing /
      // already-terminal id is a no-op. The Dart wrapper must surface
      // the Rust `false` cleanly so the UI's per-row cancel button
      // can render a "nothing to cancel" toast instead of crashing.
      final notifier = container.read(transfersProvider.notifier);
      final ok = await notifier.cancel('does-not-exist-fake-task-id');
      expect(ok, isFalse);
    });

    test('cancelAll walks the snapshot and cancels every active task', () async {
      // Spec: cancelAll dispatches cancel() for each task whose state
      // is queued or running at snapshot time. Drive two slow uploads,
      // call cancelAll, then assert both settle in `cancelled`. The
      // 50 ms write delay keeps the tasks alive long enough for the
      // walk to catch both as active.
      rust_test.testSshServerSetSftpWriteDelayMs(delayMs: 50);

      final notifier = container.read(transfersProvider.notifier);
      final payload = Uint8List(2 * 1024 * 1024);
      final files = <File>[];
      final taskIds = <String>[];
      addTearDown(() async {
        for (final f in files) {
          if (await f.exists()) await f.delete();
        }
      });

      for (var i = 0; i < 2; i++) {
        final f = File(
          '${Directory.systemTemp.path}/lfs-xfer-cancelall-$i-${DateTime.now().microsecondsSinceEpoch}',
        );
        await f.writeAsBytes(payload);
        files.add(f);
        final id = await notifier.enqueueUpload(
          connectionId: conn.id,
          name: 'cancelall-$i.bin',
          localPath: f.path,
          remotePath: '/cancelall-$i.bin',
          sizeBytes: payload.length,
        );
        taskIds.add(id);
      }

      // Let the executor start at least one chunk on each task — the
      // walk inside cancelAll runs against `transferSnapshotAll`, so
      // both tasks must be reported as queued / running at that point.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      notifier.cancelAll();

      for (final id in taskIds) {
        final state = await waitForTaskTerminal(id);
        // Either the cancel arrived mid-flight (cancelled) or the
        // tiny window between snapshot + cancel let the task finish
        // (completed). Both are valid outcomes of the cancelAll race —
        // what we're pinning here is that no task ends up in `failed`
        // because of the cancel walk itself.
        expect(state, isNot(equals(rust_bus.BusTaskState.failed)));
      }

      // Reset the delay so subsequent tests don't inherit it.
      rust_test.testSshServerSetSftpWriteDelayMs(delayMs: 0);
    });

    test('clearHistory empties the terminal entries from the registry', () async {
      // Spec: `transferClearHistory` drops every Completed / Failed /
      // Cancelled entry. Drive a completing upload, wait for terminal,
      // call clearHistory, snapshot the registry — the entry is gone.
      const payload = 'history-clear-payload';
      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-xfer-clearhist-${DateTime.now().microsecondsSinceEpoch}',
      );
      await localTmp.writeAsString(payload);
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      final notifier = container.read(transfersProvider.notifier);
      final taskId = await notifier.enqueueUpload(
        connectionId: conn.id,
        name: 'clearhist.txt',
        localPath: localTmp.path,
        remotePath: '/clearhist.txt',
        sizeBytes: payload.length,
      );
      final state = await waitForTaskTerminal(taskId);
      expect(state, rust_bus.BusTaskState.completed);

      await notifier.clearHistory();
      // `transferDropTerminal` and `transferClearHistory` don't emit
      // bus events — the Riverpod state catches up on the next refresh
      // window that fires for any other reason. Pin the contract
      // directly against the Rust snapshot so the assertion isn't
      // racing the bus.
      final snap = await rust_transfer.transferSnapshotAll();
      expect(
        snap.any((s) => s.id == taskId),
        isFalse,
        reason: 'clearHistory must drop the just-completed entry',
      );
    });

    test('deleteHistory drops each provided id and skips missing ones', () async {
      // Spec: deleteHistory iterates the supplied list and calls
      // `transferDropTerminal` per id. Missing ids are silently
      // skipped (the Rust function is idempotent on absent ids) so
      // the UI can pass a stale id list without crashing.
      const payload = 'history-delete-payload';
      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-xfer-delhist-${DateTime.now().microsecondsSinceEpoch}',
      );
      await localTmp.writeAsString(payload);
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      final notifier = container.read(transfersProvider.notifier);
      final realId = await notifier.enqueueUpload(
        connectionId: conn.id,
        name: 'delhist.txt',
        localPath: localTmp.path,
        remotePath: '/delhist.txt',
        sizeBytes: payload.length,
      );
      await waitForTaskTerminal(realId);

      await notifier.deleteHistory([realId, 'this-id-does-not-exist']);
      // Same shape as the clearHistory pin above: assert against
      // the Rust snapshot directly so the Riverpod-refresh debounce
      // can't race the assertion.
      final snap = await rust_transfer.transferSnapshotAll();
      expect(
        snap.any((s) => s.id == realId),
        isFalse,
        reason:
            'deleteHistory must drop the real id even when the '
            'list also contains a stale / missing one',
      );
    });

    test('cancel mid-flight settles the task in `cancelled`', () async {
      // The upload loop in `lfs_core::transfer::driver::upload`
      // checks `cancel.is_cancelled()` at the top of every chunk
      // (`TRANSFER_CHUNK_SIZE = 256 KiB`). On localhost loopback the
      // 16 chunks for a 4 MiB file fly through faster than a Dart
      // `cancel` round-trips through the FRB worker — the cancel
      // arrives after the upload has already settled in `completed`
      // and the assertion misses. Widening the race window deter-
      // ministically: install a per-`write` delay on the fixture's
      // SFTP subsystem so each chunk takes ~50 ms. A 4 MiB file
      // becomes ≈800 ms; cancelling after 150 ms lands on chunk
      // ~2/16 and the next loop-top check terminates the task with
      // `upload cancelled`.
      rust_test.testSshServerSetSftpWriteDelayMs(delayMs: 50);

      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-xfer-cancel-${DateTime.now().microsecondsSinceEpoch}',
      );
      // 4 MiB of zeros — content does not matter; only chunk count
      // does. 16 chunks × 50 ms gives plenty of room for the
      // cancel to land between any two writes.
      final payload = Uint8List(4 * 1024 * 1024);
      await localTmp.writeAsBytes(payload);
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      final notifier = container.read(transfersProvider.notifier);
      final taskId = await notifier.enqueueUpload(
        connectionId: conn.id,
        name: 'cancel-mid-flight.bin',
        localPath: localTmp.path,
        remotePath: '/cancel-mid-flight.bin',
        sizeBytes: payload.length,
      );

      // Wait long enough for the executor to grab the task off
      // the queue and dispatch the first chunk write — but well
      // short of the ≈800 ms total. 150 ms ≈ chunks 2-3 of 16.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final cancelled = await notifier.cancel(taskId);
      expect(cancelled, isTrue);

      final terminalState = await waitForTaskTerminal(taskId);
      expect(
        terminalState,
        rust_bus.BusTaskState.cancelled,
        reason:
            'cancel dispatched mid-flight must steer the task into '
            '`cancelled`, not `completed` or `failed`. Either the cancel '
            'token is not being checked at the chunk boundary, or the '
            'fixture write delay is not slowing things down enough — try '
            'a longer delay or a larger payload.',
      );
    });
  });
}

/// Buffers terminal `BusEvent::TransferTaskState` events per task id
/// from a single subscription opened before the first enqueue.
/// `wait` resolves immediately when the state was already recorded,
/// otherwise it parks a completer the listener fulfils on arrival —
/// so no terminal event can slip through between enqueue and wait.
/// Mirrors what `TransfersNotifier` does internally to update the
/// UI; reaches for the bus directly so the assertion does not depend
/// on a Riverpod selector firing in lockstep with the bus event.
class _TerminalWatcher {
  final Map<String, rust_bus.BusTaskState> _states = {};
  final Map<String, Completer<rust_bus.BusTaskState>> _waiters = {};
  StreamSubscription<rust_bus.BusEvent>? _sub;

  void start() {
    _sub = AppBus.instance.subscribe(rust_bus.BusTopic.transfer).listen((
      event,
    ) {
      if (event is! rust_bus.BusEvent_TransferTaskState ||
          !_isTerminal(event.state)) {
        return;
      }
      _states[event.id] = event.state;
      final waiter = _waiters.remove(event.id);
      if (waiter != null && !waiter.isCompleted) waiter.complete(event.state);
    });
  }

  Future<rust_bus.BusTaskState> wait(
    String taskId, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final recorded = _states[taskId];
    if (recorded != null) return Future.value(recorded);
    final completer = _waiters.putIfAbsent(
      taskId,
      Completer<rust_bus.BusTaskState>.new,
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(taskId);
        throw TimeoutException(
          'transfer $taskId did not reach a terminal state within '
          '${timeout.inSeconds}s',
        );
      },
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static bool _isTerminal(rust_bus.BusTaskState state) =>
      state == rust_bus.BusTaskState.completed ||
      state == rust_bus.BusTaskState.failed ||
      state == rust_bus.BusTaskState.cancelled;
}
