import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/s3/s3_fs.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/src/rust/api/s3.dart' as rust_s3;

import '../../helpers/frb_bootstrap.dart';

/// In-process stub of [`rust_s3.S3Connection`] that records every
/// method call and serves canned listings / metadata. The Rust
/// opaque interface is an abstract Dart class — implementing it
/// directly lets us exercise the [`S3FileSystem`] delegation surface
/// without binding a live HTTP transport to S3.
class _StubS3Connection implements rust_s3.S3Connection {
  final List<String> calls = <String>[];
  List<rust_s3.S3DirEntry> listResult = const [];
  BigInt dirSizeResult = BigInt.zero;
  bool statThrows = false;
  rust_s3.S3FileMetadata statResult = rust_s3.S3FileMetadata(
    isDir: false,
    size: BigInt.zero,
  );

  @override
  Future<List<rust_s3.S3DirEntry>> list({required String path}) async {
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
  Future<rust_s3.S3FileMetadata> stat({required String path}) async {
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
  Future<String> generatePresignedUrl({
    required String bucket,
    required String key,
    required int expiresSeconds,
  }) async {
    calls.add('presign:$bucket:$key:$expiresSeconds');
    return 'https://example/$bucket/$key?signed';
  }

  @override
  void dispose() {}

  @override
  bool get isDisposed => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `S3FileSystem.list` invokes the FRB-backed `sortFileEntries` for
  // any non-empty stub listing. Bootstrap FRB so that sort resolves;
  // the `S3Connection` itself stays an in-process stub.
  setUpAll(requireFrbLoaded);

  group('S3FileSystem.initialDir', () {
    test('echoes whatever the caller handed in at construction', () async {
      // S3 has no "current working directory" — the caller decides
      // the implicit root from the configured bucket + prefix.
      final fs = S3FileSystem(_StubS3Connection(), 's3://bucket/prefix');
      expect(await fs.initialDir(), 's3://bucket/prefix');
    });

    test('preserves the empty-string root (default bucket case)', () async {
      // The contract says an empty initial dir maps to the default
      // bucket root — the file-system MUST NOT silently substitute
      // "/" or any other value, or the caller's bucket dispatch
      // would skew.
      final fs = S3FileSystem(_StubS3Connection(), '');
      expect(await fs.initialDir(), '');
    });
  });

  group('S3FileSystem delegation', () {
    test(
      'list maps S3DirEntry rows to FileEntry and sorts dirs first',
      () async {
        final stub = _StubS3Connection()
          ..listResult = [
            rust_s3.S3DirEntry(
              name: 'z.bin',
              path: 's3://b/z.bin',
              isDir: false,
              size: BigInt.from(99),
              modifiedUnixMs: 1700000000000,
            ),
            rust_s3.S3DirEntry(
              name: 'pics',
              path: 's3://b/pics',
              isDir: true,
              size: BigInt.zero,
            ),
          ];
        final fs = S3FileSystem(stub, '');

        final entries = await fs.list('s3://b');

        expect(stub.calls.single, 'list:s3://b');
        // Common-prefix rows surface as directories and MUST sort
        // before object rows so the browser matches every other backend.
        expect(entries.map((e) => e.name).toList(), ['pics', 'z.bin']);
        final file = entries.firstWhere((e) => e.name == 'z.bin');
        expect(file.size, 99);
        expect(file.isDir, isFalse);
        expect(file.modTime.millisecondsSinceEpoch, 1700000000000);
        // Entries without a server-side mtime must default to epoch
        // (stable) — never `DateTime.now()` which would re-sort on
        // every refresh.
        final dir = entries.firstWhere((e) => e.name == 'pics');
        expect(dir.modTime.millisecondsSinceEpoch, 0);
      },
    );

    test('mkdir / remove / removeDir / rename forward verbatim', () async {
      final stub = _StubS3Connection();
      final fs = S3FileSystem(stub, '');

      await fs.mkdir('s3://b/dir/');
      await fs.remove('s3://b/file');
      // removeDir maps to the same single DELETE — S3 has no native
      // directories; the marker key is what the browser created via
      // mkdir, so a single DELETE clears it. Bulk recursion is a
      // follow-up the caller drives per-entry.
      await fs.removeDir('s3://b/dir/');
      await fs.rename('s3://b/old', 's3://b/new');

      expect(stub.calls, [
        'mkdir:s3://b/dir/',
        'remove:s3://b/file',
        'remove:s3://b/dir/',
        'rename:s3://b/old->s3://b/new',
      ]);
    });

    test('dirSize narrows the BigInt result to int', () async {
      final stub = _StubS3Connection()..dirSizeResult = BigInt.from(987654);
      final fs = S3FileSystem(stub, '');

      expect(await fs.dirSize('s3://b/prefix'), 987654);
      expect(stub.calls.single, 'dirSize:s3://b/prefix');
    });

    test('exists collapses every stat error to false', () async {
      final stub = _StubS3Connection()..statThrows = true;
      final fs = S3FileSystem(stub, '');

      // The conflict resolver treats "key not found", "access denied",
      // and network errors all as "target absent" — the contract
      // MUST swallow the exception, never rethrow.
      expect(await fs.exists('s3://b/missing'), isFalse);
      expect(stub.calls.single, 'stat:s3://b/missing');
    });

    test('exists returns true when HeadObject succeeds', () async {
      final stub = _StubS3Connection();
      final fs = S3FileSystem(stub, '');
      expect(await fs.exists('s3://b/here'), isTrue);
    });

    test('capabilities are the object-store default', () {
      final fs = S3FileSystem(_StubS3Connection(), '');
      // S3 objects carry neither POSIX mode bits nor a per-object
      // owner; the file pane MUST hide both columns.
      expect(fs.capabilities, same(FileSystemCapabilities.objectStore));
      expect(fs.capabilities.posixMode, isFalse);
      expect(fs.capabilities.owner, isFalse);
    });
  });

  group('S3FileSystem.flatWalkFiles', () {
    test('recurses via the shared list-based walker', () async {
      // Object-store backends have no single-call walker — the
      // canonical shape is the shared helper driving repeated
      // `list` calls against the file system itself.
      final stub = _StubS3Connection();
      stub.listResult = [
        rust_s3.S3DirEntry(
          name: 'top.bin',
          path: 's3://b/top.bin',
          isDir: false,
          size: BigInt.from(11),
        ),
      ];
      final fs = S3FileSystem(stub, '');

      final leaves = await fs.flatWalkFiles('s3://b');

      expect(leaves.length, 1);
      expect(leaves.single.relPath, 'top.bin');
      expect(leaves.single.size, 11);
    });
  });

  // covered by integration: the live S3 transport (ListObjectsV2 /
  // HeadObject / CopyObject + DeleteObject rename / presigned-URL
  // generation against AWS or a MinIO test bucket) is exercised
  // end-to-end by the manual connect-test path — unit tests stop
  // at the delegation boundary.
}
