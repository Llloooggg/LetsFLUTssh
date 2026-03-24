import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
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
}

void main() {
  group('SFTPInitializer.init', () {
    test('throws StateError when sshConnection is null', () async {
      final conn = Connection(
        id: 'test',
        label: 'Test',
        sshConfig: const SSHConfig(host: 'localhost', user: 'user'),
        sshConnection: null,
        state: SSHConnectionState.disconnected,
      );

      expect(
        () => SFTPInitializer.init(conn),
        throwsA(isA<StateError>()),
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
