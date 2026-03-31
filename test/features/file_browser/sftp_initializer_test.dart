import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/core/sftp/sftp_client.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/file_browser/file_browser_controller.dart';
import 'package:letsflutssh/features/file_browser/sftp_initializer.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<SftpClient>()])
import 'sftp_initializer_test.mocks.dart';

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

void main() {
  group('SFTPInitializer.init', () {
    test('throws StateError when sshConnection is null (no factory)', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'localhost', user: 'user')),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      expect(
        () => SFTPInitializer.init(conn),
        throwsA(isA<StateError>()),
      );
    });

    test('succeeds with injectable sftpServiceFactory', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'localhost', user: 'user')),
        sshConnection: null,  // null is OK — factory bypasses SSH
        state: SSHConnectionState.disconnected,
      );

      final mockSftp = MockSftpClient();
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/home/remote');
      when(mockSftp.listdir(any)).thenAnswer((_) async => []);

      final result = await SFTPInitializer.init(
        conn,
        sftpServiceFactory: (_) async => SFTPService(mockSftp),
        localFsFactory: () => _MockFS(),
      );

      expect(result.localCtrl.label, 'Local');
      expect(result.remoteCtrl.label, 'Remote');
      expect(result.sftpService, isNotNull);

      result.dispose();
    });

    test('controllers are initialized after init', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
      );

      final mockSftp = MockSftpClient();
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/remote');
      when(mockSftp.listdir(any)).thenAnswer((_) async => []);

      final result = await SFTPInitializer.init(
        conn,
        sftpServiceFactory: (_) async => SFTPService(mockSftp),
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
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
      );

      final mockSftp = MockSftpClient();
      when(mockSftp.absolute('.')).thenAnswer((_) async => '/r');
      when(mockSftp.listdir(any)).thenAnswer((_) async => []);

      final result = await SFTPInitializer.init(
        conn,
        sftpServiceFactory: (_) async => SFTPService(mockSftp),
        localFsFactory: () => _MockFS(),
      );

      result.dispose();
      verify(mockSftp.close()).called(1);
    });

    test('controllers are disposed when init() fails', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(server: ServerAddress(host: 'h', user: 'u')),
      );

      final mockSftp = MockSftpClient();
      // Remote controller init will fail — absolute('.') throws
      when(mockSftp.absolute('.')).thenThrow(Exception('SFTP init failure'));
      when(mockSftp.listdir(any)).thenAnswer((_) async => []);

      await expectLater(
        SFTPInitializer.init(
          conn,
          sftpServiceFactory: (_) async => SFTPService(mockSftp),
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
  });
}
