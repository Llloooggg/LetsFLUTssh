import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/sftp/sftp_client.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/transfer/conflict_resolver.dart';
import 'package:letsflutssh/core/transfer/transfer_manager.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/features/file_browser/transfer_helpers.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';

class _FakeLoc implements S {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake SFTPService — never called because TransferManager has parallelism: 0,
/// so tasks stay queued and their run() closures are never invoked.
class _FakeSFTPService extends Fake implements SFTPService {
  final Set<String> existingRemote = {};

  @override
  Future<bool> exists(String path) async => existingRemote.contains(path);
}

/// TransferManager subclass that captures enqueued tasks for inspection.
/// Uses parallelism: 0 so tasks remain in the queue and are never executed.
class _CapturingTransferManager extends TransferManager {
  final List<TransferTask> capturedTasks = [];

  _CapturingTransferManager() : super(parallelism: 0);

  @override
  String enqueue(TransferTask task) {
    capturedTasks.add(task);
    return super.enqueue(task);
  }
}

void main() {
  late _CapturingTransferManager manager;
  late _FakeSFTPService fakeSftp;
  late _FakeLoc fakeLoc;

  setUp(() {
    manager = _CapturingTransferManager();
    fakeSftp = _FakeSFTPService();
    fakeLoc = _FakeLoc();
  });

  tearDown(() {
    manager.dispose();
  });

  group('TransferHelpers.enqueueUpload', () {
    test('creates task with correct name, direction, and paths for a file', () {
      final entry = FileEntry(
        name: 'readme.txt',
        path: '/home/user/readme.txt',
        size: 1024,
        modTime: DateTime(2025, 1, 1),
        isDir: false,
      );

      TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.capturedTasks, hasLength(1));
      final task = manager.capturedTasks.first;
      expect(task.name, 'readme.txt');
      expect(task.direction, TransferDirection.upload);
      expect(task.sourcePath, '/home/user/readme.txt');
      expect(task.targetPath, '/srv/www/readme.txt');
      expect(task.sizeBytes, 1024);
    });

    test('creates task with trailing slash in name for directory entry', () {
      final entry = FileEntry(
        name: 'images',
        path: '/home/user/images',
        size: 0,
        modTime: DateTime(2025, 1, 1),
        isDir: true,
      );

      TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.capturedTasks, hasLength(1));
      final task = manager.capturedTasks.first;
      expect(task.name, 'images/');
      expect(task.direction, TransferDirection.upload);
      expect(task.sourcePath, '/home/user/images');
      expect(task.targetPath, '/srv/www/images');
    });

    test('increments queue length after enqueue', () {
      expect(manager.queueLength, 0);

      final entry = FileEntry(
        name: 'file.txt',
        path: '/home/user/file.txt',
        size: 512,
        modTime: DateTime(2025, 1, 1),
        isDir: false,
      );

      TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        remoteDirPath: '/remote',
        remoteCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.queueLength, 1);
    });
  });

  group('TransferHelpers.enqueueDownload', () {
    test('creates task with correct name, direction, and paths for a file', () {
      final entry = FileEntry(
        name: 'data.csv',
        path: '/srv/data/data.csv',
        size: 2048,
        modTime: DateTime(2025, 6, 15),
        isDir: false,
      );

      TransferHelpers.enqueueDownload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        localDirPath: '/home/user/downloads',
        localCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.capturedTasks, hasLength(1));
      final task = manager.capturedTasks.first;
      expect(task.name, 'data.csv');
      expect(task.direction, TransferDirection.download);
      expect(task.sourcePath, '/srv/data/data.csv');
      expect(task.targetPath, '/home/user/downloads/data.csv');
      expect(task.sizeBytes, 2048);
    });

    test('creates task with trailing slash in name for directory entry', () {
      final entry = FileEntry(
        name: 'logs',
        path: '/var/log/app/logs',
        size: 0,
        modTime: DateTime(2025, 3, 10),
        isDir: true,
      );

      TransferHelpers.enqueueDownload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        localDirPath: '/home/user/backup',
        localCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.capturedTasks, hasLength(1));
      final task = manager.capturedTasks.first;
      expect(task.name, 'logs/');
      expect(task.direction, TransferDirection.download);
      expect(task.sourcePath, '/var/log/app/logs');
      expect(task.targetPath, '/home/user/backup/logs');
    });

    test('increments queue length after enqueue', () {
      expect(manager.queueLength, 0);

      final entry = FileEntry(
        name: 'archive.tar.gz',
        path: '/srv/archive.tar.gz',
        size: 4096,
        modTime: DateTime(2025, 1, 1),
        isDir: false,
      );

      TransferHelpers.enqueueDownload(
        manager: manager,
        sftp: fakeSftp,
        entry: entry,
        localDirPath: '/tmp',
        localCtrl: null,
        loc: fakeLoc,
      );

      expect(manager.queueLength, 1);
    });
  });

  group('TransferHelpers.enqueueUpload — conflict handling', () {
    FileEntry fileEntry() => FileEntry(
      name: 'report.txt',
      path: '/home/user/report.txt',
      size: 100,
      modTime: DateTime(2025, 1, 1),
      isDir: false,
    );

    BatchConflictResolver resolverYielding(ConflictAction action) {
      return BatchConflictResolver(
        (_, {bool isRemote = false}) async => ConflictDecision(action),
      );
    }

    test('skips enqueue when resolver returns skip', () async {
      fakeSftp.existingRemote.add('/srv/www/report.txt');

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: fileEntry(),
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.skip),
      );

      expect(enqueued, isFalse);
      expect(manager.capturedTasks, isEmpty);
    });

    test('skips enqueue when resolver returns cancel', () async {
      fakeSftp.existingRemote.add('/srv/www/report.txt');

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: fileEntry(),
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.cancel),
      );

      expect(enqueued, isFalse);
      expect(manager.capturedTasks, isEmpty);
    });

    test('replace proceeds with the original target path', () async {
      fakeSftp.existingRemote.add('/srv/www/report.txt');

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: fileEntry(),
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.replace),
      );

      expect(enqueued, isTrue);
      expect(manager.capturedTasks, hasLength(1));
      expect(manager.capturedTasks.single.targetPath, '/srv/www/report.txt');
      expect(manager.capturedTasks.single.name, 'report.txt');
    });

    test('keepBoth enqueues a renamed sibling path', () async {
      fakeSftp.existingRemote.add('/srv/www/report.txt');

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: fileEntry(),
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.keepBoth),
      );

      expect(enqueued, isTrue);
      expect(manager.capturedTasks, hasLength(1));
      expect(
        manager.capturedTasks.single.targetPath,
        '/srv/www/report (1).txt',
      );
      // Display name tracks the renamed file.
      expect(manager.capturedTasks.single.name, 'report (1).txt');
    });

    test('enqueues normally when no conflict exists', () async {
      // existingRemote is empty → exists() returns false → no prompt.
      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: fileEntry(),
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.skip),
      );

      expect(enqueued, isTrue);
      expect(manager.capturedTasks.single.targetPath, '/srv/www/report.txt');
    });

    test('directory entries bypass the conflict check', () async {
      fakeSftp.existingRemote.add('/srv/www/images');
      final dirEntry = FileEntry(
        name: 'images',
        path: '/home/user/images',
        size: 0,
        modTime: DateTime(2025, 1, 1),
        isDir: true,
      );

      final enqueued = await TransferHelpers.enqueueUpload(
        manager: manager,
        sftp: fakeSftp,
        entry: dirEntry,
        remoteDirPath: '/srv/www',
        remoteCtrl: null,
        loc: fakeLoc,
        conflictResolver: resolverYielding(ConflictAction.skip),
      );

      // Even though the remote dir "exists" and the resolver would
      // say skip, directories are not gated by the conflict dialog.
      expect(enqueued, isTrue);
      expect(manager.capturedTasks, hasLength(1));
    });
  });

  test('multiple enqueues increase queue length cumulatively', () {
    final file1 = FileEntry(
      name: 'a.txt',
      path: '/local/a.txt',
      size: 100,
      modTime: DateTime(2025, 1, 1),
      isDir: false,
    );
    final file2 = FileEntry(
      name: 'b.txt',
      path: '/remote/b.txt',
      size: 200,
      modTime: DateTime(2025, 1, 1),
      isDir: false,
    );

    TransferHelpers.enqueueUpload(
      manager: manager,
      sftp: fakeSftp,
      entry: file1,
      remoteDirPath: '/remote',
      remoteCtrl: null,
      loc: fakeLoc,
    );
    TransferHelpers.enqueueDownload(
      manager: manager,
      sftp: fakeSftp,
      entry: file2,
      localDirPath: '/local',
      localCtrl: null,
      loc: fakeLoc,
    );

    expect(manager.queueLength, 2);
    expect(manager.capturedTasks, hasLength(2));
    expect(manager.capturedTasks[0].direction, TransferDirection.upload);
    expect(manager.capturedTasks[1].direction, TransferDirection.download);
  });
}
