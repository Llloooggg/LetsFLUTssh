import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';

void main() {
  Connection makeConn({String label = 'Server'}) {
    return Connection(
      id: 'conn-1',
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
    );
  }

  group('TabKind', () {
    test('has terminal and sftp', () {
      expect(TabKind.values.length, 2);
      expect(TabKind.values, contains(TabKind.terminal));
      expect(TabKind.values, contains(TabKind.sftp));
    });
  });

  group('TabEntry', () {
    test('stores all fields', () {
      final conn = makeConn();
      final tab = TabEntry(
        id: 'tab-1',
        label: 'My Tab',
        connection: conn,
        kind: TabKind.terminal,
      );
      expect(tab.id, 'tab-1');
      expect(tab.label, 'My Tab');
      expect(tab.connection, conn);
      expect(tab.kind, TabKind.terminal);
    });

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

    test('can create terminal and sftp tabs', () {
      final conn = makeConn();
      final terminal = TabEntry(
        id: 't1', label: 'SSH', connection: conn, kind: TabKind.terminal,
      );
      final sftp = TabEntry(
        id: 't2', label: 'SFTP', connection: conn, kind: TabKind.sftp,
      );
      expect(terminal.kind, TabKind.terminal);
      expect(sftp.kind, TabKind.sftp);
    });
  });
}
