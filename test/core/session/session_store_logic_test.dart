import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';

/// Tests for SessionStore's in-memory algorithms (search, groups, renameGroup,
/// deleteGroup, countSessionsInGroup) without file I/O or path_provider.
///
/// These test the pure logic that SessionStore applies to its _sessions list.
void main() {
  late List<Session> sessions;
  late Set<String> emptyGroups;

  Session makeSession({
    String? id,
    String label = '',
    String group = '',
    String host = 'host',
    String user = 'user',
  }) {
    return Session(
      id: id,
      label: label,
      group: group,
      host: host,
      user: user,
    );
  }

  // Mirrors SessionStore.search()
  List<Session> search(String query) {
    if (query.isEmpty) return sessions;
    final q = query.toLowerCase();
    return sessions.where((s) {
      return s.label.toLowerCase().contains(q) ||
          s.group.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q) ||
          s.user.toLowerCase().contains(q);
    }).toList();
  }

  // Mirrors SessionStore.groups()
  List<String> groups() {
    final g = sessions.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList();
    g.sort();
    return g;
  }

  // Mirrors SessionStore.byGroup()
  List<Session> byGroup(String group) {
    return sessions.where((s) => s.group == group).toList();
  }

  // Mirrors SessionStore.countSessionsInGroup()
  int countSessionsInGroup(String groupPath) {
    return sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .length;
  }

  // Mirrors SessionStore.renameGroup()
  void renameGroup(String oldPath, String newPath) {
    if (oldPath.isEmpty || newPath.isEmpty || oldPath == newPath) return;
    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      if (s.group == oldPath) {
        sessions[i] = s.copyWith(group: newPath);
      } else if (s.group.startsWith('$oldPath/')) {
        sessions[i] = s.copyWith(group: newPath + s.group.substring(oldPath.length));
      }
    }
    final toRemove = <String>[];
    final toAdd = <String>[];
    for (final g in emptyGroups) {
      if (g == oldPath) {
        toRemove.add(g);
        toAdd.add(newPath);
      } else if (g.startsWith('$oldPath/')) {
        toRemove.add(g);
        toAdd.add(newPath + g.substring(oldPath.length));
      }
    }
    emptyGroups.removeAll(toRemove);
    emptyGroups.addAll(toAdd);
  }

  // Mirrors SessionStore.deleteGroup()
  void deleteGroup(String groupPath) {
    if (groupPath.isEmpty) return;
    sessions.removeWhere(
      (s) => s.group == groupPath || s.group.startsWith('$groupPath/'),
    );
    emptyGroups.removeWhere(
      (g) => g == groupPath || g.startsWith('$groupPath/'),
    );
  }

  setUp(() {
    sessions = [
      makeSession(id: '1', label: 'nginx1', group: 'Production/Web', host: '10.0.0.1', user: 'root'),
      makeSession(id: '2', label: 'nginx2', group: 'Production/Web', host: '10.0.0.2', user: 'root'),
      makeSession(id: '3', label: 'db-master', group: 'Production/DB', host: '10.0.1.1', user: 'admin'),
      makeSession(id: '4', label: 'staging', group: 'Staging', host: '192.168.1.1', user: 'deploy'),
      makeSession(id: '5', label: 'local-dev', group: '', host: 'localhost', user: 'dev'),
    ];
    emptyGroups = {'Archive', 'Production/Cache'};
  });

  group('search', () {
    test('empty query returns all sessions', () {
      expect(search(''), hasLength(5));
    });

    test('search by label', () {
      final results = search('nginx');
      expect(results, hasLength(2));
      expect(results.every((s) => s.label.contains('nginx')), isTrue);
    });

    test('search by host', () {
      final results = search('10.0.0');
      expect(results, hasLength(2));
    });

    test('search by group', () {
      final results = search('production');
      expect(results, hasLength(3)); // Production/Web x2 + Production/DB x1
    });

    test('search by user', () {
      final results = search('root');
      expect(results, hasLength(2));
    });

    test('search is case-insensitive', () {
      expect(search('NGINX'), hasLength(2));
      expect(search('Root'), hasLength(2));
    });

    test('search with no matches returns empty', () {
      expect(search('nonexistent'), isEmpty);
    });
  });

  group('groups', () {
    test('returns unique groups sorted', () {
      final g = groups();
      expect(g, ['Production/DB', 'Production/Web', 'Staging']);
    });

    test('excludes empty group paths', () {
      final g = groups();
      expect(g, isNot(contains('')));
    });
  });

  group('byGroup', () {
    test('returns sessions in specific group', () {
      final result = byGroup('Production/Web');
      expect(result, hasLength(2));
    });

    test('returns empty for non-existent group', () {
      expect(byGroup('NonExistent'), isEmpty);
    });

    test('exact match only (not subgroups)', () {
      // 'Production' has no direct sessions, only subgroups
      expect(byGroup('Production'), isEmpty);
    });
  });

  group('countSessionsInGroup', () {
    test('counts sessions in group and subgroups', () {
      // Production has Production/Web (2) + Production/DB (1) = 3
      expect(countSessionsInGroup('Production'), 3);
    });

    test('counts exact group only when no subgroups', () {
      expect(countSessionsInGroup('Staging'), 1);
    });

    test('returns 0 for non-existent group', () {
      expect(countSessionsInGroup('NonExistent'), 0);
    });
  });

  group('renameGroup', () {
    test('renames group and updates sessions', () {
      renameGroup('Production/Web', 'Production/Frontend');
      expect(sessions[0].group, 'Production/Frontend');
      expect(sessions[1].group, 'Production/Frontend');
      // Other sessions unchanged
      expect(sessions[2].group, 'Production/DB');
    });

    test('renames subgroups too', () {
      renameGroup('Production', 'Prod');
      expect(sessions[0].group, 'Prod/Web');
      expect(sessions[1].group, 'Prod/Web');
      expect(sessions[2].group, 'Prod/DB');
      // Staging unchanged
      expect(sessions[3].group, 'Staging');
    });

    test('renames empty groups', () {
      renameGroup('Production', 'Prod');
      expect(emptyGroups, contains('Prod/Cache'));
      expect(emptyGroups, isNot(contains('Production/Cache')));
      // Archive unaffected
      expect(emptyGroups, contains('Archive'));
    });

    test('no-op when old equals new', () {
      final before = sessions.map((s) => s.group).toList();
      renameGroup('Production', 'Production');
      final after = sessions.map((s) => s.group).toList();
      expect(after, before);
    });

    test('no-op when empty paths', () {
      final before = sessions.map((s) => s.group).toList();
      renameGroup('', 'New');
      expect(sessions.map((s) => s.group).toList(), before);
    });
  });

  group('deleteGroup', () {
    test('deletes sessions in group', () {
      deleteGroup('Production/Web');
      expect(sessions, hasLength(3)); // removed nginx1, nginx2
      expect(sessions.any((s) => s.group == 'Production/Web'), isFalse);
    });

    test('deletes sessions in subgroups', () {
      deleteGroup('Production');
      expect(sessions, hasLength(2)); // removed Web x2 + DB x1
      expect(sessions.any((s) => s.group.startsWith('Production')), isFalse);
    });

    test('deletes empty groups under path', () {
      deleteGroup('Production');
      expect(emptyGroups, isNot(contains('Production/Cache')));
      expect(emptyGroups, contains('Archive'));
    });

    test('no-op for empty string', () {
      deleteGroup('');
      expect(sessions, hasLength(5));
    });

    test('no-op for non-existent group', () {
      deleteGroup('DoesNotExist');
      expect(sessions, hasLength(5));
    });
  });

  group('Session.toJson excludes secrets', () {
    test('toJson does not include password, keyData, passphrase', () {
      final s = Session(
        label: 'test',
        host: 'host',
        user: 'user',
        password: 'secret',
        keyData: 'PEM-DATA',
        passphrase: 'pass',
      );
      final json = s.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json.containsKey('key_data'), isFalse);
      expect(json.containsKey('passphrase'), isFalse);
    });

    test('toJsonWithCredentials includes secrets', () {
      final s = Session(
        label: 'test',
        host: 'host',
        user: 'user',
        password: 'secret',
        keyData: 'PEM-DATA',
        passphrase: 'pass',
      );
      final json = s.toJsonWithCredentials();
      expect(json['password'], 'secret');
      expect(json['key_data'], 'PEM-DATA');
      expect(json['passphrase'], 'pass');
    });
  });

  group('Session.fromJson handles legacy credentials', () {
    test('fromJson reads password from JSON (legacy format)', () {
      final s = Session.fromJson({
        'id': 'test-id',
        'host': 'h',
        'user': 'u',
        'password': 'pw',
        'key_data': 'kd',
        'passphrase': 'pp',
      });
      expect(s.password, 'pw');
      expect(s.keyData, 'kd');
      expect(s.passphrase, 'pp');
    });

    test('fromJson defaults missing credentials to empty', () {
      final s = Session.fromJson({
        'id': 'test-id',
        'host': 'h',
        'user': 'u',
      });
      expect(s.password, '');
      expect(s.keyData, '');
      expect(s.passphrase, '');
    });
  });
}
