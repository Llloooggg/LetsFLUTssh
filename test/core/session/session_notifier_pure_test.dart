import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/port_forwards_dao.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import '../../helpers/frb_bootstrap.dart';

// SessionNotifier reads/writes through FRB (`lfs_core.db`). flutter_test
// does not load the native bridge, so the persistence-asserting unit
// tests that round-tripped through drift's in-memory DB no longer
// apply — equivalent coverage moves to integration_test. Same
// precedent as the dartssh2 → MockSshTransport sweep.

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
  // Session.validate (called by SessionNotifier.add) routes through
  // `lfs_core::sessions` — bootstrap FRB so the validation path runs.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('SessionNotifier (no-DB sentinels)', () {
    test('load resolves to empty when DB is unreachable', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionProvider.notifier);
      await notifier.load();
      expect(container.read(sessionProvider), isEmpty);
    });

    test('loadPortForwards returns empty when DB is unreachable', () async {
      expect(await loadPortForwards('whatever'), isEmpty);
    });

    test('add validates input even without a DB', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionProvider.notifier);
      // Empty host / user fails validate(); the throw should fire
      // before any FRB call so the test runner can observe it.
      expect(
        () => notifier.add(
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

  group('filterSessions (pure)', () {
    test('returns input unchanged for empty query', () {
      final all = [_makeSession(id: 'a'), _makeSession(id: 'b')];
      expect(filterSessions(all, ''), all);
    });

    test('matches case-insensitively against label / folder / host / user', () {
      final all = [
        _makeSession(id: 'a', label: 'Frontend Web', folder: 'Production/EU'),
        _makeSession(id: 'b', label: 'API Backend', folder: 'Production/US'),
      ];
      expect(filterSessions(all, 'frontend').single.id, 'a');
      expect(filterSessions(all, 'us').single.id, 'b');
    });
  });
}
