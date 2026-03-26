import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_tree.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('SessionTree', () {
    test('empty list produces empty tree', () {
      final tree = SessionTree.build([]);
      expect(tree, isEmpty);
    });

    test('sessions without groups appear at root', () {
      final sessions = [
        Session(label: 'B', server: const ServerAddress(host: 'b.com', user: 'r')),
        Session(label: 'A', server: const ServerAddress(host: 'a.com', user: 'r')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree.length, 2);
      expect(tree[0].name, 'A'); // sorted
      expect(tree[1].name, 'B');
      expect(tree[0].isSession, true);
    });

    test('sessions with groups create nested folders', () {
      final sessions = [
        Session(label: 'nginx', group: 'Production/Web', server: const ServerAddress(host: 'x', user: 'r')),
        Session(label: 'db', group: 'Production/DB', server: const ServerAddress(host: 'y', user: 'r')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree.length, 1); // "Production" folder
      expect(tree[0].name, 'Production');
      expect(tree[0].isGroup, true);
      expect(tree[0].children.length, 2); // DB, Web folders
      expect(tree[0].children[0].name, 'DB'); // sorted
      expect(tree[0].children[1].name, 'Web');
      expect(tree[0].children[0].children[0].name, 'db');
      expect(tree[0].children[1].children[0].name, 'nginx');
    });

    test('groups appear before sessions at same level', () {
      final sessions = [
        Session(label: 'standalone', server: const ServerAddress(host: 'x', user: 'r')),
        Session(label: 'grouped', group: 'Servers', server: const ServerAddress(host: 'y', user: 'r')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree.length, 2);
      expect(tree[0].isGroup, true); // "Servers" folder first
      expect(tree[0].name, 'Servers');
      expect(tree[1].isSession, true); // "standalone" after
    });

    test('same group shared across sessions', () {
      final sessions = [
        Session(label: 'web1', group: 'Prod', server: const ServerAddress(host: 'w1', user: 'r')),
        Session(label: 'web2', group: 'Prod', server: const ServerAddress(host: 'w2', user: 'r')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree.length, 1);
      expect(tree[0].children.length, 2);
      expect(tree[0].children[0].name, 'web1');
      expect(tree[0].children[1].name, 'web2');
    });

    test('deeply nested groups', () {
      final sessions = [
        Session(label: 'server', group: 'A/B/C', server: const ServerAddress(host: 'x', user: 'r')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree[0].name, 'A');
      expect(tree[0].children[0].name, 'B');
      expect(tree[0].children[0].children[0].name, 'C');
      expect(tree[0].children[0].children[0].children[0].name, 'server');
    });

    test('session with empty label uses displayName', () {
      final sessions = [
        Session(label: '', server: const ServerAddress(host: '10.0.0.1', user: 'root')),
      ];
      final tree = SessionTree.build(sessions);
      expect(tree[0].name, 'root@10.0.0.1:22');
    });
  });
}
