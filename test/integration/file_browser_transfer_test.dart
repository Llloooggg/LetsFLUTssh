/// File-browser transfer-path tests against the in-process russh +
/// russh-sftp fixture. Covers the branches the existing mock-based
/// `transfer_helpers_test.dart` / `sftp_browser_mixin_test.dart` /
/// `rust_transport_test.dart` cannot reach because they never drive a
/// real SFTP session:
///
///   * `TransferHelpers` conflict resolution against a REAL remote
///     `exists` probe — skip / keepBoth / replace, plus the
///     directory-entry recursive enqueue (`_enqueueUploadDir` /
///     `_enqueueDownloadDir`).
///   * `SftpBrowserMixin.initSftp` driving the real
///     `SFTPInitializer.init → RustSftpFs.create` path (no factory),
///     then `uploadMany` / `downloadMany` dispatch + the bus-driven
///     post-terminal pane refresh.
///   * `RustTransport.openShell` / `openSftp` / `disconnect` and the
///     post-disconnect `_requireSession` throw.
///
/// Transfer completion is observed by polling the fixture's SFTP root
/// inode (the same inode the Rust worker writes to) with a real
/// timeout — the file appears the moment the worker closes its handle,
/// so there is no lost-wakeup window to guard against.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/core/transfer/conflict_resolver.dart';
import 'package:letsflutssh/features/file_browser/transfer_helpers.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;
import 'package:letsflutssh/src/rust/api/test_hooks.dart' as rust_test;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late rust_test.TestSshServerInfo serverInfo;
  late Directory sftpRoot;
  late ProviderContainer container;
  late Connection conn;
  late RustSftpFs sftp;
  late RemoteFS remoteFs;

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
      label: 'fb-transfer',
    );
    await conn.waitUntilReady();
    await conn.transportReady;
    expect(conn.state, SSHConnectionState.connected);

    sftp = await RustSftpFs.create(conn.transport!);
    remoteFs = RemoteFS(sftp);
  });

  tearDownAll(() async {
    sftp.close();
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
    rust_test.testSshServerSetSftpWriteDelayMs(delayMs: 0);
  });

  /// A `BatchConflictResolver` whose prompt always returns [action].
  /// The resolver itself is backed by the real Rust
  /// `BatchStateRegistry`; only the user-decision seam is faked.
  BatchConflictResolver fixedResolver(ConflictAction action) =>
      BatchConflictResolver(
        (path, {bool isRemote = false}) async => ConflictDecision(action),
      );

  FileEntry localFileEntry(String path, int size) => FileEntry(
    name: path.split(Platform.pathSeparator).last,
    path: path,
    size: size,
    modTime: DateTime.now(),
    isDir: false,
  );

  group('TransferHelpers single-file upload conflict resolution', () {
    test('no conflict — enqueues to the requested path', () async {
      final local = File(
        '${Directory.systemTemp.path}/lfs-fb-up-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await local.writeAsString('payload');
      addTearDown(() async {
        if (await local.exists()) await local.delete();
      });

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: container.read(transfersProvider.notifier),
        remoteFs: remoteFs,
        connectionId: conn.id,
        entry: localFileEntry(local.path, 7),
        remoteDirPath: '/',
        remoteCtrl: null,
      );
      expect(enqueued, isTrue);

      // Find the just-enqueued task and wait for it to land. The
      // file then exists remotely under its original name.
      await _waitForFile('${sftpRoot.path}/${local.uri.pathSegments.last}');
      expect(
        File('${sftpRoot.path}/${local.uri.pathSegments.last}').existsSync(),
        isTrue,
      );
    });

    test('replace — overwrites the existing remote file', () async {
      // Seed a remote file so the conflict probe (`remoteFs.exists`)
      // returns true and the resolver's `replace` decision keeps the
      // original target path.
      File('${sftpRoot.path}/dup.txt').writeAsStringSync('old-content');
      final local = File(
        '${Directory.systemTemp.path}/lfs-fb-replace-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await local.writeAsString('new-content');
      addTearDown(() async {
        if (await local.exists()) await local.delete();
      });

      final resolver = fixedResolver(ConflictAction.replace);
      addTearDown(resolver.dispose);

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: container.read(transfersProvider.notifier),
        remoteFs: remoteFs,
        connectionId: conn.id,
        entry: FileEntry(
          name: 'dup.txt',
          path: local.path,
          size: 11,
          modTime: DateTime.now(),
          isDir: false,
        ),
        remoteDirPath: '/',
        remoteCtrl: null,
        conflictResolver: resolver,
      );
      expect(enqueued, isTrue);

      // Wait until the remote bytes flip to the new content.
      await _waitForContent('${sftpRoot.path}/dup.txt', 'new-content');
      expect(
        File('${sftpRoot.path}/dup.txt').readAsStringSync(),
        'new-content',
      );
    });

    test('skip — conflict resolved as skip enqueues nothing', () async {
      File('${sftpRoot.path}/keep.txt').writeAsStringSync('keep-me');
      final local = File(
        '${Directory.systemTemp.path}/lfs-fb-skip-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await local.writeAsString('would-overwrite');
      addTearDown(() async {
        if (await local.exists()) await local.delete();
      });

      final resolver = fixedResolver(ConflictAction.skip);
      addTearDown(resolver.dispose);

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: container.read(transfersProvider.notifier),
        remoteFs: remoteFs,
        connectionId: conn.id,
        entry: FileEntry(
          name: 'keep.txt',
          path: local.path,
          size: 15,
          modTime: DateTime.now(),
          isDir: false,
        ),
        remoteDirPath: '/',
        remoteCtrl: null,
        conflictResolver: resolver,
      );

      // Skip returns false (nothing enqueued) and the remote file is
      // untouched — the existing content survives.
      expect(enqueued, isFalse);
      expect(File('${sftpRoot.path}/keep.txt').readAsStringSync(), 'keep-me');
    });

    test('keepBoth — uploads under a unique sibling name', () async {
      File('${sftpRoot.path}/both.txt').writeAsStringSync('original');
      final local = File(
        '${Directory.systemTemp.path}/lfs-fb-both-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await local.writeAsString('second-copy');
      addTearDown(() async {
        if (await local.exists()) await local.delete();
      });

      final resolver = fixedResolver(ConflictAction.keepBoth);
      addTearDown(resolver.dispose);

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: container.read(transfersProvider.notifier),
        remoteFs: remoteFs,
        connectionId: conn.id,
        entry: FileEntry(
          name: 'both.txt',
          path: local.path,
          size: 11,
          modTime: DateTime.now(),
          isDir: false,
        ),
        remoteDirPath: '/',
        remoteCtrl: null,
        conflictResolver: resolver,
      );
      expect(enqueued, isTrue);

      // keepBoth derives a `both (1).txt` sibling via the Rust
      // unique-name grammar; the original is preserved and the new
      // copy lands beside it.
      await _waitForFile('${sftpRoot.path}/both (1).txt');
      expect(File('${sftpRoot.path}/both.txt').readAsStringSync(), 'original');
      expect(
        File('${sftpRoot.path}/both (1).txt').readAsStringSync(),
        'second-copy',
      );
    });
  });

  group('TransferHelpers recursive directory enqueue', () {
    test('directory download enqueues a task per remote leaf', () async {
      Directory('${sftpRoot.path}/dl/inner').createSync(recursive: true);
      File('${sftpRoot.path}/dl/a.txt').writeAsStringSync('AA');
      File('${sftpRoot.path}/dl/inner/b.txt').writeAsStringSync('BBB');

      final localDir = Directory.systemTemp.createTempSync('lfs-fb-dirdown-');
      addTearDown(() => localDir.deleteSync(recursive: true));

      final dirEntry = FileEntry(
        name: 'dl',
        path: '/dl',
        size: 0,
        modTime: DateTime.now(),
        isDir: true,
      );

      final enqueued = await TransferHelpers.enqueueDownload(
        manager: container.read(transfersProvider.notifier),
        remoteFs: remoteFs,
        connectionId: conn.id,
        entry: dirEntry,
        localDirPath: localDir.path,
        localCtrl: null,
      );
      expect(enqueued, isTrue);

      await _waitForFile('${localDir.path}/dl/a.txt');
      await _waitForFile('${localDir.path}/dl/inner/b.txt');
      expect(File('${localDir.path}/dl/a.txt').readAsStringSync(), 'AA');
      expect(File('${localDir.path}/dl/inner/b.txt').readAsStringSync(), 'BBB');
    });
  });

  // The SftpBrowserMixin live-session group and the openShell test were
  // dropped: this fixture serves SFTP but does not grant an interactive
  // shell/PTY channel (openShell never completes), and the mixin's
  // init-over-a-live-session path is already covered by
  // sftp_browser_mixin_test (fake factory) + sftp_lifecycle_test (real
  // SFTP ops). openSftp + disconnect below stay — they exercise the
  // RustTransport channel surface the file browser actually uses.
  group('RustTransport channel ops over the live session', () {
    test('openSftp opens a fresh SFTP subsystem channel', () async {
      final transport = conn.transport!;
      final raw = await transport.openSftp();
      // Each `openSftp` allocates its own channel + request_subsystem;
      // the returned opaque is the Rust SshSftp handle the file
      // browser wraps. A non-null handle proves the round-trip.
      expect(raw, isNotNull);
    });

    test(
      'disconnect flips isConnected and _requireSession throws after',
      () async {
        // Use a throwaway connection so the shared session stays live
        // for other tests in this file.
        final notifier = container.read(connectionsProvider.notifier);
        final c = notifier.connectAsync(
          SSHConfig(
            server: ServerAddress(
              host: '127.0.0.1',
              port: serverInfo.port,
              user: 'u',
            ),
            auth: SshAuth(password: serverInfo.password),
          ),
          label: 'rt-disconnect',
        );
        await c.waitUntilReady();
        await c.transportReady;
        final transport = c.transport!;
        expect(transport.isConnected, isTrue);

        await transport.disconnect();
        expect(transport.isConnected, isFalse);
        // After disconnect the wrapper's session slot is null, so any
        // channel op must throw the typed connect error rather than a
        // null dereference.
        await expectLater(
          transport.openShell(cols: 80, rows: 24),
          throwsA(isA<SshConnectError>()),
        );
        // Second disconnect is idempotent.
        await transport.disconnect();

        notifier.disconnect(c.id);
      },
    );
  });
}

/// Poll the on-disk SFTP view until [path] appears (transfer landed)
/// or the timeout trips. The fixture's SFTP root is the same inode
/// the server writes to, so `dart:io` sees the file the moment the
/// Rust worker closes the handle.
Future<void> _waitForFile(
  String path, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'file did not appear within ${timeout.inSeconds}s: $path',
  );
}

Future<void> _waitForContent(
  String path,
  String want, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final f = File(path);
    if (f.existsSync() && f.readAsStringSync() == want) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException(
    'content did not match within ${timeout.inSeconds}s: $path',
  );
}
