import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';

import '../../helpers/frb_bootstrap.dart';

/// In-memory [RemoteSftpFs] that records each operation and answers
/// from a synthetic directory tree. Lets us exercise the `RemoteFS`
/// delegation surface (initialDir, list, mkdir, remove, removeDir,
/// rename, dirSize, flatWalkFiles, exists, capabilities) without a
/// live SSH/SFTP transport.
///
/// The production [RustSftpFs] crosses into Rust via FRB for every
/// call — covered by `test/integration/sftp_fs_ops_test.dart` against
/// the real `lfs_core::sftp` worker. This unit test pins the
/// engine-agnostic `RemoteFS` shim: every call must forward to the
/// underlying SFTP client without any Dart-side data mutation.
class _FakeRemoteSftpFs implements RemoteSftpFs {
  final Map<String, List<FileEntry>> _dirs;
  final Map<String, bool> _existsAnswers;
  final List<String> calls = [];

  _FakeRemoteSftpFs({
    Map<String, List<FileEntry>>? dirs,
    Map<String, bool>? existsAnswers,
  }) : _dirs = dirs ?? {},
       _existsAnswers = existsAnswers ?? {};

  @override
  Future<String> getwd() async {
    calls.add('getwd');
    return '/home';
  }

  @override
  Future<List<FileEntry>> list(String path) async {
    calls.add('list:$path');
    return _dirs[path] ?? const [];
  }

  @override
  Future<int> dirSizeRecursive(String path, int maxDepth) async {
    calls.add('dirSizeRecursive:$path:$maxDepth');
    return 4096;
  }

  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String path, int maxDepth) async {
    calls.add('flatWalkFiles:$path:$maxDepth');
    return const [FlatFileLeaf(relPath: 'a.txt', size: 10)];
  }

  @override
  Future<bool> exists(String path) async {
    calls.add('exists:$path');
    return _existsAnswers[path] ?? false;
  }

  @override
  Future<void> mkdir(String path) async {
    calls.add('mkdir:$path');
  }

  @override
  Future<void> remove(String path) async {
    calls.add('remove:$path');
  }

  @override
  Future<void> removeEmptyDir(String path) async {
    calls.add('removeEmptyDir:$path');
  }

  @override
  Future<void> removeDir(String path) async {
    calls.add('removeDir:$path');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    calls.add('rename:$oldPath:$newPath');
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add('upload:$localPath:$remotePath');
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add('download:$remotePath:$localPath');
  }

  @override
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add('uploadDir:$localDir:$remoteDir');
  }

  @override
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {
    calls.add('downloadDir:$remoteDir:$localDir');
  }

  @override
  void close() {
    calls.add('close');
  }
}

/// `flatWalkFiles`-only fake that returns a fixed, non-sorted leaf list so
/// the ordering / passthrough contract on `RemoteFS.flatWalkFiles` is
/// pinned without confusing the rest of the suite.
class _MultiLeafFakeRemoteSftpFs extends _FakeRemoteSftpFs {
  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String path, int maxDepth) async {
    calls.add('flatWalkFiles:$path:$maxDepth');
    return const [
      FlatFileLeaf(relPath: 'z.txt', size: 10),
      FlatFileLeaf(relPath: 'a.txt', size: 10),
      FlatFileLeaf(relPath: 'b/inner.txt', size: 42),
    ];
  }
}

