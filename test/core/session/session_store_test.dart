import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

// Phase 4.2 stage 6: SessionStore now reads/writes through FRB
// (`lfs_core.db`). flutter_test does not load the native bridge, so
// the persistence-asserting unit tests that round-tripped through
// drift's in-memory DB no longer apply — equivalent coverage moves
// to integration_test. Same precedent as the dartssh2 →
// MockSshTransport sweep.

Session _makeSession({
  String id = 'test-id',
  String label = 'Test',
  String folder = '',
}) {
  return Session(
    id: id,
    label: label,
    folder: folder,
    server: const ServerAddress(host: 'example.com', user: 'root'),
    auth: const SessionAuth(),
  );
}

void main() {
  group('SessionStore (no-DB sentinels)', () {
    test('load returns empty when DB is unreachable', () async {
      final store = SessionStore();
      expect(await store.load(), isEmpty);
    });

    test('loadPortForwards returns empty when DB is unreachable', () async {
      final store = SessionStore();
      expect(await store.loadPortForwards('whatever'), isEmpty);
    });

    test('add validates input even without a DB', () async {
      final store = SessionStore();
      // Empty host / user fails validate(); the throw should fire
      // before any FRB call so the test runner can observe it.
      expect(
        () => store.add(
          Session(
            id: 's1',
            label: 'broken',
            folder: '',
            server: const ServerAddress(host: '', user: ''),
            auth: const SessionAuth(),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('SessionStore.filterSessions (pure)', () {
    test('returns input unchanged for empty query', () {
      final all = [_makeSession(id: 'a'), _makeSession(id: 'b')];
      expect(SessionStore.filterSessions(all, ''), all);
    });

    test('matches case-insensitively against label / folder / host / user', () {
      final all = [
        _makeSession(id: 'a', label: 'Frontend Web', folder: 'Production/EU'),
        _makeSession(id: 'b', label: 'API Backend', folder: 'Production/US'),
      ];
      expect(SessionStore.filterSessions(all, 'frontend').single.id, 'a');
      expect(SessionStore.filterSessions(all, 'us').single.id, 'b');
    });
  });
}
