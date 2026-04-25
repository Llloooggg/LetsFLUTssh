import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_fs.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';

/// Mock FileSystem for testing SFTPInitResult.
class _MockFS implements FileSystem {
  @override
  Future<String> initialDir() async => '/test';
  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<int> dirSize(String path) async => 0;
}

/// Configurable in-memory `RemoteSftpFs` for the init tests. Each
/// behaviour the tests exercise (default cwd, throwing on `getwd`,
/// recording `close`) is wired through public flags so the fixtures
/// stay tight.
class _FakeSftpFs implements RemoteSftpFs {
  String cwd;
  Object? getwdError;
  bool closed = false;

  _FakeSftpFs({this.cwd = '/remote'});

  @override
  Future<String> getwd() async {
    if (getwdError != null) throw getwdError!;
    return cwd;
  }

  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<bool> exists(String path) async => false;
  @override
  Future<void> mkdir(String path) async {}
  @override
  Future<void> remove(String path) async {}
  @override
  Future<void> removeEmptyDir(String path) async {}
  @override
  Future<void> rename(String oldPath, String newPath) async {}
  @override
  Future<void> upload(
    String localPath,
    String remotePath,
    void Function(TransferProgress)? onProgress,
  ) async {}
  @override
  Future<void> download(
    String remotePath,
    String localPath,
    void Function(TransferProgress)? onProgress,
  ) async {}
  @override
  Future<void> uploadDir(
    String localDir,
    String remoteDir,
    void Function(TransferProgress)? onProgress,
  ) async {}
  @override
  Future<void> downloadDir(
    String remoteDir,
    String localDir,
    void Function(TransferProgress)? onProgress,
  ) async {}
  @override
  Future<void> removeDir(String path) async {}
  @override
  void close() {
    closed = true;
  }
}

void main() {
  group('SFTPInitializer.init', () {
    test('throws StateError when transport is null (no factory)', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'localhost', user: 'user'),
        ),
        state: SSHConnectionState.disconnected,
      );

      expect(() => SFTPInitializer.init(conn), throwsA(isA<StateError>()));
    });

    test('succeeds with injectable filesystemFactory', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'localhost', user: 'user'),
        ),
        state: SSHConnectionState.disconnected,
      );

      final fakeFs = _FakeSftpFs(cwd: '/home/remote');
      final result = await SFTPInitializer.init(
        conn,
        filesystemFactory: (_) async => fakeFs,
        localFsFactory: () => _MockFS(),
      );

      expect(result.localCtrl.label, 'Local');
      expect(result.remoteCtrl.label, 'Remote');
      expect(result.filesystem, same(fakeFs));

      result.dispose();
    });

    test('controllers are initialized after init', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );

      final result = await SFTPInitializer.init(
        conn,
        filesystemFactory: (_) async => _FakeSftpFs(cwd: '/remote'),
        localFsFactory: () => _MockFS(),
      );

      // Controllers should be initialized (currentPath set)
      expect(result.localCtrl.currentPath, '/test');
      expect(result.remoteCtrl.currentPath, '/remote');

      result.dispose();
    });

    test('dispose closes sftp service', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );

      final fakeFs = _FakeSftpFs(cwd: '/r');
      final result = await SFTPInitializer.init(
        conn,
        filesystemFactory: (_) async => fakeFs,
        localFsFactory: () => _MockFS(),
      );

      result.dispose();
      expect(fakeFs.closed, isTrue);
    });

    test('controllers are disposed when init() fails', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );

      // Remote controller init will fail — getwd throws.
      final fakeFs = _FakeSftpFs()..getwdError = Exception('SFTP init failure');

      await expectLater(
        SFTPInitializer.init(
          conn,
          filesystemFactory: (_) async => fakeFs,
          localFsFactory: () => _MockFS(),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SFTPInitResult', () {
    test('dispose() disposes both controllers', () {
      final localCtrl = FilePaneController(fs: _MockFS(), label: 'Local');
      final remoteCtrl = FilePaneController(fs: _MockFS(), label: 'Remote');

      localCtrl.dispose();
      remoteCtrl.dispose();

      // After dispose, addListener should throw
      expect(() => localCtrl.addListener(() {}), throwsA(isA<FlutterError>()));
      expect(() => remoteCtrl.addListener(() {}), throwsA(isA<FlutterError>()));
    });

    test('controllers have correct labels', () {
      final localCtrl = FilePaneController(fs: _MockFS(), label: 'Local');
      final remoteCtrl = FilePaneController(fs: _MockFS(), label: 'Remote');

      expect(localCtrl.label, 'Local');
      expect(remoteCtrl.label, 'Remote');

      localCtrl.dispose();
      remoteCtrl.dispose();
    });

    test('storagePermissionDenied defaults to false', () async {
      final conn = Connection(
        id: 'perm-1',
        label: 'Test',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: 'h', user: 'u'),
        ),
      );

      final result = await SFTPInitializer.init(
        conn,
        filesystemFactory: (_) async => _FakeSftpFs(cwd: '/r'),
        localFsFactory: () => _MockFS(),
      );

      expect(result.storagePermissionDenied, isFalse);
      result.dispose();
    });

    test('storagePermissionDenied can be set to true', () {
      final localCtrl = FilePaneController(fs: _MockFS(), label: 'Local');
      final remoteCtrl = FilePaneController(fs: _MockFS(), label: 'Remote');
      final fakeFs = _FakeSftpFs();

      final result = SFTPInitResult(
        localCtrl: localCtrl,
        remoteCtrl: remoteCtrl,
        filesystem: fakeFs,
        storagePermissionDenied: true,
      );

      expect(result.storagePermissionDenied, isTrue);
      result.dispose();
    });
  });
}
