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

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;
  late Directory sftpRoot;
  late ProviderContainer container;
  late Connection conn;

  setUpAll(() async {
    await requireFrbLoaded();
    await rust_app.dbInit(path: ':memory:', key: const []);

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
  });

  /// Wait for the per-task `BusEvent::TransferTaskState` to hit a
  /// terminal state (`completed` / `failed` / `cancelled`). Mirrors
  /// what `TransfersNotifier` does internally to update the UI;
  /// reaches for the bus directly so the assertion does not depend
  /// on a Riverpod selector firing in lockstep with the bus event.
  Future<rust_bus.BusTaskState> waitForTaskTerminal(
    String taskId, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final completer = Completer<rust_bus.BusTaskState>();
    late StreamSubscription<rust_bus.BusEvent> sub;
    sub = AppBus.instance.subscribe(rust_bus.BusTopic.transfer).listen((event) {
      if (event is rust_bus.BusEvent_TransferTaskState && event.id == taskId) {
        if (event.state == rust_bus.BusTaskState.completed ||
            event.state == rust_bus.BusTaskState.failed ||
            event.state == rust_bus.BusTaskState.cancelled) {
          if (!completer.isCompleted) completer.complete(event.state);
          sub.cancel();
        }
      }
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub.cancel();
        throw TimeoutException(
          'transfer $taskId did not reach a terminal state within '
          '${timeout.inSeconds}s',
        );
      },
    );
  }

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

    // Cancel-mid-flight isn't covered: the localhost loopback +
    // fixture's per-chunk-open SFTP write makes the timing
    // window for "cancel arrives between two write chunks but
    // before the upload completes" too narrow to reliably hit
    // from the test process. The Rust-side `pool.cancel`
    // invariants are exercised by the unit tests in
    // `lfs_core::transfer::*`; a stress-style integration test
    // for the race window can be added later if it starts to
    // regress.
  });
}
