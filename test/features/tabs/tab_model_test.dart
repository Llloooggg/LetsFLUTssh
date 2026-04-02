import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';

void main() {
  Connection makeConn({String label = 'Server'}) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(server: ServerAddress(host: '10.0.0.1', user: 'root')),
    );
  }

  group('TabEntry', () {
    test('copyWith changes label only', () {
      final conn = makeConn();
      final tab = TabEntry(
        id: 'tab-1',
        label: 'Original',
        connection: conn,
        kind: TabKind.sftp,
      );
      final copy = tab.copyWith(label: 'Updated');
      expect(copy.id, 'tab-1');
      expect(copy.label, 'Updated');
      expect(copy.connection, conn);
      expect(copy.kind, TabKind.sftp);
    });

    test('copyWith without arguments keeps label', () {
      final conn = makeConn();
      final tab = TabEntry(
        id: 'tab-1',
        label: 'Original',
        connection: conn,
        kind: TabKind.terminal,
      );
      final copy = tab.copyWith();
      expect(copy.label, 'Original');
    });

  });
}