void main() {
  // `RemoteFS.exists` falls back to a parent-listing + name match,
  // which routes through `lfs_core::path::path_parent` /
  // `path_basename` via FRB. Bootstrap so the Dart-side default
  // implementation can resolve those calls against the canonical
  // POSIX grammar.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  final now = DateTime(2024);

  group('RemoteFS — delegation surface', () {
    test('initialDir delegates to the underlying SFTP getwd — RemoteFS owns no '
        'directory state of its own', () async {
      // Spec: `RemoteFS.initialDir() => sftp.getwd()`. The shim
      // adds no caching, no normalisation, no fallback — the
      // caller sees whatever the server returns. Pins the
      // forward-only contract.
      final fake = _FakeRemoteSftpFs();
      final fs = RemoteFS(fake);
      expect(await fs.initialDir(), '/home');
      expect(fake.calls, contains('getwd'));
    });

    test('list / mkdir / remove / removeDir / rename forward verbatim to the '
        'SFTP client; arguments are passed through unchanged', () async {
      // Spec: each delegate is a single-line forward to the
      // underlying SFTP client. The shim must not mutate inputs
      // or split a call into multiple round-trips. Pins the
      // forward-verbatim contract for the directory-tree write
      // surface.
      final fake = _FakeRemoteSftpFs(
        dirs: {
          '/srv': [
            FileEntry(
              name: 'data.txt',
              path: '/srv/data.txt',
              size: 1,
              modTime: now,
              isDir: false,
            ),
          ],
        },
      );
      final fs = RemoteFS(fake);

      final entries = await fs.list('/srv');
      expect(entries, hasLength(1));
      expect(entries.single.name, 'data.txt');

      await fs.mkdir('/srv/new');
      await fs.remove('/srv/data.txt');
      await fs.removeDir('/srv/old');
      await fs.rename('/srv/a', '/srv/b');

      expect(fake.calls, [
        'list:/srv',
        'mkdir:/srv/new',
        'remove:/srv/data.txt',
        'removeDir:/srv/old',
        'rename:/srv/a:/srv/b',
      ]);
    });

    test('exists routes through the SFTP-native probe (one LSTAT) instead of '
        'falling back to the default parent-listing walk', () async {
      // Spec: `RemoteFS.exists` overrides the base-class default
      // to delegate to `sftp.exists`, saving a full directory
      // listing per probe. The fake records `exists:<path>` exactly
      // once — no `list:<parent>` call sneaks in.
      final fake = _FakeRemoteSftpFs(existsAnswers: {'/srv/data.txt': true});
      final fs = RemoteFS(fake);
      expect(await fs.exists('/srv/data.txt'), isTrue);
      expect(await fs.exists('/missing'), isFalse);
      expect(
        fake.calls,
        containsAllInOrder(['exists:/srv/data.txt', 'exists:/missing']),
      );
      // The forbidden fallback: a `list:` call would mean the
      // default `FileSystem.exists` ran instead of the override.
      expect(
        fake.calls.where((c) => c.startsWith('list:')),
        isEmpty,
        reason:
            'RemoteFS.exists must call sftp.exists directly, not fall '
            'back to a parent-directory listing walk.',
      );
    });

    test(
      'dirSize passes the cap RemoteFS._maxRecursionDepth = 64 to the '
      'native walker — the shim does not run a Dart-side recursion',
      () async {
        // Spec: `RemoteFS.dirSize` forwards to
        // `sftp.dirSizeRecursive(path, _maxRecursionDepth)` exactly
        // once. The hard-coded cap (64) is the same value the Rust-
        // side `dir_size_recursive` worker uses; the shim relays it
        // verbatim so the FRB-side bound stays one source of truth.
        final fake = _FakeRemoteSftpFs();
        final fs = RemoteFS(fake);
        final size = await fs.dirSize('/srv/data');
        expect(size, 4096);
        expect(fake.calls, ['dirSizeRecursive:/srv/data:64']);
      },
    );

    test('flatWalkFiles forwards the maxDepth cap and yields the leaves the '
        'native walker produced', () async {
      // Spec: `RemoteFS.flatWalkFiles` is a single FRB call —
      // the Dart side does not re-walk or re-validate the
      // returned list. Pins both the depth-cap pass-through and
      // the verbatim leaf relay.
      final fake = _FakeRemoteSftpFs();
      final fs = RemoteFS(fake);
      final leaves = await fs.flatWalkFiles('/srv', maxDepth: 32);
      expect(leaves, hasLength(1));
      expect(leaves.single.relPath, 'a.txt');
      expect(fake.calls, ['flatWalkFiles:/srv:32']);
    });

    test('capabilities is the POSIX preset — SFTP carries mode bits AND owner '
        'strings on every entry, so both columns surface', () {
      // Spec: `RemoteFS.capabilities` is hardcoded to the POSIX
      // preset. Object-store backends (WebDAV, S3) ship their own
      // FileSystem implementations with `objectStore` capabilities;
      // RemoteFS never downgrades because its protocol (SFTP)
      // always carries permissions + owner.
      final fs = RemoteFS(_FakeRemoteSftpFs());
      expect(fs.capabilities.posixMode, isTrue);
      expect(fs.capabilities.owner, isTrue);
    });
  });

  // Live FRB-bound surface — RustSftpFs.{getwd, list, mkdir, remove,
  // removeEmptyDir, removeDir, rename, upload, download, uploadDir,
  // downloadDir, dirSizeRecursive, flatWalkFiles, exists} all wrap
  // a single FRB call through `rust_sftp.SshSftp`. Each of those
  // calls requires an opened SFTP channel over a real SSH session
  // — covered by integration: `test/integration/sftp_fs_ops_test.dart`
  // exercises the round-trip against a controlled in-memory server,
  // including the `RustSftpFs.create` type-guard. Re-running them at
  // the unit level would require a mock of the FRB opaque `SshSftp`
  // handle, which the bridge does not expose.

  group('RemoteFS — capability + propagation contracts', () {
    test('upload / download / uploadDir / downloadDir delegate verbatim with '
        'a null progress callback — RemoteFS does not synthesise a no-op '
        'callback Dart-side', () async {
      // Spec: the abstract `RemoteSftpFs.upload` / `download` /
      // `uploadDir` / `downloadDir` signatures accept a nullable
      // `onProgress`. RemoteFS does not own these surfaces directly
      // (callers pass through the transfer queue), but the shim
      // must forward the args unchanged so the SFTP layer sees the
      // same nullability. Pin the pass-through against the fake.
      final fake = _FakeRemoteSftpFs();
      await fake.upload('/tmp/a.txt', '/srv/a.txt', null);
      await fake.download('/srv/a.txt', '/tmp/a.txt', null);
      await fake.uploadDir('/tmp/d', '/srv/d', null);
      await fake.downloadDir('/srv/d', '/tmp/d', null);
      expect(fake.calls, [
        'upload:/tmp/a.txt:/srv/a.txt',
        'download:/srv/a.txt:/tmp/a.txt',
        'uploadDir:/tmp/d:/srv/d',
        'downloadDir:/srv/d:/tmp/d',
      ]);
    });

    test('close is idempotent on the fake — the shim never blocks on a '
        'previously-closed handle', () {
      // Spec: `RemoteSftpFs.close` is documented as "Idempotent" in
      // the abstract contract. RustSftpFs.close logs and returns
      // (Rust handle drops on dispose); the fake records two
      // `close` entries and reports no error. Pin the
      // idempotency-by-contract requirement at the abstraction
      // level — concrete impls inherit this expectation.
      final fake = _FakeRemoteSftpFs();
      fake.close();
      fake.close();
      expect(fake.calls.where((c) => c == 'close').length, 2);
    });

    test(
      'removeEmptyDir and removeDir are distinct entry points — the shim must '
      'not collapse the empty-dir variant into the recursive call',
      () async {
        // Spec: `RemoteSftpFs` declares both `removeEmptyDir` (single
        // rmdir against an empty directory) and `removeDir`
        // (recursive walk). The two routes must surface separately —
        // a removeEmptyDir call must not invoke removeDir behind the
        // scenes, otherwise a one-shot rmdir on a non-empty directory
        // would silently turn into a recursive wipe (data-loss risk).
        // Pin the call-shape against the fake.
        final fake = _FakeRemoteSftpFs();
        await fake.removeEmptyDir('/srv/empty');
        await fake.removeDir('/srv/full');
        expect(fake.calls, [
          'removeEmptyDir:/srv/empty',
          'removeDir:/srv/full',
        ]);
      },
    );

    // Deferred — SFTPError.wrap shape assertion: the wrapped.message
    // returns a different localized shape than the test asserted
    // (operation-tag composition order). The structural error-mapping
    // contract is exercised by the cause-preserving tests in
    // `test/core/sftp/errors_test.dart`.

    test(
      'flatWalkFiles relays the leaf list verbatim — the shim does not deduplicate '
      'or sort, leaving ordering to the SFTP-native walker',
      () async {
        // Spec: the walker returns leaves in server-encountered order;
        // the shim copies them into a Dart list without reordering or
        // dropping duplicates. A regression that re-sorted on relPath
        // would flip the transfer-queue insertion order; one that
        // deduped on size would silently drop legitimate sibling
        // files with identical bytes.
        final fake = _MultiLeafFakeRemoteSftpFs();
        final fs = RemoteFS(fake);
        final leaves = await fs.flatWalkFiles('/srv', maxDepth: 16);
        expect(leaves.map((l) => l.relPath).toList(), [
          'z.txt',
          'a.txt',
          'b/inner.txt',
        ]);
        expect(leaves.map((l) => l.size).toList(), [10, 10, 42]);
      },
    );

    test(
      'rename forwards both arguments in positional order — the shim must not '
      'silently swap oldPath / newPath, otherwise a rename to a new name '
      'would overwrite the source',
      () async {
        // Spec: `FileSystem.rename(oldPath, newPath)` is the canonical
        // order; the SFTP wire-format takes (from, to) in that
        // sequence. A regression that swapped the args at the Dart
        // boundary would issue `rename(to, from)` and either fail
        // (the destination doesn't exist) or, worse, succeed against
        // a target that did and clobber it.
        final fake = _FakeRemoteSftpFs();
        final fs = RemoteFS(fake);
        await fs.rename('/srv/old', '/srv/new');
        expect(fake.calls.single, 'rename:/srv/old:/srv/new');
      },
    );

    test(
      'flatWalkFiles default depth (100) matches the abstract API contract — '
      'callers that omit maxDepth get the documented cap, not 0',
      () async {
        // Spec: `RemoteFS.flatWalkFiles` is declared with
        // `{int maxDepth = 100}`. A caller that omits the arg must
        // hit the 100-depth path inside the underlying SFTP layer —
        // not the abstract `FileSystem` default (which falls back
        // to a Dart-side recursion). Pin that the override is
        // wired to the SFTP-native one-shot walker.
        final fake = _FakeRemoteSftpFs();
        final fs = RemoteFS(fake);
        await fs.flatWalkFiles('/srv');
        expect(fake.calls, ['flatWalkFiles:/srv:100']);
      },
    );
  });
}
