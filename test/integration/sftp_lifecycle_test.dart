/// End-to-end SFTP tests against the in-process russh + russh-sftp
/// fixture.
///
/// The connection-lifecycle suite already covers the bus boundary
/// races; this file focuses on the SFTP subsystem: list / read /
/// write / mkdir / rename / remove paths against a real SFTP
/// session backed by `lfs_core::connection::test_server`'s
/// filesystem-rooted SFTP handler.
///
/// Why real SFTP and not a mock: `RustSftpFs` routes through FRB
/// async calls that ultimately drive `russh-sftp`'s wire protocol.
/// A mock that satisfies the abstract `RemoteSftpFs` interface
/// proves nothing about whether the Rust side handles a malformed
/// readdir, a partial write, an `Eof` mid-pipeline, etc. The
/// in-process server gives us the protocol round-trip without
/// requiring `apt install openssh-server` in CI.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
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

    // One container + one connection for the whole group — every
    // test reuses the same SFTP session so SSH-channel allocation
    // overhead (full re-handshake, re-auth) doesn't dominate the
    // per-test cost. SFTP-specific state lives in the per-test
    // setUp below.
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
      label: 'sftp-test',
    );
    await conn.waitUntilReady();
    await conn.transportReady;
    expect(conn.state, SSHConnectionState.connected);

    sftp = await RustSftpFs.create(conn.transport!);
  });

  tearDownAll(() async {
    sftp.close();
    container.read(connectionsProvider.notifier).disconnect(conn.id);
    container.dispose();
    rust_test.testSshServerStop();
    await rust_app.dbClose();
  });

  /// Wipe the SFTP root between tests so each one starts from a
  /// known state. The directory itself stays in place — only its
  /// children are removed. Using `dart:io` because the Rust-side
  /// fixture roots SFTP at exactly this path; the two views of
  /// the directory are the same on-disk inode.
  setUp(() async {
    for (final entry in sftpRoot.listSync()) {
      if (entry is Directory) {
        entry.deleteSync(recursive: true);
      } else {
        entry.deleteSync();
      }
    }
  });

  group('SFTP filesystem ops (russh-sftp fixture)', () {
    test('list returns entries seeded via dart:io', () async {
      File('${sftpRoot.path}/alpha.txt').writeAsStringSync('one');
      File('${sftpRoot.path}/beta.txt').writeAsStringSync('two');
      sftpRoot.createTempSync('subdir-');

      final entries = await sftp.list('/');
      final names = entries.map((e) => e.name).toSet();
      expect(names, containsAll({'alpha.txt', 'beta.txt'}));
      expect(names.any((n) => n.startsWith('subdir-')), isTrue);

      final alpha = entries.firstWhere((e) => e.name == 'alpha.txt');
      expect(alpha.isDir, isFalse);
      expect(alpha.size, 3);
    });

    test('mkdir creates a directory visible to dart:io', () async {
      await sftp.mkdir('/from-sftp');
      expect(Directory('${sftpRoot.path}/from-sftp').existsSync(), isTrue);
    });

    test('upload streams a local file to a remote path', () async {
      // The transfer worker pipeline: local file → SFTP open(write|
      // create|truncate) → write loop → close. The fixture's
      // sequence handles the same wire protocol; this asserts the
      // bytes land verbatim.
      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-sftp-upload-${DateTime.now().microsecondsSinceEpoch}',
      );
      const payload = 'hello-from-the-test-suite';
      await localTmp.writeAsString(payload);
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      await sftp.upload(localTmp.path, '/uploaded.txt', null);

      expect(File('${sftpRoot.path}/uploaded.txt').existsSync(), isTrue);
      expect(File('${sftpRoot.path}/uploaded.txt').readAsStringSync(), payload);
    });

    test('download streams a remote file to a local path', () async {
      const payload = 'roundtrip-payload';
      File('${sftpRoot.path}/seeded.txt').writeAsStringSync(payload);
      final localTmp = File(
        '${Directory.systemTemp.path}/lfs-sftp-download-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        if (await localTmp.exists()) await localTmp.delete();
      });

      await sftp.download('/seeded.txt', localTmp.path, null);
      expect(localTmp.readAsStringSync(), payload);
    });

    test('rename moves an existing file', () async {
      File('${sftpRoot.path}/oldname.txt').writeAsStringSync('x');
      await sftp.rename('/oldname.txt', '/newname.txt');
      expect(File('${sftpRoot.path}/oldname.txt').existsSync(), isFalse);
      expect(File('${sftpRoot.path}/newname.txt').existsSync(), isTrue);
    });

    test('remove deletes a file', () async {
      File('${sftpRoot.path}/disposable.txt').writeAsStringSync('bye');
      await sftp.remove('/disposable.txt');
      expect(File('${sftpRoot.path}/disposable.txt').existsSync(), isFalse);
    });

    test('removeDir deletes an empty directory', () async {
      Directory('${sftpRoot.path}/scratch').createSync();
      await sftp.removeDir('/scratch');
      expect(Directory('${sftpRoot.path}/scratch').existsSync(), isFalse);
    });

    test(
      'list of a non-existent path surfaces an SFTPError, not a hang',
      () async {
        // Defensive: a typo in the path should bubble through as an
        // exception, not stall the SFTP session. Previous regressions
        // around bus-event delivery would have masqueraded as a hang
        // here if the Rust side dropped the error response.
        await expectLater(
          sftp.list('/does/not/exist').timeout(const Duration(seconds: 5)),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('path traversal via "../" is rejected by the fixture', () async {
      // The fixture's SFTP handler resolves paths against the
      // tempdir root and rejects any `..` component with
      // PermissionDenied. This is a self-test for the fixture's
      // own safety, not an LfS production assertion — but if the
      // fixture ever started accepting `..`, an attacker who
      // landed on a localhost SFTP would be reachable via the
      // shipped test surface.
      await expectLater(
        sftp.list('/../').timeout(const Duration(seconds: 5)),
        throwsA(isA<Exception>()),
      );
    });
  });
}
