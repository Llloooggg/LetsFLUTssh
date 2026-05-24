import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/transfer_helpers.dart';
import 'package:letsflutssh/providers/transfer_provider.dart';

/// In-memory `FileSystem` stub that records the calls
/// `TransferHelpers` makes — the regression test below pins that
/// the helpers route through the generic [`FileSystem`] surface
/// rather than the SFTP-specific [`RemoteSftpFs`] shape. Until the
/// generalisation landed, calling `TransferHelpers.enqueueUpload`
/// with a non-SFTP backend (WebDAV / S3) was impossible — the
/// signature demanded a `RemoteSftpFs` the caller couldn't
/// provide, so drag-drop / paste / transfer-button on those panes
/// no-op'd silently. The test below proves the helpers now accept
/// any `FileSystem` and reach the manager.
class _RecordingFs implements FileSystem {
  final List<String> createdDirs = [];
  // Set of paths the stub treats as "already present"; consulted
  // by [`exists`]. Empty default — `enqueueUpload` skips the
  // conflict probe when no `conflictResolver` is passed, but the
  // surface stays available for future tests that exercise it.
  final Set<String> existing;

  // ignore: unused_element_parameter
  _RecordingFs({this.existing = const {}});

  @override
  Future<String> initialDir() async => '/';

  @override
  Future<List<FileEntry>> list(String path) async => const [];

  @override
  Future<void> mkdir(String path) async => createdDirs.add(path);

  @override
  Future<void> remove(String path) async {}

  @override
  Future<void> removeDir(String path) async {}

  @override
  Future<void> rename(String oldPath, String newPath) async {}

  @override
  Future<int> dirSize(String path) async => 0;

  @override
  Future<List<FlatFileLeaf>> flatWalkFiles(String root, {int maxDepth = 100}) =>
      flatWalkViaList(this, root, maxDepth: maxDepth);

  @override
  Future<bool> exists(String path) async => existing.contains(path);

  @override
  FileSystemCapabilities get capabilities => FileSystemCapabilities.objectStore;
}

/// Captures every `enqueueUpload` / `enqueueDownload` call on the
/// notifier — the assertions below grep through this list rather
/// than driving the real Rust transfer queue.
class _CapturingTransfersNotifier extends TransfersNotifier {
  final uploads = <Map<String, Object?>>[];
  final downloads = <Map<String, Object?>>[];

  @override
  TransfersState build() {
    state = const TransfersState();
    return state;
  }

  @override
  Future<String> enqueueUpload({
    required String connectionId,
    required String name,
    required String localPath,
    required String remotePath,
    int sizeBytes = 0,
  }) async {
    uploads.add({
      'connectionId': connectionId,
      'name': name,
      'localPath': localPath,
      'remotePath': remotePath,
      'sizeBytes': sizeBytes,
    });
    return 'fake-upload-${uploads.length}';
  }

  @override
  Future<String> enqueueDownload({
    required String connectionId,
    required String name,
    required String remotePath,
    required String localPath,
    int sizeBytes = 0,
  }) async {
    downloads.add({
      'connectionId': connectionId,
      'name': name,
      'remotePath': remotePath,
      'localPath': localPath,
      'sizeBytes': sizeBytes,
    });
    return 'fake-download-${downloads.length}';
  }
}

void main() {
  // The download-directory walk rejects unsafe SFTP-supplied entry
  // names before joining them onto the user-chosen destination. That
  // safety predicate is owned by Rust
  // (`lfs_core::path::is_safe_transfer_entry_name`, surfaced as
  // `path_is_safe_entry_name`) and is unit + property tested there —
  // it cannot run in this pure-Dart harness without Rust-lib init.
  group('TransferHelpers — generic FileSystem dispatch', () {
    test('enqueueUpload reaches the transfer manager when given a non-SFTP '
        'FileSystem (the WebDAV / S3 drag-drop path)', () async {
      final manager = _CapturingTransfersNotifier();
      final fs = _RecordingFs();
      final entry = FileEntry(
        name: 'photo.png',
        path: '/local/photo.png',
        size: 4096,
        modTime: DateTime(2026, 5, 16),
        isDir: false,
      );

      final ok = await TransferHelpers.enqueueUpload(
        manager: manager,
        remoteFs: fs,
        connectionId: 'conn-webdav-1',
        entry: entry,
        remoteDirPath: '/uploads',
        remoteCtrl: null,
      );

      expect(ok, isTrue);
      expect(manager.uploads, hasLength(1));
      expect(manager.uploads.first['connectionId'], 'conn-webdav-1');
      expect(manager.uploads.first['localPath'], '/local/photo.png');
      expect(manager.uploads.first['remotePath'], '/uploads/photo.png');
      expect(manager.uploads.first['sizeBytes'], 4096);
    });

    test(
      'enqueueDownload reaches the transfer manager with a generic '
      'FileSystem (mirrors the upload contract for the download side)',
      () async {
        final manager = _CapturingTransfersNotifier();
        final fs = _RecordingFs();
        final entry = FileEntry(
          name: 'data.csv',
          path: '/remote/data.csv',
          size: 8192,
          modTime: DateTime(2026, 5, 16),
          isDir: false,
        );

        final ok = await TransferHelpers.enqueueDownload(
          manager: manager,
          remoteFs: fs,
          connectionId: 'conn-s3-1',
          entry: entry,
          localDirPath: '/downloads',
          localCtrl: null,
        );

        expect(ok, isTrue);
        expect(manager.downloads, hasLength(1));
        expect(manager.downloads.first['connectionId'], 'conn-s3-1');
        expect(manager.downloads.first['remotePath'], '/remote/data.csv');
        expect(manager.downloads.first['sizeBytes'], 8192);
      },
    );
  });
}
