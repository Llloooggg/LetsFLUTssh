import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';

void main() {
  group('Constants', () {
    test('sftpMaxRecursionDepth caps at 100', () {
      expect(sftpMaxRecursionDepth, 100);
    });

    test('sftpMaxConcurrentFileTransfers is 4', () {
      // Modest concurrency — see file header for OpenSSH MaxSessions
      // rationale.
      expect(sftpMaxConcurrentFileTransfers, 4);
    });
  });

  group('RemoteSftpFs.removeDir (recursive)', () {
    test('removes nested files + dirs in depth-first order', () async {
      // Tree:
      //   /a/
      //     ├── f1
      //     └── b/
      //         ├── f2
      //         └── c/  (empty)
      final fs = _FakeRemoteSftpFs.fromTree({
        '/a': ['f1', 'b/'],
        '/a/b': ['f2', 'c/'],
        '/a/b/c': [],
      });

      await fs.removeDir('/a');

      // Files removed before parent dirs.
      expect(fs.removedFiles, contains('/a/f1'));
      expect(fs.removedFiles, contains('/a/b/f2'));
      // Empty dirs popped bottom-up: c first, then b, then a.
      expect(fs.removedEmptyDirs, ['/a/b/c', '/a/b', '/a']);
    });

    test('removes a leaf empty directory directly', () async {
      final fs = _FakeRemoteSftpFs.fromTree({'/empty': []});
      await fs.removeDir('/empty');
      expect(fs.removedEmptyDirs, ['/empty']);
      expect(fs.removedFiles, isEmpty);
    });

    test('throws on recursion past sftpMaxRecursionDepth', () async {
      // Synthetic deep tree — every level has exactly one subdir.
      final tree = <String, List<String>>{};
      var path = '';
      for (var i = 0; i <= sftpMaxRecursionDepth + 5; i++) {
        path = '$path/d$i';
        tree[path] = ['d${i + 1}/'];
      }
      final fs = _FakeRemoteSftpFs.fromTree(tree);

      expect(() => fs.removeDir('/d0'), throwsA(isA<StateError>()));
    });
  });

  group('RemoteSftpFs.uploadDir (recursive)', () {
    late Directory tmpRoot;

    setUp(() => tmpRoot = Directory.systemTemp.createTempSync('lfs_sftp_up_'));
    tearDown(() {
      if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
    });

    test('uploads every file + creates intermediate dirs', () async {
      // Local tree:
      //   tmpRoot/
      //     a.txt
      //     sub/
      //       b.txt
      File(p.join(tmpRoot.path, 'a.txt')).writeAsStringSync('hello-a');
      Directory(p.join(tmpRoot.path, 'sub')).createSync();
      File(p.join(tmpRoot.path, 'sub', 'b.txt')).writeAsStringSync('hello-b');

      final fs = _FakeRemoteSftpFs.empty();

      await fs.uploadDir(tmpRoot.path, '/remote', null);

      expect(fs.uploaded.map((u) => u.remotePath), [
        '/remote/a.txt',
        '/remote/sub/b.txt',
      ]);
      expect(fs.mkdirs, ['/remote', '/remote/sub']);
    });

    test(
      'emits TransferProgress with correct totalBytes (file count)',
      () async {
        File(p.join(tmpRoot.path, 'a.txt')).writeAsStringSync('a');
        File(p.join(tmpRoot.path, 'b.txt')).writeAsStringSync('b');

        final fs = _FakeRemoteSftpFs.empty();
        final events = <TransferProgress>[];

        await fs.uploadDir(tmpRoot.path, '/remote', events.add);

        expect(events.length, 2);
        // Each event's totalBytes = total file count (the walker repurposes
        // the field for "total files in batch", not bytes).
        for (final e in events) {
          expect(e.totalBytes, 2);
          expect(e.isUpload, isTrue);
        }
        expect(events.last.isCompleted, isTrue);
      },
    );

    test('mkdir failure is logged + walking continues', () async {
      File(p.join(tmpRoot.path, 'a.txt')).writeAsStringSync('a');

      final fs = _FakeRemoteSftpFs.empty(mkdirThrows: true);
      // mkdir-throw must NOT abort the walker — directory may already
      // exist server-side.
      await fs.uploadDir(tmpRoot.path, '/remote', null);

      expect(fs.uploaded.map((u) => u.remotePath), ['/remote/a.txt']);
    });
  });

  group('RemoteSftpFs.downloadDir (recursive)', () {
    late Directory tmpRoot;

    setUp(() => tmpRoot = Directory.systemTemp.createTempSync('lfs_sftp_dl_'));
    tearDown(() {
      if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
    });

    test('downloads every file + builds local dirs', () async {
      final fs = _FakeRemoteSftpFs.fromTree({
        '/remote': ['a.txt', 'sub/'],
        '/remote/sub': ['b.txt'],
      });
      final localTarget = p.join(tmpRoot.path, 'pulled');

      await fs.downloadDir('/remote', localTarget, null);

      // Local files materialised by the fake (writes "fake" content).
      expect(File(p.join(localTarget, 'a.txt')).existsSync(), isTrue);
      expect(File(p.join(localTarget, 'sub', 'b.txt')).existsSync(), isTrue);
    });

    test('emits per-file progress with running counter', () async {
      final fs = _FakeRemoteSftpFs.fromTree({
        '/remote': ['a.txt', 'b.txt'],
      });
      final events = <TransferProgress>[];
      await fs.downloadDir('/remote', tmpRoot.path, events.add);

      expect(events.length, 2);
      expect(events.first.doneBytes, lessThanOrEqualTo(2));
      expect(events.last.doneBytes, 2);
      expect(events.last.isCompleted, isTrue);
      for (final e in events) {
        expect(e.isUpload, isFalse);
      }
    });
  });
}

