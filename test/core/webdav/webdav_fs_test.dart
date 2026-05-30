import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/webdav/webdav_fs.dart';
import 'package:letsflutssh/src/rust/api/webdav.dart' as rust_webdav;

import '../../helpers/frb_bootstrap.dart';

/// In-process stub of [`rust_webdav.WebDavConnection`] that records
/// every method call and serves canned listings / metadata. The Rust
/// opaque interface is an abstract Dart class — implementing it
/// directly lets us exercise the [`WebDavFileSystem`] delegation
/// surface without binding a live HTTP transport.
class _StubWebDavConnection implements rust_webdav.WebDavConnection {
  final List<String> calls = <String>[];
  List<rust_webdav.WebDavDirEntry> listResult = const [];
  BigInt dirSizeResult = BigInt.zero;
  bool statThrows = false;
  rust_webdav.WebDavFileMetadata statResult = rust_webdav.WebDavFileMetadata(
    isDir: false,
    size: BigInt.zero,
  );

  @override
  Future<List<rust_webdav.WebDavDirEntry>> list({required String path}) async {
    calls.add('list:$path');
    return listResult;
  }

  @override
  Future<void> mkdir({required String path}) async {
    calls.add('mkdir:$path');
  }

  @override
  Future<void> remove({required String path}) async {
    calls.add('remove:$path');
  }

  @override
  Future<void> rename({required String from, required String to}) async {
    calls.add('rename:$from->$to');
  }

  @override
  Future<BigInt> dirSize({required String path}) async {
    calls.add('dirSize:$path');
    return dirSizeResult;
  }

  @override
  Future<rust_webdav.WebDavFileMetadata> stat({required String path}) async {
    calls.add('stat:$path');
    if (statThrows) throw StateError('stat failed');
    return statResult;
  }

  @override
  Future<Uint8List> getFull({required String path}) async {
    calls.add('getFull:$path');
    return Uint8List(0);
  }

  @override
  Future<void> putFull({required String path, required List<int> body}) async {
    calls.add('putFull:$path:${body.length}');
  }

  @override
  void dispose() {}

  @override
  bool get isDisposed => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `WebDavFileSystem.list` runs the FRB-backed `sortFileEntries`
  // against any non-empty stub listing. Bootstrap FRB so the sort
  // call resolves; the `WebDavConnection` itself remains an
  // in-process stub.
  setUpAll(requireFrbLoaded);

  group('WebDavFileSystem.initialDir', () {
    test(
      'extracts the path segment from a typical Nextcloud base URL',
      () async {
        final fs = WebDavFileSystem(
          _StubWebDavConnection(),
          'https://nc.example.com/remote.php/dav/files/admin/',
        );
        // The initial directory the browser opens at MUST be the
        // server-absolute path, not the full URL — every PROPFIND
        // `href` lives in that coordinate space.
        expect(await fs.initialDir(), '/remote.php/dav/files/admin/');
      },
    );

    test('falls back to "/" when the base URL has no path', () async {
      final fs = WebDavFileSystem(
        _StubWebDavConnection(),
        'https://nc.example.com',
      );
      expect(await fs.initialDir(), '/');
    });

    test('falls back to "/" when the base URL fails to parse', () async {
      // `Uri.parse` is famously lenient, but a leading colon throws.
      // The constructor must collapse the parse error to root so the
      // file browser still opens at a sane location.
      final fs = WebDavFileSystem(_StubWebDavConnection(), ':bad-url');
      expect(await fs.initialDir(), '/');
    });
  });

