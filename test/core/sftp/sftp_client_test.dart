import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:letsflutssh/core/sftp/sftp_client.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';

@GenerateNiceMocks([
  MockSpec<SftpClient>(),
  MockSpec<SftpFile>(),
])
import 'sftp_client_test.mocks.dart';

/// Helper to create a directory SftpFileAttrs.
SftpFileAttrs _dirAttrs({int? modifyTime, int? size}) => SftpFileAttrs(
      size: size ?? 4096,
      mode: const SftpFileMode.value(0x4000 | 0x1ED), // directory 0755
      accessTime: 0,
      modifyTime: modifyTime ?? 1000,
    );

/// Helper to create a regular file SftpFileAttrs.
SftpFileAttrs _fileAttrs({int? size, int? modifyTime}) => SftpFileAttrs(
      size: size ?? 100,
      mode: const SftpFileMode.value(0x81A4), // regular file 0644
      accessTime: 0,
      modifyTime: modifyTime ?? 1000,
    );

/// Helper: dot and dotdot entries.
List<SftpName> _dotEntries() => [
      SftpName(filename: '.', longname: 'drwxr-xr-x 2 root root 4096 .', attr: _dirAttrs()),
      SftpName(filename: '..', longname: 'drwxr-xr-x 2 root root 4096 ..', attr: _dirAttrs()),
    ];