/// Fake [RemoteSftpFs] that records every call so the recursive
/// composites (`uploadDir` / `downloadDir` / `removeDir`) can be
/// exercised without a live SFTP connection.
class _FakeRemoteSftpFs extends RemoteSftpFs {
  _FakeRemoteSftpFs._(this._tree, {this.mkdirThrows = false});

  /// Empty tree — used by upload tests where the local source drives
  /// the walk.
  factory _FakeRemoteSftpFs.empty({bool mkdirThrows = false}) =>
      _FakeRemoteSftpFs._({}, mkdirThrows: mkdirThrows);

  /// Build a fake remote-side tree from a `path → entry-name list` map.
  /// An entry ending with `/` is a directory; otherwise a file.
  factory _FakeRemoteSftpFs.fromTree(Map<String, List<String>> tree) {
    return _FakeRemoteSftpFs._(Map.of(tree));
  }

  final Map<String, List<String>> _tree;
  final bool mkdirThrows;

  final List<({String localPath, String remotePath})> uploaded = [];
  final List<String> mkdirs = [];
  final List<String> removedFiles = [];
  final List<String> removedEmptyDirs = [];

  @override
  Future<String> getwd() async => '/';

  @override
  Future<List<FileEntry>> list(String path) async {
    final names = _tree[path] ?? const <String>[];
    return [
      for (final name in names)
        FileEntry(
          name: name.endsWith('/') ? name.substring(0, name.length - 1) : name,
          path: path == '/'
              ? '/${name.endsWith('/') ? name.substring(0, name.length - 1) : name}'
              : '$path/${name.endsWith('/') ? name.substring(0, name.length - 1) : name}',
          size: 0,
          mode: 0,
          modTime: DateTime.utc(2026, 1, 1),
          isDir: name.endsWith('/'),
          owner: '',
        ),
    ];
  }

  @override
  Future<bool> exists(String path) async => _tree.containsKey(path);

  @override
  Future<void> mkdir(String path) async {
    if (mkdirThrows) {
      throw StateError('mkdir refused (test): $path');
    }
    mkdirs.add(path);
  }

  @override
  Future<void> remove(String path) async {
    removedFiles.add(path);
  }

  @override
  Future<void> removeEmptyDir(String path) async {
    removedEmptyDirs.add(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {}

  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {
    uploaded.add((localPath: localPath, remotePath: remotePath));
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {
    // Materialise an empty local file so callers' subsequent
    // `existsSync` checks pass.
    await File(localPath).create(recursive: true);
  }

  @override
  void close() {}
}
