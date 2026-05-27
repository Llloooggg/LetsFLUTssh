/// SFTP filesystem-operation tests against the in-process russh +
/// russh-sftp fixture, focused on the corners `sftp_lifecycle_test.dart`
/// leaves uncovered: `getwd`, `dirSize`/`dirSizeRecursive`,
/// `flatWalkFiles`, the `exists` true/false/error tri-state, recursive
/// `removeDir`, streaming `uploadDir`/`downloadDir`, the `RemoteFS`
/// wrapper surface (`initialDir`, `capabilities`, `exists`), and the
/// `RustSftpFs.create` type-guard.
///
/// Why a real SFTP session and not a mock: every one of these methods
/// is a thin Dart wrapper over an FRB call that drives the russh-sftp
/// wire protocol Rust-side. A mock satisfying `RemoteSftpFs` proves
/// nothing about whether `canonicalize('.')`, a recursive walk, or an
/// `LSTAT` on a missing path round-trips correctly — only the fixture
/// exercises the protocol path the wrappers exist to bridge.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/errors.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/ssh/transport/ssh_transport.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
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
      label: 'sftp-fs-ops',
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

  /// Each test starts from an empty SFTP root. The directory itself
  /// stays — only its children are wiped — because the Rust fixture
  /// roots SFTP at exactly this inode.
  setUp(() async {
    for (final entry in sftpRoot.listSync()) {
      if (entry is Directory) {
        entry.deleteSync(recursive: true);
      } else {
        entry.deleteSync();
      }
    }
  });

  group('RustSftpFs query ops', () {
    test('getwd canonicalizes "." to an absolute server path', () async {
      // `canonicalize('.')` must resolve against the SFTP session's
      // working directory and come back as an absolute path — the
      // file browser seeds its initial remote pane from this value,
      // so a relative or empty answer would leave the pane rooted
      // nowhere.
      final wd = await sftp.getwd();
      expect(wd, isNotEmpty);
      expect(wd.startsWith('/'), isTrue);
    });

    test(
      'exists returns true for a present file, false for an absent one',
      () async {
        File('${sftpRoot.path}/present.txt').writeAsStringSync('x');
        expect(await sftp.exists('/present.txt'), isTrue);
        // A clean "no such file" must resolve to false, NOT throw — the
        // conflict resolver / unique-name generator treats false as a
        // free slot. (A permission/IO error would propagate instead;
        // the fixture's tempdir is world-accessible so we can't force
        // that arm here without an OS-level chmod, which is on the
        // allow-list for "not unit-testable".)
        expect(await sftp.exists('/no-such-file.txt'), isFalse);
      },
    );

    test('dirSizeRecursive sums the byte total of a nested tree', () async {
      // Lay down a two-level tree: 3 + 5 + 7 = 15 bytes total. The
      // Rust walk runs over one channel pair; the assertion is the
      // exact byte sum so a miscounted subdirectory or a double-
      // counted entry is caught, not just "non-zero".
      File('${sftpRoot.path}/a.txt').writeAsStringSync('aaa'); // 3
      Directory('${sftpRoot.path}/sub').createSync();
      File('${sftpRoot.path}/sub/b.txt').writeAsStringSync('bbbbb'); // 5
      File('${sftpRoot.path}/sub/c.txt').writeAsStringSync('ccccccc'); // 7

      // Via RemoteFS.dirSize → sftp.dirSizeRecursive (depth cap 64).
      final total = await remoteFs.dirSize('/');
      expect(total, 15);
    });

    test(
      'flatWalkFiles enumerates every leaf with /-joined relPaths',
      () async {
        File('${sftpRoot.path}/top.txt').writeAsStringSync('1');
        Directory('${sftpRoot.path}/d1/d2').createSync(recursive: true);
        File('${sftpRoot.path}/d1/mid.txt').writeAsStringSync('22');
        File('${sftpRoot.path}/d1/d2/deep.txt').writeAsStringSync('333');

        final leaves = await remoteFs.flatWalkFiles('/');
        final byRel = {for (final l in leaves) l.relPath: l.size};
        // Directories are not leaves — only the three files appear, and
        // each relPath is /-joined relative to the walk root.
        expect(byRel.keys.toSet(), {'top.txt', 'd1/mid.txt', 'd1/d2/deep.txt'});
        expect(byRel['top.txt'], 1);
        expect(byRel['d1/mid.txt'], 2);
        expect(byRel['d1/d2/deep.txt'], 3);
      },
    );

    test('list filters out "." and ".." synthetic entries', () async {
      File('${sftpRoot.path}/real.txt').writeAsStringSync('r');
      final entries = await sftp.list('/');
      expect(entries.map((e) => e.name), isNot(contains('.')));
      expect(entries.map((e) => e.name), isNot(contains('..')));
      expect(entries.map((e) => e.name), contains('real.txt'));
    });
  });

  group('RustSftpFs recursive + streaming ops', () {
    test('removeDir recursively drops a populated directory', () async {
      Directory('${sftpRoot.path}/tree/inner').createSync(recursive: true);
      File('${sftpRoot.path}/tree/f1.txt').writeAsStringSync('1');
      File('${sftpRoot.path}/tree/inner/f2.txt').writeAsStringSync('2');

      // Recursive removeDir (one FRB call) must drain contents first
      // then drop the shell — a non-recursive rmdir would fail on the
      // non-empty directory.
      await remoteFs.removeDir('/tree');
      expect(Directory('${sftpRoot.path}/tree').existsSync(), isFalse);
    });

    test(
      'removeEmptyDir drops an empty directory but is non-recursive',
      () async {
        Directory('${sftpRoot.path}/empty').createSync();
        await sftp.removeEmptyDir('/empty');
        expect(Directory('${sftpRoot.path}/empty').existsSync(), isFalse);
      },
    );

    test(
      'uploadDir streams every local leaf to the remote tree with progress',
      () async {
        final localDir = Directory.systemTemp.createTempSync('lfs-updir-');
        addTearDown(() => localDir.deleteSync(recursive: true));
        File('${localDir.path}/x.txt').writeAsStringSync('xx');
        Directory('${localDir.path}/nested').createSync();
        File('${localDir.path}/nested/y.txt').writeAsStringSync('yyy');

        var sawCompleted = false;
        await sftp.uploadDir(localDir.path, '/dest', (p) {
          if (p.isCompleted) sawCompleted = true;
        });

        // Both leaves land under the remote dest, mirroring the local
        // tree shape, and the progress callback signals completion at
        // least once.
        expect(File('${sftpRoot.path}/dest/x.txt').readAsStringSync(), 'xx');
        expect(
          File('${sftpRoot.path}/dest/nested/y.txt').readAsStringSync(),
          'yyy',
        );
        expect(sawCompleted, isTrue);
      },
    );

    test('downloadDir streams the remote tree to a local path', () async {
      Directory('${sftpRoot.path}/src/inner').createSync(recursive: true);
      File('${sftpRoot.path}/src/a.txt').writeAsStringSync('A');
      File('${sftpRoot.path}/src/inner/b.txt').writeAsStringSync('BB');

      final localDir = Directory.systemTemp.createTempSync('lfs-downdir-');
      addTearDown(() => localDir.deleteSync(recursive: true));
      final dest = '${localDir.path}/out';

      await sftp.downloadDir('/src', dest, null);

      expect(File('$dest/a.txt').readAsStringSync(), 'A');
      expect(File('$dest/inner/b.txt').readAsStringSync(), 'BB');
    });

    test(
      'rename across directories moves the file under a new parent',
      () async {
        Directory('${sftpRoot.path}/from').createSync();
        Directory('${sftpRoot.path}/to').createSync();
        File('${sftpRoot.path}/from/m.txt').writeAsStringSync('move-me');

        await sftp.rename('/from/m.txt', '/to/m.txt');

        expect(File('${sftpRoot.path}/from/m.txt').existsSync(), isFalse);
        expect(File('${sftpRoot.path}/to/m.txt').readAsStringSync(), 'move-me');
      },
    );
  });

  group('RustSftpFs error wrapping', () {
    test('mkdir over an existing file surfaces an SFTPError', () async {
      File('${sftpRoot.path}/collide').writeAsStringSync('x');
      // Creating a directory where a regular file already lives must
      // bubble through the wrapper as an SFTPError rather than hang
      // or pass silently.
      await expectLater(
        sftp.mkdir('/collide').timeout(const Duration(seconds: 5)),
        throwsA(isA<SFTPError>()),
      );
    });

    test('remove of a missing file surfaces an SFTPError', () async {
      await expectLater(
        sftp.remove('/never-existed.txt').timeout(const Duration(seconds: 5)),
        throwsA(isA<SFTPError>()),
      );
    });

    test('rename of a missing source surfaces an SFTPError', () async {
      await expectLater(
        sftp
            .rename('/missing-src.txt', '/dst.txt')
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<SFTPError>()),
      );
    });

    test('flatWalkFiles on a missing root surfaces an SFTPError', () async {
      await expectLater(
        sftp
            .flatWalkFiles('/does/not/exist', 10)
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<SFTPError>()),
      );
    });
  });

  group('RemoteFS wrapper surface', () {
    test(
      'initialDir delegates to getwd and returns an absolute path',
      () async {
        final dir = await remoteFs.initialDir();
        expect(dir.startsWith('/'), isTrue);
      },
    );

    test('exists delegates to the SFTP-native probe', () async {
      File('${sftpRoot.path}/probe.txt').writeAsStringSync('p');
      expect(await remoteFs.exists('/probe.txt'), isTrue);
      expect(await remoteFs.exists('/absent.txt'), isFalse);
    });

    test('capabilities reports POSIX — SFTP carries mode + owner', () {
      // The SFTP backend always has st_mode + an owner name on every
      // entry, so the file browser shows both the Mode and Owner
      // columns; the wrapper must advertise the POSIX capability set.
      expect(remoteFs.capabilities, FileSystemCapabilities.posix);
    });

    test('mkdir + list + remove round-trip through the wrapper', () async {
      await remoteFs.mkdir('/wrap-dir');
      final entries = await remoteFs.list('/');
      expect(entries.any((e) => e.name == 'wrap-dir' && e.isDir), isTrue);
      await remoteFs.removeDir('/wrap-dir');
      expect(Directory('${sftpRoot.path}/wrap-dir').existsSync(), isFalse);
    });
  });

  group('RustSftpFs.create type guard', () {
    test(
      'rejects a transport that returns a non-SshSftp from openSftp',
      () async {
        // The factory must fail closed with a clear StateError when a
        // transport hands back the wrong opaque type, instead of
        // letting a downstream NoSuchMethod surface deep in the file
        // browser. Drive it with a transport whose openSftp returns an
        // unrelated object.
        await expectLater(
          RustSftpFs.create(_BadSftpTransport()),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('close is a no-op and safe to call repeatedly', () {
      // The Rust handle drops on dispose; explicit close must not
      // throw and must be idempotent so a double-dispose from the
      // file browser teardown is harmless.
      expect(sftp.close, returnsNormally);
      expect(sftp.close, returnsNormally);
    });
  });
}

/// A transport whose `openSftp` returns the wrong opaque type so the
/// `RustSftpFs.create` type guard has a non-`SshSftp` value to reject.
/// Only `openSftp` is reachable in this test; the rest throw so a
/// mis-wired call is loud rather than silently no-op.
class _BadSftpTransport implements SshTransport {
  @override
  Future<Object> openSftp() async => Object();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used by this test',
  );
}