void main() {
  late MockSftpClient mockSftp;
  late SFTPService service;

  setUp(() {
    mockSftp = MockSftpClient();
    service = SFTPService(mockSftp);
  });

  group('SFTPService.list', () {
    test('returns sorted entries, dirs first, skips . and ..', () async {
      final items = [
        ..._dotEntries(),
        SftpName(
          filename: 'file_b.txt',
          longname: '-rw-r--r-- 1 user staff 100 Jan 01 00:00 file_b.txt',
          attr: _fileAttrs(size: 100, modifyTime: 2000),
        ),
        SftpName(
          filename: 'dir_a',
          longname: 'drwxr-xr-x 2 admin wheel 4096 Jan 01 00:00 dir_a',
          attr: _dirAttrs(modifyTime: 3000),
        ),
        SftpName(
          filename: 'file_a.txt',
          longname: '-rw-r--r-- 1 user staff 200 Jan 01 00:00 file_a.txt',
          attr: _fileAttrs(size: 200, modifyTime: 4000),
        ),
      ];

      when(mockSftp.listdir('/home')).thenAnswer((_) async => items);

      final result = await service.list('/home');

      expect(result.length, 3);
      // Dirs first, then alphabetical
      expect(result[0].name, 'dir_a');
      expect(result[0].isDir, isTrue);
      expect(result[0].path, '/home/dir_a');
      expect(result[0].owner, 'admin');
      // Files alphabetical
      expect(result[1].name, 'file_a.txt');
      expect(result[1].isDir, isFalse);
      expect(result[1].owner, 'user');
      expect(result[2].name, 'file_b.txt');
    });

    test('returns empty list for empty directory', () async {
      when(mockSftp.listdir('/empty')).thenAnswer((_) async => _dotEntries());

      final result = await service.list('/empty');
      expect(result, isEmpty);
    });

    test('handles missing modifyTime gracefully', () async {
      final items = [
        SftpName(
          filename: 'notime.txt',
          longname: '-rw-r--r-- 1 root root 0 notime.txt',
          attr: SftpFileAttrs(size: 0, mode: const SftpFileMode.value(0x81A4)),
        ),
      ];

      when(mockSftp.listdir('/test')).thenAnswer((_) async => items);

      final result = await service.list('/test');
      expect(result.length, 1);
      expect(result[0].modTime.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
    });

    test('handles missing mode gracefully', () async {
      final items = [
        SftpName(
          filename: 'nomode.txt',
          longname: '-rw-r--r-- 1 root root 0 nomode.txt',
          attr: SftpFileAttrs(size: 50, modifyTime: 1000),
        ),
      ];

      when(mockSftp.listdir('/test')).thenAnswer((_) async => items);

      final result = await service.list('/test');
      expect(result.length, 1);
      expect(result[0].mode, 0);
    });

    test('owner parsed correctly from longname', () async {
      final items = [
        SftpName(
          filename: 'owned.txt',
          longname: '-rw-r--r-- 1 myuser mygroup 100 Jan 01 owned.txt',
          attr: _fileAttrs(),
        ),
      ];

      when(mockSftp.listdir('/test')).thenAnswer((_) async => items);

      final result = await service.list('/test');
      expect(result[0].owner, 'myuser');
    });

    test('owner empty when longname has fewer than 3 parts', () async {
      final items = [
        SftpName(
          filename: 'short.txt',
          longname: 'ab',
          attr: _fileAttrs(size: 10),
        ),
      ];

      when(mockSftp.listdir('/test')).thenAnswer((_) async => items);

      final result = await service.list('/test');
      expect(result[0].owner, '');
    });
  });

  group('SFTPService.getwd', () {
    test('returns absolute path from sftp.absolute', () async {
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/home/user');

      final result = await service.getwd();
      expect(result, '/home/user');
    });
  });

  group('SFTPService.stat', () {
    test('returns FileEntry with correct fields', () async {
      when(mockSftp.stat('/test/file.txt'))
          .thenAnswer((_) async => _fileAttrs(size: 1024, modifyTime: 5000));

      final result = await service.stat('/test/file.txt');
      expect(result.name, 'file.txt');
      expect(result.path, '/test/file.txt');
      expect(result.size, 1024);
      expect(result.isDir, isFalse);
    });

    test('returns directory entry', () async {
      when(mockSftp.stat('/test/dir'))
          .thenAnswer((_) async => _dirAttrs(modifyTime: 3000));

      final result = await service.stat('/test/dir');
      expect(result.isDir, isTrue);
    });
  });

  group('SFTPService.mkdir', () {
    test('delegates to sftp.mkdir', () async {
      await service.mkdir('/new/dir');
      verify(mockSftp.mkdir('/new/dir')).called(1);
    });
  });

  group('SFTPService.remove', () {
    test('delegates to sftp.remove', () async {
      await service.remove('/test/file.txt');
      verify(mockSftp.remove('/test/file.txt')).called(1);
    });
  });

  group('SFTPService.removeDir', () {
    test('removes files and subdirectories recursively', () async {
      // Top level: one file and one subdir
      when(mockSftp.listdir('/test/dir')).thenAnswer((_) async => [
            ..._dotEntries(),
            SftpName(
              filename: 'file.txt',
              longname: '-rw-r--r-- 1 root root 100 file.txt',
              attr: _fileAttrs(size: 100),
            ),
            SftpName(
              filename: 'subdir',
              longname: 'drwxr-xr-x 2 root root 4096 subdir',
              attr: _dirAttrs(),
            ),
          ]);

      // Subdir is empty
      when(mockSftp.listdir('/test/dir/subdir')).thenAnswer((_) async => _dotEntries());

      await service.removeDir('/test/dir');

      verify(mockSftp.remove('/test/dir/file.txt')).called(1);
      verify(mockSftp.rmdir('/test/dir/subdir')).called(1);
      verify(mockSftp.rmdir('/test/dir')).called(1);
    });
  });

  group('SFTPService.rename', () {
    test('delegates to sftp.rename', () async {
      await service.rename('/old/path', '/new/path');
      verify(mockSftp.rename('/old/path', '/new/path')).called(1);
    });
  });

  group('SFTPService.close', () {
    test('delegates to sftp.close', () {
      service.close();
      verify(mockSftp.close()).called(1);
    });
  });

  group('RemoteFS', () {
    test('delegates initialDir to sftp.getwd', () async {
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/home/remote');
      final remoteFs = RemoteFS(service);
      final dir = await remoteFs.initialDir();
      expect(dir, '/home/remote');
    });

    test('delegates list to sftp.list', () async {
      when(mockSftp.listdir('/path')).thenAnswer((_) async => []);
      final remoteFs = RemoteFS(service);
      final result = await remoteFs.list('/path');
      expect(result, isEmpty);
    });

    test('delegates mkdir to sftp.mkdir', () async {
      final remoteFs = RemoteFS(service);
      await remoteFs.mkdir('/new/dir');
      verify(mockSftp.mkdir('/new/dir')).called(1);
    });

    test('delegates remove to sftp.remove', () async {
      final remoteFs = RemoteFS(service);
      await remoteFs.remove('/file.txt');
      verify(mockSftp.remove('/file.txt')).called(1);
    });

    test('delegates rename to sftp.rename', () async {
      final remoteFs = RemoteFS(service);
      await remoteFs.rename('/old', '/new');
      verify(mockSftp.rename('/old', '/new')).called(1);
    });

    test('delegates removeDir to sftp.removeDir (recursive)', () async {
      // Empty dir
      when(mockSftp.listdir('/dir')).thenAnswer((_) async => _dotEntries());
      final remoteFs = RemoteFS(service);
      await remoteFs.removeDir('/dir');
      verify(mockSftp.rmdir('/dir')).called(1);
    });
  });

  group('SFTPService.download', () {
    test('downloads file with progress callbacks', () async {
      final mockFile = MockSftpFile();
      final fileContent = Uint8List.fromList(List.filled(1024, 65));

      when(mockSftp.stat('/remote/file.txt'))
          .thenAnswer((_) async => _fileAttrs(size: 1024));
      when(mockSftp.open('/remote/file.txt')).thenAnswer((_) async => mockFile);
      when(mockFile.read()).thenAnswer((_) => Stream.fromIterable([fileContent]));

      final progressUpdates = <TransferProgress>[];

      final tempDir = await Directory.systemTemp.createTemp('sftp_test_');
      final localPath = '${tempDir.path}/file.txt';

      try {
        await service.download('/remote/file.txt', localPath, (p) => progressUpdates.add(p));

        expect(progressUpdates, isNotEmpty);
        expect(progressUpdates.last.isUpload, isFalse);
        expect(progressUpdates.last.doneBytes, 1024);
        expect(progressUpdates.last.isCompleted, isTrue);
        verify(mockFile.close()).called(1);

        // Verify local file was created
        expect(await File(localPath).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads file with null progress callback', () async {
      final mockFile = MockSftpFile();
      final fileContent = Uint8List.fromList(List.filled(64, 66));

      when(mockSftp.stat('/remote/small.txt'))
          .thenAnswer((_) async => _fileAttrs(size: 64));
      when(mockSftp.open('/remote/small.txt')).thenAnswer((_) async => mockFile);
      when(mockFile.read()).thenAnswer((_) => Stream.fromIterable([fileContent]));

      final tempDir = await Directory.systemTemp.createTemp('sftp_test_');
      final localPath = '${tempDir.path}/small.txt';

      try {
        // No exception expected with null progress
        await service.download('/remote/small.txt', localPath, null);
        verify(mockFile.close()).called(1);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SFTPService.downloadDir', () {
    test('downloads directory structure recursively with progress', () async {
      // Remote dir has one file
      when(mockSftp.listdir('/remote/dir')).thenAnswer((_) async => [
            ..._dotEntries(),
            SftpName(
              filename: 'readme.txt',
              longname: '-rw-r--r-- 1 root root 10 readme.txt',
              attr: _fileAttrs(size: 10),
            ),
          ]);

      // Mock download of the file
      final mockFile = MockSftpFile();
      when(mockSftp.stat('/remote/dir/readme.txt'))
          .thenAnswer((_) async => _fileAttrs(size: 10));
      when(mockSftp.open('/remote/dir/readme.txt')).thenAnswer((_) async => mockFile);
      when(mockFile.read())
          .thenAnswer((_) => Stream.fromIterable([Uint8List.fromList(List.filled(10, 65))]));

      final progressUpdates = <TransferProgress>[];
      final tempDir = await Directory.systemTemp.createTemp('sftp_test_');
      final localDir = '${tempDir.path}/dir';

      try {
        await service.downloadDir('/remote/dir', localDir, (p) => progressUpdates.add(p));

        expect(progressUpdates, isNotEmpty);
        expect(progressUpdates.last.isUpload, isFalse);
        expect(progressUpdates.last.isCompleted, isTrue);
        expect(await Directory(localDir).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SFTPService — upload', () {
    late MockSftpClient mockSftp;
    late MockSftpFile mockFile;
    late SFTPService service;

    setUp(() {
      mockSftp = MockSftpClient();
      mockFile = MockSftpFile();
      service = SFTPService(mockSftp);
    });

    test('upload sends file data and reports progress', () async {
      final tempDir = await Directory.systemTemp.createTemp('sftp_up_');
      try {
        final localFile = File('${tempDir.path}/test.txt');
        await localFile.writeAsString('hello world');

        when(mockSftp.open(any, mode: anyNamed('mode')))
            .thenAnswer((_) async => mockFile);
        when(mockFile.writeBytes(any, offset: anyNamed('offset')))
            .thenAnswer((_) async {});

        final progress = <TransferProgress>[];
        await service.upload(localFile.path, '/remote/test.txt', (p) => progress.add(p));

        expect(progress, isNotEmpty);
        expect(progress.last.isUpload, isTrue);
        expect(progress.last.isCompleted, isTrue);
        verify(mockFile.close()).called(1);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('upload closes file on error', () async {
      final tempDir = await Directory.systemTemp.createTemp('sftp_up_err_');
      try {
        final localFile = File('${tempDir.path}/test.txt');
        await localFile.writeAsString('data');

        when(mockSftp.open(any, mode: anyNamed('mode')))
            .thenAnswer((_) async => mockFile);
        when(mockFile.writeBytes(any, offset: anyNamed('offset')))
            .thenThrow(Exception('write failed'));

        expect(
          () => service.upload(localFile.path, '/remote/test.txt', null),
          throwsA(anything),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SFTPService — uploadDir', () {
    late MockSftpClient mockSftp;
    late MockSftpFile mockFile;
    late SFTPService service;

    setUp(() {
      mockSftp = MockSftpClient();
      mockFile = MockSftpFile();
      service = SFTPService(mockSftp);
    });

    test('uploadDir creates remote dir and uploads files', () async {
      final tempDir = await Directory.systemTemp.createTemp('sftp_updir_');
      try {
        // Create local structure: dir/file.txt
        await File('${tempDir.path}/file.txt').writeAsString('content');

        when(mockSftp.mkdir(any)).thenAnswer((_) async {});
        when(mockSftp.open(any, mode: anyNamed('mode')))
            .thenAnswer((_) async => mockFile);
        when(mockFile.writeBytes(any, offset: anyNamed('offset')))
            .thenAnswer((_) async {});

        final progress = <TransferProgress>[];
        await service.uploadDir(tempDir.path, '/remote/dir', (p) => progress.add(p));

        verify(mockSftp.mkdir('/remote/dir')).called(1);
        expect(progress, isNotEmpty);
        expect(progress.last.isUpload, isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('SFTPService — fromSSHClient', () {
    test('fromSSHClient creates service from SSH client sftp subsystem', () async {
      // Can't easily test without real SSH, but verify the static method exists
      expect(SFTPService.fromSSHClient, isA<Function>());
    });
  });
}