  group('WebDavFileSystem delegation', () {
    test(
      'list maps WebDavDirEntry rows to FileEntry + delegates path',
      () async {
        final stub = _StubWebDavConnection()
          ..listResult = [
            rust_webdav.WebDavDirEntry(
              name: 'b.txt',
              path: '/d/b.txt',
              isDir: false,
              size: BigInt.from(42),
              modifiedUnixMs: 1700000000000,
            ),
            rust_webdav.WebDavDirEntry(
              name: 'sub',
              path: '/d/sub',
              isDir: true,
              size: BigInt.zero,
            ),
          ];
        final fs = WebDavFileSystem(stub, 'https://h/dav/');

        final entries = await fs.list('/d');

        expect(stub.calls.single, 'list:/d');
        // Directories must come before files per the canonical sort.
        expect(entries.map((e) => e.name).toList(), ['sub', 'b.txt']);
        final file = entries.firstWhere((e) => e.name == 'b.txt');
        expect(file.size, 42);
        expect(file.isDir, isFalse);
        expect(file.modTime.millisecondsSinceEpoch, 1700000000000);
        final dir = entries.firstWhere((e) => e.name == 'sub');
        // Entries missing a server-side modification timestamp fall back
        // to epoch so the UI never paints `null` and the column stays
        // sortable. The fallback must NOT be `DateTime.now()` — that
        // would shift on every refresh.
        expect(dir.modTime.millisecondsSinceEpoch, 0);
      },
    );

    test('mkdir / remove / removeDir / rename forward verbatim', () async {
      final stub = _StubWebDavConnection();
      final fs = WebDavFileSystem(stub, 'https://h/dav/');

      await fs.mkdir('/a');
      await fs.remove('/a/x');
      // removeDir must map to the same DELETE as remove — most WebDAV
      // servers cascade collection deletes; routing them differently
      // would force a Dart-side recursive walk and diverge from the
      // documented contract.
      await fs.removeDir('/a/dir');
      await fs.rename('/a/x', '/a/y');

      expect(stub.calls, [
        'mkdir:/a',
        'remove:/a/x',
        'remove:/a/dir',
        'rename:/a/x->/a/y',
      ]);
    });

    test('dirSize narrows the BigInt result to int', () async {
      final stub = _StubWebDavConnection()..dirSizeResult = BigInt.from(123456);
      final fs = WebDavFileSystem(stub, 'https://h/dav/');

      expect(await fs.dirSize('/big'), 123456);
      expect(stub.calls.single, 'dirSize:/big');
    });

    test('exists collapses a stat throw to false', () async {
      final stub = _StubWebDavConnection()..statThrows = true;
      final fs = WebDavFileSystem(stub, 'https://h/dav/');

      // The upload-conflict path treats every probe failure
      // (404 / 410 / network blip / auth error) as "target absent" —
      // the contract MUST swallow the exception, never rethrow.
      expect(await fs.exists('/missing'), isFalse);
      expect(stub.calls.single, 'stat:/missing');
    });

    test('exists returns true when stat succeeds', () async {
      final stub = _StubWebDavConnection();
      final fs = WebDavFileSystem(stub, 'https://h/dav/');
      expect(await fs.exists('/here'), isTrue);
    });

    test('capabilities are the object-store default', () {
      final fs = WebDavFileSystem(_StubWebDavConnection(), 'https://h/dav/');
      // WebDAV PROPFIND surfaces neither POSIX mode bits nor a
      // per-resource owner, so the file pane must hide both columns.
      expect(fs.capabilities, same(FileSystemCapabilities.objectStore));
      expect(fs.capabilities.posixMode, isFalse);
      expect(fs.capabilities.owner, isFalse);
    });
  });

  group('WebDavFileSystem.flatWalkFiles', () {
    test('recurses through list using the shared helper', () async {
      // First call lists root; subsequent calls list each subdir.
      // The helper drives recursion via repeated `list` calls on
      // the WebDavFileSystem itself — WebDAV has no single-shot
      // walker, so this is the canonical shape.
      final stub = _StubWebDavConnection();
      stub.listResult = [
        rust_webdav.WebDavDirEntry(
          name: 'top.txt',
          path: '/root/top.txt',
          isDir: false,
          size: BigInt.from(7),
        ),
      ];
      final fs = WebDavFileSystem(stub, 'https://h/dav/');

      final leaves = await fs.flatWalkFiles('/root');

      expect(leaves.length, 1);
      expect(leaves.single.relPath, 'top.txt');
      expect(leaves.single.size, 7);
    });
  });

  // covered by integration: the live transport (PROPFIND / MKCOL /
  // DELETE / MOVE / PUT to a real WebDAV server) is exercised end-to-end
  // by the manual connect-test path against a Nextcloud / mod_dav
  // instance — unit tests stop at the delegation boundary.
}
